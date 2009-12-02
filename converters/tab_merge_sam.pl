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
use Switch;

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
  die("Usage: tab_merge_sam.pl <seq> <sam>\n") if (@ARGV == 0 && -t STDIN);
  my $seq_file = $ARGV[0];
  my $sam_file = $ARGV[1];

  my $tmp_seq = $seq_file . ".tmp";
  my $tmp_sam = $sam_file . ".tmp";
  my $merged_sam = $sam_file . ".seq_merged";

  print STDERR "Sorting sequence file \"$seq_file\"... ";
  `grep -v sequence $seq_file | sort > $tmp_seq`;
  
  print STDERR "Done.\n";

  print STDERR "Sorting sam file \"$sam_file\"... ";
  `sort $sam_file > $tmp_sam`;

  print STDERR "Done.\n";

  open(SAM, $tmp_sam);
  open(SEQ, $tmp_seq);


  my $wc_seq = `wc -l $tmp_seq`;
  #my $wc_bowtie = `wc -l $tmp_bowtie`;
  my $lines_in_seq = (split(" ", $wc_seq))[0];
  #my $lines_in_bowtie = (split(" ", $wc_bowtie))[0];
  my $lines_read_sam = 0;
  my $lines_written = 0;
  my $read_not_found = 0;
  my $reads_matched = 0;
  my $lines_read_seq = 0;

  print STDERR "there are " . $lines_in_seq . " lines in the file \"" . $seq_file . "\"\n";
  print STDERR "Merging...\n";
  my $sam_id = "";

  #there may be multiple alignments reported
  #for each of the reads in the tab file, find them in the sam file, add the hit counter

  while (<SEQ>) { 
      $lines_read_seq++;
      my $seq_line = $_;
      chomp($seq_line);
      $seq_line =~ s/\s+/\t/g;
      my ($seq_id, $read_sequence) = split(/\t/,$seq_line);

      my $seq_found = 0;
      my $too_big = 0;
      my $seq_hits = 0; #counter for number of alignments for each sequence
      #print STDERR "line $lines_read_seq seq is $seq_id\n";
      my $flag = 0;
      while (!$flag) {
	  last if eof(SAM);
	  my $sam_line = <SAM>;	  
	  next if ($sam_line =~ /^\s*$/);
	  my $line_length = length($sam_line);
	  chomp($sam_line);
	  $sam_line =~ s/\s+/\t/g;
	  my @sam = split(/\t/, $sam_line);
	  my $sam_id = $sam[0];
	  my $strand = ($sam[1] == 0); 
	  #if ($sam_line =~ m/\Q$seq_id/) {  
	  $lines_read_sam++;
	  #print STDERR "line $lines_read_sam sam is $sam_id\n";
	  if ($sam_id eq $seq_id) {
	      #add sequence to sam array
	      #$sam[9] = $strand ? $read_sequence : reverse_complement($read_sequence) ;
	      if ($strand) {
		  $sam[9] = $read_sequence;
	      } else {
		  #print STDERR "rc for read $sam_id at line $lines_read_sam\n";
		  $sam[9] = reverse_complement($read_sequence);
	      }
	      $seq_hits++;  
	      $sam[11] .= " HI:i:" . $seq_hits;
	      $reads_matched++;
	      #print STDERR "matched $seq_id at line $lines_read_sam of sam file\n";
	      print STDOUT join("\t", @sam) . "\n";      
	  } elsif ($sam_id gt $seq_id) {
	      $lines_read_sam--;
	      #backup
	      seek(SAM,-$line_length,1);
	      #print STDERR "backing up to line $lines_read_sam of sam file\n";
	      $flag = 1;
	  } else {
	      print STDOUT join("\t", @sam) . "\n";      
	      die;
	  }  
      }
  }
  print STDERR "++++++++++++++++++++++++++++++++++\n";
  print STDERR "SAM read: $lines_read_sam\n";
  print STDERR "reads matched: $reads_matched\n";
  print STDERR "reads not found: $read_not_found\n";
  print STDERR "++++++++++++++++++++++++++++++++++\n";
  close(SAM);
  close(SEQ);
  unlink ($tmp_sam);
  unlink ($tmp_seq);
}

sub reverse_complement {
    my ($sequence) = @_;
    my $rc_sequence = "";
    my @array = split(//, $sequence);
    foreach my $c (@array) {
        switch ($c) {
            case "A" {$c = "T"}
            case "T" {$c = "A"}
            case "G" {$c = "C"}
            case "C" {$c = "G"}
        }
        $rc_sequence = $c . $rc_sequence
    }
    return $rc_sequence;
}
