#!/usr/bin/perl
# Bot for automation of copy from
# Indiana CGB website to modENCODE private wiki
#
# 2007 - François Guillier - University of Cambridge for modENCODE
# Licence TBC

use strict;
use lib::Perlwikipedia;
use Config::IniFiles;

# DEBUG On/Off
# (also affects the caching of the source)
my $Debug=0;

#
# Global variables
#

my $Cfg; # Config INI file

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
sub getSourceContent
{
    my $cache="/tmp/CACHE.html";

    if ($Debug && (-f $cache))
    {
        print "Loading data from cache\n";
        open(F,"<".$cache);
        my @sourceContent=<F>;
        close(F);
        chomp(@sourceContent);
        return @sourceContent;
    }

    my $mech=WWW::Mechanize->new("agent" => getAgent());
    $mech->get($Cfg->val("source","url"));

    $mech->submit_form(
            form_number =>2,
            fields      => {
            os_username => $Cfg->val("source","username"),
            os_password => $Cfg->val("source","password"),
            }
            );

    my $sourceContent=$mech->content();

    if ($Debug)
    {
        print "Retrieved data from CGB server\n";
        open(F,">".$cache);
        print F $sourceContent;
        close(F);
    }

    return split(/\n/,$sourceContent);
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
# Parse source and update wiki as needed
#
sub parseSource
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
                $qc =~ tr /+/ /;
                ###/ vim bug ###
            
                if ($qc =~ / <a href="\/display\/modencode\/([^"]+)" /)
                {
                    die("QC (protocols):".$1." not defined")
                                       unless ($Cfg->val("protocols",$1));
                    push(@{$rna{"protocols"}},$Cfg->val("protocols",$1));
                }
            }
        }
    }

    push(@RNASources,{%rna}) if ($rna{"id"});

    return @RNASources;
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
    my ($editor,%rna)=@_;

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

    print $article.": ".(($text eq $textB)? "No change" : "update").
        " needed\n" if ($Debug);

    return if ($text eq $textB);

    $text.="<!-- ".$marker." DO NOT EDIT ABOVE THIS LINE! -->\n";

    $textH="= Local data =\n";
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

####
$Cfg=new Config::IniFiles("-file" => "cgb-wiki-bot.ini");
my @RNASources=parseSource(getSourceContent());

my $editor=getWikiConnection();

# Update Invidual RNA page
foreach (@RNASources)
{
    updateWiki($editor,%$_);
}

# Update Index
updateWikiIndex($editor,@RNASources);

# Clean exit
exit(0);
