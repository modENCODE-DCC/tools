#!/usr/bin/perl -w

# this script is a converter that will take nexalign sequencing alignment
# files and generate a SAM file.  

# this script makes a few assumptions:
# 1. read name can have the optional condition that it includes
#    name/sequence/quality, delimited by the "~".  if this info is not
#    included in the read name, it will default to using the "*" in
#    the sequence and quality columns
# 2. for sequence clipping, this looks for a discrepancy between the 
#    sequence length, and the mapping coordinate length.  if it maps
#    to the negative strand it will apply the clipping to the 5' end
# 3. the sequences are not w.r.t the positive strand, so all negative
#    strand sequences are reverse complemented.  the quality scores
#    are therefore reversed. 
# 4. this script assumes sequences are single-reads, rather than
#    paired end.  this script will not work for paired-end seq.
# TODO:  this script should be generalized such that it takes standard
#        nexalign output, a fastq file, and merges the two files 
#        together, based on the read names.
# 

## SJC: Generic debug variable and print.
my $DEBUG = 1;
sub kvetch{
    my $foo = shift || '';
    print STDERR $foo . "\n" if $DEBUG;
}


use strict;
use warnings;
use Getopt::Long;
use Tie::File;
use File::Copy;
use Switch;

my $lines_read = 0;
my $lines_written = 0;
my $lines_in_file = 0;
my $start = time();
my @buffer;
my $fastq_file = "";
my $pair_flag = 0;
($lines_read, $lines_written, $lines_in_file) = &nexalign2sam;
my $stop = time();
my $time = $stop-$start;
my $time_s = printf("%02d:%02d:%02d", int($time / 3600), int(($time % 3600) / 60), int($time % 60));
  print STDERR "Done. Processed $lines_written/$lines_in_file reads in file in " . $time . " sec \n";

exit;

sub usage {
    my $s = "";
    $s = "Usage: nexalign2sam.pl [-p] [-fastq <file>] <aln.nexalign>\n";
    $s .= "Options: -p              reads are from paired-end sequencing.  otherwise assumes single-read.\n";  #TODO
    $s .= "         -fastq <file>   merges the alignment file with a fastq file based on the read names\n\n";  #TODO
    return $s;
}

sub nexalign2sam {

  GetOptions("p" => \$pair_flag,
	     "fastq=s" => \$fastq_file) or die (&usage);
  die(&usage) if (@ARGV == 0 && -t STDIN);
  if ($pair_flag) {
      print STDERR "THIS SCRIPT DOES NOT SUPPORT PAIRED END DATA\n";
      exit;
  } else {
      print STDERR "processing non-paired-end file\n";
  }
  if ($fastq_file) {
      print "merging nexalign with fastq file\n";
      #sort the fastq file
      #sort thre nexalign file
  }

  my $file = $ARGV[0];
  my $tmp_file = $file . ".tmp";
  copy($file,$tmp_file) or die "Copy failed: $!";

  
  my $wc = `wc -l $tmp_file`;
  my $lines_in_file = (split(" ", $wc))[0];
  my $lines_read = 0;
  my $lines_written = 0;

  print STDERR "there are " . $lines_in_file . " lines in the file \"" . $file . "\"\n";
  print STDERR "Converting...\n";
  while (<>) {
      $lines_read++;
      #print STDERR "buffer size after $lines_read is " . ($#buffer+1) . "\n";
      if ($#buffer+1 < 3) {
	  if (($lines_read)<$lines_in_file) {
	      push @buffer, $_;
	      next;
	  }
      }
	  push @buffer, $_;

      &process_file($lines_read, \$lines_written, $lines_in_file);
  }
  #clear out buffer
  while (@buffer > 0) {
      &process_file($lines_read, \$lines_written, $lines_in_file);
  }

  unlink($tmp_file);
  return ($lines_read, $lines_written, $lines_in_file);
}

sub process_file {
    my ($lines_read, $lines_written, $lines_in_file) = @_;
    my (@read1, $last, @staging, $k, $best_s, $subbest_s, $best_k);
    $last = '';
    my $line1 = shift @buffer;
    chomp($line1);
    my @t1 = split(/\t/, $line1);
    $t1[0] =~ s/\/[12]$//;
        
    my ($name, $nm) = &nexalign2sam_unpaired($line1, \@read1); # read_name, number of mismatches, read_object

    print join("\t", @read1) .  "\n";
    ${$lines_written}++;
    print STDERR "processed $lines_read reads " . "\n" if ($lines_read % 50000 == 0);
}

sub nexalign2sam_unpaired {
  #name, chr, strand, start, stop, exact_match, #reads, #repeats

  my ($line, $s) = @_;
  my ($nm, $ret);
  chomp($line);
  my @t = split("\t", $line);
  #my $ret;
  @$s = ();

  # read name, sequence, quality
  my @n = split("~", $t[0]);
  $s->[0] = $ret = $n[0];
  if (@n > 0) {
      # using the query name to house the read id, sequence, and quality, delimited by "~"
      if ($t[2] eq '-') {
	  $s->[9] = reverse_complement($n[1]); 
	  $s->[10] = reverse($n[2]);
      }	else {
	  $s->[9] = $n[1]; 
	  $s->[10] = $n[2];
      } 

  } else {
      # no seq or quality provided 
      $s->[9] = "*"; 
      $s->[10] = "*";
  }

  # initial flag (will be updated later)
  $s->[1] = 0;


  # cigar
  $s->[5] = get_cigar($t[3], $t[4], $s->[9], $t[2]);
  # coor
  ($s->[2],$s->[3]) = get_chrom_and_start($t[1],$t[3]);
  #$s->[3] += 1;
  $s->[1] |= 0x10 if ($t[2] eq '-');
  # mapQ
  $s->[4] = 255;
  # mate coordinate
  $s->[6] = '*'; $s->[7] = $s->[8] = 0;
  $nm = &some_processing(\@t,\@$s);
  return ($ret, $nm);
}


sub some_processing {
  my ($t, $s) = @_;
  my $temp = @{$s};

  # aux
  my $nm = @{$t} - 7;
  push(@$s, "NM:i:" . (@{$t}-7));  #nt diffs

  #add a tag for the junction
  #junction, if present, will go into the Y0 tag
  my @c = split("_", @{$t}[2]);
  push (@$s, "Y0:Z:" . @{$t}[2]) if (length(@c) > 1);

  return $nm;
}

sub get_cigar {
    my ($start, $stop, $seq, $strand) = @_;
    my $read_length = $stop - $start;
    my $cigar = "";
    $cigar = $read_length . "M";
    if ($seq ne "*") {
	#BEWARE: this assumes 3' clipping only!
	my $clip_length = length($seq) - $read_length;
	if ($strand eq "+") {
	    $cigar .=  $clip_length . "S";
	} else {
	    $cigar =  $clip_length . "S" . $cigar;
	}
    }
    return $cigar;

}

sub get_chrom_and_start {

    my ($chrom, $start) = @_;
    my @c = split("_", $chrom);
    $start++;  #dm3 coords are 0-based, but we need 1-based
    if (length(@c)>1) {
	#there's a junction read
	#assuming that junctions are same chrom
	$start += $c[2];
	$chrom = $c[1];
    }
    return ($chrom, $start);
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

