#!/usr/bin/perl -w
use strict;

# Validate that a valid batchdir was passed as argument

if ($#ARGV != 0 ) {
  print $#ARGV . "  " ;
  print "usage: upload_to_cluster.pl batchfilename\n";
  exit;
}

my $cluster_batchdir = '/.mounts/labs/steinlab/public/modENCODE_validators/batches/'; 
my $cluster_datadir = '/.mounts/labs/steinlab/public/modENCODE_validators/data/' ;
my $pipeline_datadir = '/modencode/raw/data/' ;
my $pipeline_batchdir = '/modencode/raw/tools/cluster_validator/batches/';
my $cluster_submit = '/.mounts/labs/steinlab/public/modENCODE_validators/submit_job.sh' ;
my $bash_cmd = 'bash -s -l' ;


my $batchfile = $ARGV[0] ;

my $fullbatchpath = $pipeline_batchdir . $batchfile ;
unless (-e $fullbatchpath) {
  print "ERROR: cannot find batchfile $batchfile in /modencode/raw/tools/cluster_validator/batches.\n" ;
  exit ;
} 

print "Beginning rsync from www-1 to cluster..\n";
# First rsync inputfile to cluster to up-to-date it
#system("rsync", "-avzh", "$fullbatchpath", "$fullbatchpath.ids", "$cluster_batchdir") or die "Couldn't rsync batch file: $!\n" ;

# For some reason when it crashed it ran and when it ran it crashed, so removing die, unfortunately.
system("rsync", "-avzh", "$fullbatchpath", "$fullbatchpath.ids", "$cluster_batchdir") ;


# Then open the id list, and one at a time,
# rsync to the cluster, then ssh to hn1 and submit the job
open(my $VALIDATELOG, '<', "$fullbatchpath.ids") or die "Couldn't open $batchfile.ids $!\n" ;
while(<$VALIDATELOG>) {
  my ($pid) = $_;
  chomp($pid);

  print "\n\nSetting up $pid to submit...\n" ;

  my $srcdir = $pipeline_datadir . $pid . '/' ;
  my $destdir = $cluster_datadir . $pid ;

  # Make the dest directory unless it exists
  unless(-e $destdir) {
     mkdir $destdir or die $! ;
  }
  

  my $cmd = "rsync -avzh --include=*.tgz --exclude=*  $srcdir $destdir";
  print $cmd . "\n" ;
  system($cmd) ;

  
# dont qsub it here -- cluster_submit will do that

  my $submit_command = "ssh hn1.hpc '$bash_cmd' < $cluster_submit $batchfile $pid" ;

  print $submit_command . "\n" ;
 system($submit_command) ; # or die "akk! $!\n";
 
}  # end while

close($VALIDATELOG) ;

print "Finished submitting to cluster.\n";
