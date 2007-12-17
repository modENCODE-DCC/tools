#!/usr/bin/perl
# Bot for automation of copy from
# Indiana CGB website to modENCODE private wiki
#
# 2007 - François Guillier - University of Cambridge for modENCODE
# Licence TBC

use strict;
use Perlwikipedia;
use Config::IniFiles;
use XML::Simple;

#
# Global variables
#

my $Debug; # Debug on/off
my $Cfg; # Config INI file
my $Mech; # Needs to be global to preserve the cookie Jar

#
# Returns a UserAgent string (for logging purpose)
#
sub getAgent
{
    # Subversion Revision
    my $rev="r".substr('$Rev$',6,-2);

    return "CGB Wiki Bot (".$rev.")";
}

#
# Connect and read main page from source
#
sub connectCGBAndGetSourceContent
{
    $Mech=WWW::Mechanize->new("agent" => getAgent());
    $Mech->get("https://".$Cfg->val("source","hostname")."/".
            $Cfg->val("source","path"));

    $Mech->submit_form(
            form_number =>2,
            fields      => {
            os_username => $Cfg->val("source","username"),
            os_password => $Cfg->val("source","password"),
            }
            );

    return split(/\n/,$Mech->content());
}

#
# read a page from server
#
sub getCGBContent
{
    my ($page)=@_;

    $Mech->get("https://".$Cfg->val("source","hostname").$page);
    return $Mech->content();

}

#
# Connect to wiki
#
sub getWikiConnection
{
    my $editor=Perlwikipedia->new(getAgent());
    $editor->set_wiki($Cfg->val("wiki","hostname"),$Cfg->val("wiki","path"));
    $editor->{debug}=$Debug;
    $editor->login($Cfg->val("wiki","username"),$Cfg->val("wiki","password"));

    return $editor;
}

#
# Parse source of main page
#
sub parseSourceMain
{
    my @sourceContent=@_;

    my @RNASources; # RNA sources from CGB
    my $relLine=0;
    my %rna=();

    foreach (@sourceContent)
    {
        # Filtering & extraction from "Frame"
        next unless (m|<td class='confluenceTd'>(.+)</td>|);
        $_=$1;
        $relLine++;
    
        if (/ <a name="RNAsources-(\d+)"><\/a> <b>(\d+)<\/b> /)
        {
            die if ($1 != $2);

            push(@RNASources,{%rna}) if ($rna{"id"});
            %rna=("id" => $1);
            $relLine=0;
            next;
        }

        if ((/ BS(\d+) /) && ($relLine==1))
        {
            $rna{"biosample"}=$1;
            next;
        }

        if ((/ rel="nofollow">([^<]+)<sup>/) && ($relLine==2))
        {
            $rna{"celltype"}=$1;
            $rna{"celltype"} =~ s/&#43;/+/;
            next;
        } elsif ($relLine==2)
        {
            $rna{"sample"}=$_;
            next;
        }


        if ((/ rel="nofollow">([^<]+)<sup>/) && $relLine==3)
        {
            die ("Protocols:".$1." not defined") unless ($Cfg->val("protocols",$1));
            push(@{$rna{"protocols"}},$Cfg->val("protocols",$1));
            $rna{"preparation"}=$1;
            next;
        }

        if (($relLine==7) && ($_ ne "&nbsp;"))
        {
            $rna{"qc"}=();
            foreach my $qc (split(/,/))
            {
                if ($qc =~ m|<a href="(/display/modencode/[^\"]+)"[^>]+>([^<]+)</a>|)
                {
                    push(@{$rna{"qcdata"}},$1);
                    die("QC (protocols):".$2." not defined")
                                       unless ($Cfg->val("protocols",$2));
                    push(@{$rna{"protocols"}},$Cfg->val("protocols",$2));
                }
            }
        }
    }

    push(@RNASources,{%rna}) if ($rna{"id"});

    return @RNASources;
}

#
# Parse source of QC Data page (to locate the image)
#
sub parseSourceQCData
{
    my ($cgbContent)=@_;

    my $wikiContent=0;

    foreach (split(/\n/,$cgbContent))
    {
        if ($wikiContent==0)
        {
            $wikiContent=1 if (m|<div class="wiki-content">|);
            next;
        }

        return $1 if (m|<img src="(/download/attachments/[^\"]+)" align="absmiddle" border="0" />|); #/ (for Vim bug)
    }
    die("Can't locate image in QC Data page ");
}

#
# Cut & Normalise the image path => name
#
sub imagePathToName
{
    my ($path)=@_;

    my $name=substr($path,rindex($path,"/")+1);
    $name =~ tr/ /_/;

    return $name;
}

#
# Transfer images from CGB to Wiki
#
sub transferImages
{
    my $editor=shift;

    foreach (@_)
    {
        my $name=imagePathToName($_);
        my $filename="cache/".$name;
        print "Downloading ".$name."\n" if ($Debug);
        my $img=getCGBContent($_);
        open(F,">".$filename);
        print F $img;
        close(F);

        (length($img) == (-s $filename)) ||
            die ("Error during download of '".imagePathToName($_)."'\n");

        print "uploading ".$name."\n" if ($Debug);

        # Big Hack!!!
        # Emulating a _post_api method as Perlwikipedia doesn't provide
        # anything like this (yet).
        # See http://www.mediawiki.org/wiki/API:Edit_-_Uploading_files

        $editor->{mech}->get("http://".$editor->{host}."/".
                $editor->{path}."/index.php/Special:Upload");

        $editor->{mech}->form_number(1);
        $editor->{mech}->set_fields("wpUploadFile" => $filename);
        $editor->{mech}->tick("wpIgnoreWarning","true");
        $editor->{mech}->click_button("name" => "wpUpload");
    }
}

#
# Retrieve Images from QC Data pages
#
sub retrieveQCImages
{
    my @listQCPages=@_;

    my %QCImages=();
    foreach my $qc (@listQCPages)
    {
        $QCImages{$qc}=parseSourceQCData(getCGBContent($qc));
    }
    return %QCImages;
}

#
# Check if images were already transfered
#
sub getImagesNotInWiki
{
    my ($editor,@QCImages)=@_;

    my (@imagesToTransfer)=();

    foreach (@QCImages)
    {
        # Hack!!!
        # Calling directly the _get_api method as Perlwikipedia doesn't provide
        # anything better (yet).
        my $res=$editor->_get_api("action=query&prop=revisions&titles=Image:".
                imagePathToName($_)."&format=xml");
        next unless ($res);

        my $s=$res->decoded_content;
        $s =~ s/^\s+//;

        my $xml=XMLin($s);
        unless ($xml->{query}->{pages}->{page}->{revisions})
        {
            push(@imagesToTransfer,$_);
        }
    }

    return @imagesToTransfer;
}

#
# Retrieve page from wiki
#
sub getPage
{
    my ($textServer,$marker)=@_;

    my $userPart=0;
    my $textB="";
    my $textH="";

    foreach (split(/\n/,$textServer))
    {
        if ($userPart==0)
        {
            if (/<!--.* $marker .*-->/)
            {
                $userPart=1;
            } else
            {
                $textB.=$_."\n";
            }
        } else
        {
            $textH.=$_."\n";
        }
    }
    return ($textB,$textH);
}

#
# Create/Update an individual RNA wiki page
#
sub updateWiki
{
    my ($editor,$qcImages,%rna)=@_;

    my $article = "Celniker/RNA:".$rna{"id"};
    my $marker="CGB_WIKI_BOT_END_OF_MIRRORED_DATA";
    my ($textB,$textH)=getPage($editor->get_text($article),$marker);

    my $text="= Mirrored data =\n\n";
    $text.="'''RNA ID:''' ".$rna{"id"}."\n\n";
    $text.="'''Biosample:''' ".$rna{"biosample"}."\n\n";
    $text.="'''Protocols:'''\n\n";
    foreach my $p (@{$rna{"protocols"}})
    {
        $text.="*[[".$p."]]\n";
    }
    $text.="\n";

    $text.="'''Cell type:''' [[".$rna{"celltype"}."]]\n\n" if ($rna{"celltype"});
    $text.="'''Cell type:''' ".$rna{"sample"}."\n\n" if ($rna{"sample"});
    $text.="'''Notes:'''\n\n";
    $text.="'''QC data:'''\n\n";
    foreach my $p (@{$rna{"qcdata"}})
    {
        my $proto=substr($p,rindex($p,"/")+1);
        $proto =~ tr /+/ /; #/ (for Vim bug)
        $text.="*[[Image:".imagePathToName($$qcImages{$p})."|".$proto."]]\n";
    }

    print $article.": ".(($text eq $textB)? "No change" : "update").
        " needed\n" if ($Debug);

    return if ($text eq $textB);

    $text.="<!-- ".$marker." DO NOT EDIT ABOVE THIS LINE! -->\n";

    $textH="= Comments =\n";
    $text.=$textH;

    $editor->edit($article, $text,"Synchronisation by ".getAgent());
}

#
# Create/Update the index RNA page
#
sub updateWikiIndex
{
    my ($editor,@RNASources)=@_;

    my $article = "Celniker/RNA_Sources";
    my $textServer=$editor->get_text($article);

    my $text="<!-- WARNING: DO NOT EDIT THIS PAGE MANUALLY! -->\n";
    $text.="= List of RNA Sources =\n\n";
    $text.="''Retrieved from \"The Center for Genomics and Biofinformatics / RNA Source page''\n";

    foreach (@RNASources)
    {
        $text.="* [["."Celniker/RNA:".$$_{"id"}."]] (BS".$$_{"biosample"}.
            ",".$$_{"preparation"}.")\n";
    }

    $text.="\n<!-- WARNING: DO NOT EDIT THIS PAGE MANUALLY! -->\n";

    print $article.": ".(($text eq $textServer)? "No change" : "update").
        " needed\n" if ($Debug);

    return if ($text eq $textServer);

    $editor->edit($article, $text,"Synchronisation by ".getAgent());

}

$Cfg=new Config::IniFiles("-file" => "cgb-wiki-bot.ini");
$Debug=($Cfg->val("general","debug")==1);
my @RNASources=parseSourceMain(connectCGBAndGetSourceContent());

# Extract the QC Pages and build a list
my %listQCPages=();
foreach (@RNASources)
{
    $listQCPages{@{$$_{"qcdata"}}[0]}=1 if ($$_{"qcdata"});
}

my %QCImages=retrieveQCImages(keys %listQCPages);

my $editor=getWikiConnection();

# Update Invidual RNA page
foreach (@RNASources)
{
    updateWiki($editor,\%QCImages,%$_);
}

# Update Index
updateWikiIndex($editor,@RNASources);

# Transfer Images
my @imagesToTransfer=getImagesNotInWiki($editor,values %QCImages);

transferImages($editor,@imagesToTransfer);


# Clean exit
exit(0);
