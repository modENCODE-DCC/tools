#!/usr/bin/perl -w
use strict;
use warnings;
use File::Find;





if ($#ARGV != 0 ) {
  print $#ARGV . "  " ;
  print "usage: back_to_pipeline.pl batchfilename\n";
  exit;
}

my $cluster_batchdir = '/.mounts/labs/steinlab/public/modENCODE_validators/batches/'; 
my $cluster_datadir = '/.mounts/labs/steinlab/public/modENCODE_validators/data/' ;
my $pipeline_datadir = '/modencode/raw/data/' ;
my $pipeline_tmpdir = '/modencode/raw/tmp/ellen/data/' ;
my $pipeline_scriptfile = '/modencode/raw/tools/cluster_validator/add_to_pipeline.rb';


##### FIND WHICH FILES NEED TO BE RSYNC'D ##############
{
  my $string_dirlist ; # Holds the files to be compared

  # To be passed to find - add non-directories to the list
  sub make_dirlist {
    my $currfile = $File::Find::name ;
    unless( -d $currfile ) {
      $string_dirlist .= $currfile . "\n" ;
    }
  }

  # And this, actually finds the files. Pass it the project ID.
  # returns files which are in the cluster dir but not the pipeline dir. 
  sub find_files_to_rsync{
    my ($line) = @_;

    $string_dirlist = "" ; # reset for this run of the function

    # Look in both datadirs
    my $src = $cluster_datadir . $line . "/extracted" ;
    my $dest = $pipeline_datadir . $line . "/extracted" ;
    my @search = ($src, $dest);
    find(\&make_dirlist, @search);
    my @resarr = split(/\n/, $string_dirlist);
    # remove the datadir bit
    my @srcfiles = map{ s/$src//; $_; } grep(/$cluster_datadir/, @resarr);
    my @destfiles = map { s/$dest//; $_; } grep(/$pipeline_datadir/, @resarr);
    # thanks to some person on stack overflow for this diff
    my @diff = grep{ not $_ ~~ @destfiles } @srcfiles;
    return @diff;
  }

}
################# MAIN CODE #######

my $batchfile = $ARGV[0] ;

# Check to make sure there is a batchfile
my $fullbatchpath = $cluster_batchdir . $batchfile . '.ids' ;
unless (-e $fullbatchpath) {
  print "ERROR: cannot find batchfile $batchfile.ids in modENCODE_validators/batches.\n" ;
  exit ;
} 

print "Beginning rsync from from cluster to www-1 temporary directory\n" ;
open(my $BATCHFILE, '<', "$fullbatchpath") or die "Couldn't open $batchfile.ids $!\n";

# For each pid in the batchfile
while(<$BATCHFILE>) {
  my ($line) = $_;
  chomp($line);

  print "Processing project $line...\n";

  my $srcdir  = $cluster_datadir . $line . '/extracted/';
  my $destdir = $pipeline_tmpdir . $line . '/extracted/' ;

  # If a chado file was not found, skip this project.
  my $haschado = $srcdir . $line . ".chadoxml" ;
  unless (-e $haschado) {
    print "ERROR: $line : No chado file found -- cluster submission has failed or is still running!. Skipping this project.\n";
    next;
  }

  # Make the temporary containing folder if necessary
  unless (-e $destdir) {
   system("mkdir -p $destdir") ;
  } 

  my @need_to_rsync = find_files_to_rsync($line) ;
  
  # rsync the files
  foreach(@need_to_rsync) {
    my $currfile = $_ ;

    system("rsync", "-azvh", $srcdir . $currfile,  $destdir . $currfile) ;
  # and chmod them 644 here [so the directories don't get chmod'd as well and become useless]
    system("chmod", "644", $destdir . $currfile); 
  }

  # Then, copy the files over from the tmpdir to the  
  # actual pipeline dir so they can have the right owner 

 
  print "rsync complete, copying tmp files to pipeline directory...\n";

  my $proj_datadir = $pipeline_datadir . $line . '/extracted/';

  my $cp_cmd = "sudo -u www-data cp -vur --preserve=timestamps $pipeline_tmpdir/$line/extracted/* $proj_datadir";
  system("ssh modencode-www1 \"$cp_cmd\"");
  print "copy for $line complete.\n";

}
close($BATCHFILE);
  print "copy complete.\n\nRunning script on www1 to add commands to pipeline...\n" ;

  my $cmd = "sudo -u www-data ruby $pipeline_scriptfile $batchfile" ;
 
  #print " NOT ACTUALLY DOING THIS YET! TODO! testing the copy first." ; 
  system("ssh modencode-www1 \"$cmd\"");

  print "Complete.\n" ;
