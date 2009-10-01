#!/usr/bin/perl -w

# Author: nlw

# This script converts "match" gff features into individual sam reads. 
# This assumes that each line is a single read, using the Gap attribute, 
# rather than "match_part" features.
# If the Gap attribute is found, it assumes that "D" in the cigar string
# represents introns, and therefore changes them into Ns.

use strict;
use warnings;
use Getopt::Std;

my %opts = (a=>1, b=>3, q=>5, r=>2);
getopts('a:b:q:r:', \%opts);
die("Usage: gff2sam.pl <in.gff>\n") if (@ARGV == 0 && -t STDIN);

my $start = time();
my $lines = 0;

while (<>) {
    $lines++;
  next unless (/^\S/);
  my @gff = split(/\t/, $_);
  my @attributes = split(/;/,$gff[8]);
  my @s;
  my $cigar = '';
    my $read_length = 0;
  # read id

  ($s[0],$read_length) = ($attributes[0] =~ /Target\=(_\S+)\s\d+\s(\d+)/);

  # bit flag
  $s[1] = 0;
  $s[1] = 0x0010 if $gff[6] eq '-';

  # chrom
  $s[2] = $gff[0];

  # start
  $s[3] = $gff[3];

  # score
  $s[4] = '255';

  # cigar
  $s[5] .= $read_length . 'M';

  foreach my $a (@attributes) {
      #use the Gap cigar, if present
      if ($a =~ /Gap/) {
	  $a =~ s/Gap=//;
	  my @cigar_array = split(/ /, $a);
	  my $pos = 0;
	  my $last = '';
	  my $cigar = '';
	  foreach my $a (@cigar_array) {
	      my $nums = my $letter = '';
	      ($letter, $nums) = ($a =~ m/(\D)(\d+)/);
	      $cigar .= $nums . $letter;
	  }
	  $cigar =~ s/D/N/;  #assuming introns rather than deletions
	  $s[5] = $cigar;
      }
  }
  
  $s[6] = '*';
  $s[7] = 0;
  $s[8] = 0;
  #sequence
  $s[9] = '*';
  #quality
  $s[10] = '*';
  # number of mismatches
  $s[11] = 'NM:i:' . ($read_length - $gff[5]);

  #add the tag for the items that provide support to other features
  foreach my $a (@attributes) {
      if ($a =~ /Parent/) {
	  $a =~ s/Parent=//;
	  $s[11] .= ' Y1:Z:' . $a;
      }
  }

  print join("\t", @s), "\n";
  print STDERR "processed $lines lines\n" if ($lines % 50000 == 0);
}

my $stop = time();
my $time = $stop-$start;
my $time_s = printf("%02d:%02d:%02d", int($time / 3600), int(($time % 3600) / 60), int($time % 60));
print STDERR "\nDone. Processed $lines lines in your gff file in $time sec \n";
