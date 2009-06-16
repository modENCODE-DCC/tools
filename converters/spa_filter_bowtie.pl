#!/usr/bin/perl -w

# Contact: lh3
# Version: 0.1.1
# this script is to take spa and combined bowtie files and spit out a 
# filtered bowtie file

$| = 1;

## SJC: Generic debug variable and print.
my $DEBUG = 1;
sub kvetch{
    my $foo = shift || '';
    print STDERR $foo . "\n" if $DEBUG;
}


use strict;
use warnings;
use Getopt::Std;
use File::Copy;

my $lines_read = 0;
my $lines_written = 0;
my @filearray;
my $lines_in_file = 0;
my $start = time();
my @buffer;

($lines_read, $lines_written, $lines_in_file) = &bowtie2sam;
my $stop = time();
my $time = $stop-$start;
print STDERR "Done. Processed in " . $time . " sec \n";

exit;

sub bowtie2sam {
  my %opts = ();
  die("Usage: spa_fileter_bowtie.pl <spa> <bowtie>\n") if (@ARGV == 0 && -t STDIN);
  my $spa_file = $ARGV[0];
  my $bowtie_file = $ARGV[1];

  my $sed_spa = $spa_file . ".sed";
  my $tmp_spa = $spa_file . ".tmp";
  my $tmp_bowtie = $bowtie_file . ".tmp";
  my $filtered_bowtie = $bowtie_file . ".spa_filtered";

  print STDERR "Sorting bowtie file \"$bowtie_file\"... ";
  `sort $bowtie_file > $tmp_bowtie`;
  
  print STDERR "Done.\n";
  print STDERR "Replacing underscores with colons...";
  `sed s/_/\:/g $spa_file > $sed_spa`;
  print STDERR "Done.\n";

  print STDERR "Sorting spa file \"$spa_file\"... ";
  `sort $sed_spa > $tmp_spa`;
  unlink($sed_spa);
  print STDERR "Done.\n";

  open(SPA, "<", $tmp_spa);
  open(BOWTIE, "<", $tmp_bowtie);


  my $wc_spa = `wc -l $tmp_spa`;
  #my $wc_bowtie = `wc -l $tmp_bowtie`;
  my $lines_in_spa = (split(" ", $wc_spa))[0];
  #my $lines_in_bowtie = (split(" ", $wc_bowtie))[0];
  my $lines_read_bowtie = 0;
  my $lines_written = 0;
  my $read_not_found = 0;

  print STDERR "there are " . $lines_in_spa . " lines in the file \"" . $spa_file . "\"\n";
  print STDERR "Filtering...\n";
  while (<BOWTIE>) { 
      my $bowtie_line = $_;
      $lines_read_bowtie++;
      while (<SPA>) {
	  my ($spa_line) = $_;
	  next if ($spa_line =~ /^\s*$/);
	  #print STDERR "$lines_read lines read from SPA file\n"; #if ($lines_read % 100 == 0);
	  #print STDERR "read line $lines_read\n";
	  #go through the SPA file, and then pick out the matching items from 
	  #the bowtie file
	  $lines_read++;

	  my @spa = split("\t",$spa_line);
	  chomp($spa_line);
	  my ($read_id, $read1_chr, $read1_pos, $read1_strand, $read2_chr, $read2_pos, $read2_strand) = ($spa_line =~ /(\S+)\s+(\S+)\s+(\d+)\s+([-+])\s+(\S+)\s+(\d+)\s+([+-])\s+/);
	  #read id is first item

	  $read_id =~ s/_/:/g;
	  #print STDERR "looking for $read_id\n";
	  my $pair_found = 0;
	  my $skip_flag = 0;
	  my $read1_found = 0;
	  my $read2_found = 0;
	  my @bowtie = ();
	  if ($skip_flag) {
	      $read1_found = $read2_found = 0; 
	      #$skip_flag = 0;
	      die;
	  } else {
	      
	      while ((!$read1_found) || (!$read2_found)) {
		  while ($bowtie_line !~ /\Q$read_id/) {
		      #keep reading file until a matching read is found.  
		      chomp($bowtie_line);
		      @bowtie = split("\t",$bowtie_line);
		      my ($bowtie_read) = ($bowtie[0] =~ /\w:(\d+:\d+:\d+)\/.+/);
		      #print STDERR "BOWTIE READ: \"$bowtie_read\" vs \"$read_id\"\n";
		      if ($bowtie_read gt $read_id) {
			  #since the file is sorted, then we can test if we've
			  #already passed where the read should be in the file
			  #continue;
			  $skip_flag = 1;
			  $read_not_found++;
		      } #else {
			  $bowtie_line = <BOWTIE>;
			  $lines_read_bowtie++;
		      #}
		  }
		  chomp($bowtie_line);
		  @bowtie = split("\t",$bowtie_line);
		  #print STDERR "BOWTIE id match at line $lines_read_bowtie: " . $bowtie[2] . ", " . $bowtie[0] . "\n";
		  if (!$skip_flag) {
		      if (!$read1_found) {
			  my @bowtie_chr_spa = split("_",$bowtie[2]);
			  my $bowtie_chr = "";
			  if (scalar(@bowtie_chr_spa) > 1) {
			      $bowtie_chr = $bowtie_chr_spa[1] . ":" . $bowtie_chr_spa[2] . ":" . $bowtie_chr_spa[3] . ":" . $bowtie_chr_spa[6] . ":" . $bowtie_chr_spa[7];
			  } else {
			      $bowtie_chr = $bowtie[2];
			  }
			  if (($bowtie_chr eq $read1_chr) && ($bowtie[1] eq $read1_strand)) {

			      print $bowtie_line . "\n";
			      #print STDERR "wrote: $bowtie_line\n";
			      $lines_written++;
			      $read1_found = 1;
			  } else {
			      #print STDERR "Don't match : $bowtie_chr and $read1_chr for $read_id at line $lines_read\n";
			      #die;
			  }
		      } elsif (!$read2_found) {
			  my @bowtie_chr_spa = split("_",$bowtie[2]);
			  my $bowtie_chr = "";
			  if (scalar(@bowtie_chr_spa) > 1) {
			      $bowtie_chr = $bowtie_chr_spa[1] . ":" . $bowtie_chr_spa[2] . ":" . $bowtie_chr_spa[3] . ":" . $bowtie_chr_spa[6] . ":" . $bowtie_chr_spa[7];
			  } else {
			      $bowtie_chr = $bowtie[2];
			  }
			  if (($bowtie_chr eq $read2_chr) && ($bowtie[1] eq $read2_strand)) {

			      print $bowtie_line . "\n";
			      #print STDERR "wrote: $bowtie_line\n";
			      $lines_written++;
			      $read2_found = 1;
			  } else {
			      #print STDERR "Don't match : $bowtie_chr and $read2_chr for $read_id at line $lines_read\n";
			      #die;
			  }			  
		      }
		  } else {
		      print STDERR "*************************$read_id skipped!\n";
		      die;
		  }
		      $bowtie_line = <BOWTIE>;
		      $lines_read_bowtie++;
	      }
	  }
	  print STDERR "$lines_read_bowtie lines read in bowtie file; $lines_read lines read in spa file\n" if ($lines_read % 100000 == 0);
      }
  }
  print STDERR "++++++++++++++++++++++++++++++++++\n";
  print STDERR "BOWTIE read: $lines_read_bowtie\n";
  print STDERR "BOWTIE discarded: " . ($lines_read_bowtie - $lines_written) . "\n";
  print STDERR "SPA read: $lines_read\n";
  print STDERR "BOWTIE filtered: $lines_written \n";
  print STDERR "++++++++++++++++++++++++++++++++++\n";
  close(BOWTIE);
  close(SPA);
}

