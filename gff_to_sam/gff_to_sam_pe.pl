#!/usr/bin/perl -w

# this script is used to convert the alignments in gff to sam, for the waterston project
# this script is going to make certain assumptions:
# 1. file has paired-reads
# 2. reads might not have mate
# 3. there are no multi-matches

# this script requires that the file be sorted on the read name,


## SJC: Generic debug variable and print.
my $DEBUG = 0;
sub kvetch{
    my $foo = shift || '';
    print STDERR $foo . "\n" if $DEBUG;
}


use strict;
use warnings;
use Getopt::Std;
use Tie::File;
use File::Copy;

my $lines_read = 0;
my $lines_written = 0;
my $bad_cigar_count = 0;
my @filearray;
my $lines_in_file = 0;
my $start = time();
my @buffer;

($lines_read, $lines_written, $lines_in_file, $bad_cigar_count) = &gff2sam;
my $stop = time();
my $time = $stop-$start;
my $time_s = sprintf("%02d:%02d:%02d", int($time / 3600), int(($time % 3600) / 60), int($time % 60));

print STDERR "Done. Processed $lines_written/$lines_in_file reads in file in " . $time . " sec \n";
print STDERR "Found $bad_cigar_count poorly constructed cigar strings in file.\n";
exit;

sub gff2sam {
  my %opts = ();
  die("Usage: gff_to_sam_pe.pl <aln.gff3>\n") if (@ARGV == 0 && -t STDIN);
  my $file = $ARGV[0];
#  my $tmp_file = $file;
  my $tmp_file = $file . ".sorted";
  print STDERR "Sorting gff file and removing comments from \"$file\"... ";
  `sort $file -k 9 | grep -v ^# > $tmp_file`;
  print STDERR "Done.\n";
  #copy($file,$tmp_file) or die "Copy failed: $!";

  use Fcntl 'O_RDONLY';
  #note that cpu is a more limiting factor here.
  tie @filearray, 'Tie::File', $tmp_file, memory => 100_000_000 or die "can't find file";
  
  #$lines_in_file = scalar(@filearray);
  my $wc = `wc -l $tmp_file`;
  my $lines_in_file = (split(" ", $wc))[0];
  my $lines_read = 0;
  my $lines_written = 0;

  print STDERR "there are " . $lines_in_file . " lines in the file \"" . $file . "\"\n";
  print STDERR "Converting...\n";
  open TMPFILE, "<", $tmp_file;
  while (<TMPFILE>) {
      $lines_read++;
      #print STDERR "buffer size after $lines_read is " . ($#buffer+1) . "\n";
      if ($#buffer+1 < 3) {
	  if (($lines_read)<$lines_in_file) {
	      push @buffer, $_;
	      next;
	  }
      }
	  push @buffer, $_;

      &process_file($lines_read, \$lines_written, $lines_in_file, \$bad_cigar_count);
  }
  #clear out buffer
  while (@buffer > 0) {
      &process_file($lines_read, \$lines_written, $lines_in_file, \$bad_cigar_count);
  }
  close TMPFILE;
  untie @filearray;
  #unlink($tmp_file);
  return ($lines_read, $lines_written, $lines_in_file, $bad_cigar_count);
}

sub process_file {
    my ($lines_read, $lines_written, $lines_in_file, $bad_cigar_count) = @_;
    my (@read1, @read2, $last, @staging, $k, $best_s, $subbest_s, $best_k);
    $last = '';
    my $line1 = shift @buffer;
    chomp($line1);
    my @t1 = split(/\t/, $line1);

    my @t2 = ();
    my $line2 = "";
    if ($#buffer > 0) {
	$line2 = shift @buffer;
	chomp($line2);
	@t2 = split(/\t/, $line2);
    }
    
    my ($name1, $name2) = &gff2sam_paired($line1, \@read1, $line2, \@read2, \${$bad_cigar_count}); # read_name, number of mismatches, read_object

    $name1 =~ s/\/[12]$//;
    $name2 =~ s/\/[12]$//;

    my $line_to_print = join("\t", @read1);
    $line_to_print =~ s/\s+$//; #remove trailing WS
    print $line_to_print .  "\n";

    ${$lines_written}++;
    if ($line2 ne "") {
	if ($name1 =~ $name2) {
          $line_to_print = join("\t", @read2);
          $line_to_print =~ s/\s+$//; #remove trailing WS
          print $line_to_print .  "\n";
	    ${$lines_written}++;

	} else {
	    unshift @buffer, $line2 if ($line2 ne "");
	    #print STDERR "unmated read found at line $lines_written\n"
	}
    }
    print STDERR "processed $lines_read reads " . "\n" if ($lines_read % 50000 == 0);
}

sub gff2sam_paired {
  my ($line1, $s1, $line2, $s2, $bad_cigar_count) = @_;

  #gff structure: 
  #t0 = chrom
  #t1 = source
  #t2 = type
  #t3 = start
  #t4 = end
  #t5 = cross_match score
  #t6 = strand
  #t7 = dunno
  #t8 = attributes (target, parent, seq, etc)

  #sam structure:
  #s0 = read id
  #s1 = bit flag
  #s2 = chrom
  #s3 = start
  #s4 = map-qual '255'
  #s5 = cigar
  #s6 = chrom of mate '='
  #s7 = pnext pos of mate
  #s8 = distance between ends of mates
  #s9 = sequence
  #s10 = qual, '*'
  #s11 = tag-val attributes

  chomp($line1);
  chomp($line2);
  my @t1 = split("\t", $line1); #gff fields read1
  my @t2 = split("\t", $line2); #gff fields read2
  my ($ret1, $ret2);
  $ret1 = $ret2 = "";
  @$s1 = ();  #sam fields read1
  @$s2 = ();  #sam fields read2

  # initial flag (will be updated later)
  $s1->[1] = $s2->[1] = 0;
  $s1->[1] = $s2->[1] = 0x01;  #read is paired

  kvetch "read 1 bit set to " . $s1->[1] . "\n";
  kvetch "read 2 bit set to " . $s2->[1] . "\n";

  # Read name and length
  # Read name is placed in the Target attribute in the gff file
  my (@attributes1, @attributes2,$t_start,$t_end);
  (@attributes1) = split(/;/, $t1[8]);
  ($ret1, $t_start, $t_end) = ((grep { m/^Target=/ } @attributes1)[0] =~ /Target\=(\S+)\s(\d+)\s(\d+)/);
  die "No read_length" unless $t_end > 0;
  if ($line2 ne "") {
    (@attributes2) = split(/;/,$t2[8]);
    ($ret2, $t_start, $t_end) = ((grep { m/^Target=/ } @attributes2)[0] =~ /Target\=(\S+)\s(\d+)\s(\d+)/);
    die "No read_length" unless $t_end > 0;
  }

  #set bit for first or second read in pair
  $s1->[1] += ($ret1 =~ /\/1$/) ? 0x40 : 0x80;
  $s2->[1] += ($ret2 =~ /\/1$/) ? 0x40 : 0x80 if ($line2 ne "");

  kvetch "read 1 is " . $ret1 . "\n";
  kvetch "read 2 is " . $ret2 . "\n";

  kvetch "read 1 bit set to " . $s1->[1] . " after setting as " . (($ret1 =~ /\/1$/) ? "first" : "second") . " read in pair \n";
  kvetch "read 2 bit set to " . $s2->[1] . " after setting as ". (($ret2 =~ /\/1$/) ? "first" : "second") . " read in pair \n";


  #read name
  my $name = $ret1; 
  $name =~ s/\/[12]$//;
  $s1->[0] = $s2->[0] = $name;

  # coor
  $s1->[2]=$t1[0];   #chrom
  $s1->[3]=$t1[3];   #start
  if ($line2 ne "") {
    $s2->[2]=$t2[0];  #chrom
    $s2->[3]=$t2[3];  #start
  }
  
  #map quality
  $s1->[4] = 255;
  $s2->[4] = 255;

  #quality
  $s1->[10] = "*";  #qual not included
  $s2->[10] = "*" if ($line2 ne "");

  #($cigar, $seq, $tag);
  my ($tag1,$tag2,$bad_cigar);
  ($s1->[5], $s1->[9], $tag1, $bad_cigar) =  &process_attributes(\@attributes1, $t1[6]);
  ${$bad_cigar_count}+=$bad_cigar;
  ($s2->[5], $s2->[9], $tag2, $bad_cigar) =  &process_attributes(\@attributes2, $t2[6]) if ($line2 ne "");
  #${$lines_written}++
  ${$bad_cigar_count}+=$bad_cigar if ($line2 ne "");
  #add tags
  push(@$s1, "AS:i:" . $t1[5]);
  push(@$s2, "AS:i:" . $t2[5]) if ($line2 ne "");
  #$tag1 =~ s/\s//g;
  #$tag2 =~ s/\s//g;
  push(@$s1, $tag1) if ($tag1 ne "");

  push(@$s2, $tag2) if (($line2 ne "") && ($tag2 ne ""));

  #strandedness
  $s1->[1] += 0x10 if ($t1[6] eq '-');  #strand of query
  kvetch "read 1 bit set to " . $s1->[1] . " after setting strand as " . (($t1[6] eq '-') ? "negative" : "positive") . " for the first read \n";


  if ($line2 ne "") {  #strand of query
      $s2->[1] += 0x10 if ($t2[6] eq '-');
      kvetch "read 2 bit set to " . $s2->[1] . " after setting strand as " . (($t2[6] eq '-') ? "negative" : "positive") . " for the second read \n";

      if ((split(/\/[12]$/,$ret1))[0] =~ (split(/\/[12]$/,$ret2))[0]) {
	  # there's mates!
	  
	  # mate coordinate
	  $s1->[1] += 0x20 if ($t2[6] eq '-');  #strand of mate
	  $s2->[1] += 0x20 if ($t1[6] eq '-');  #strand of mate

          kvetch "read 1 bit set to " . $s1->[1] . " after setting strand of read2 as " . (($t2[6] eq '-') ? "negative" : "positive") . " \n";
          kvetch "read 2 bit set to " . $s2->[1] . " after setting strand of read1 as " . (($t1[6] eq '-') ? "negative" : "positive") . "\n";

          $s1->[1] += 0x2; #mate is mapped
          $s2->[1] += 0x2; #mate is mapped

          kvetch "read 1 bit set to " . $s1->[1] . " after setting mate as mapped\n";
          kvetch "read 2 bit set to " . $s2->[1] . " after setting mate as mapped\n";


	  my $pair_start = $t1[6] =~ /\+/ ? $s1->[3] : $s2->[3];
	  my $pair_end = 0;
	  if ($t1[6] =~ /\-/) {
	      my $cigar = $s1->[5];
	      my @temp = split(/\D/,$cigar);
	      my $dist = 0;
	      my $i = 0;
	      
	      while ($i < @temp) {
		  my $t = pop(@temp);
		  $dist += $t if ($t =~ /\d+/); 
		  $i++;
	      }
	      $pair_end = $s1->[3]+$dist;
	  } else {
	      my $cigar = $s2->[5];
	      my @temp = split(/\D/,$cigar);
	      my $dist = 0;
	      my $i = 0;
	      
	      while ($i < @temp) {
		  my $t = pop(@temp);
		  $dist += $t if ($t =~ /\d+/); 
		  $i++;
	      }
	      $pair_end = $s2->[3]+$dist;
	  }
	  my $isize = abs($pair_end - $pair_start);
	  
          if ($s1->[2] eq $s2->[2]) {
            $s1->[6] = $s2->[6] = '=';
          } else {
            $s1->[6] = $s2->[2];
            $s2->[6] = $s1->[2];  
          }

          $s1->[7] = $s2->[3];
	  $s2->[7] = $s1->[3];
	  
	  if ($s1->[3] < $s2->[3]) {
	      $s1->[8] = $isize;
	      $s2->[8] = $isize*(-1);
	  } else {
	      $s1->[8] = $isize*(-1);
	      $s2->[8] = $isize;
	  }
      } else {
	  #for unpaired
	  #print "UNPAIRED! at $line_count\n";
	  $s1->[6] = $s2->[6] = '*'; 
	  $s1->[7] = $s1->[8] = $s2->[7] = $s2->[8] = 0;
	  $s1->[1] += 0x08;
  kvetch( "read 1 bit set to " . $s1->[1] . " after setting unpaired \n");

        }
  } else {
      #also unpaired, but the last line in the file
      #for unpaired
      #print "UNPAIRED! at $line_count\n";
      $s1->[6] = $s2->[6] = '*'; 
      $s1->[7] = $s1->[8] = $s2->[7] = $s2->[8] = 0;
      $s1->[1] += 0x08;
  kvetch "read 1 bit set to " . $s1->[1] . " after setting unpaired for last line\n";

    }
    kvetch "bits: 0x1: " . 0x1 . "\n";
    kvetch "bits: 0x2: " . 0x2 . "\n";
    kvetch "bits: 0x8: " . 0x8 . "\n";
    kvetch "bits: 0x10: " . 0x10 . "\n";
    kvetch "bits: 0x20: " . 0x20 . "\n";
    kvetch "bits: 0x40: " . 0x40 . "\n";
    kvetch "bits: 0x80: " . 0x80 . "\n";

    kvetch "read1 should be " . (0x1 + 0x40 + 0x10 + 0x2) . "\n";
    kvetch "read2 should be " . (0x1 + 0x80 + 0x0 + 0x2 + 0x20) . "\n";
  return ($ret1, $ret2);
}

sub process_attributes {
  my ($a,$strand,$bad_cigar) = @_;
  my @attributes = @$a;
  my ($cigar_length,$qname,$t_start,$t_end,$cigar3,$cigar5,$tag,$target_match_length,$seq_length,$cigar);
  $target_match_length = $seq_length = $cigar_length = $t_start = $t_end = $cigar3 = $cigar5 = 0;
  $qname = $tag = $cigar = "";
  $bad_cigar = 0;
  my $seq = "*";  #default seq

  # Extra attributes
  foreach my $att (@attributes) {
    chomp($att);
    my ($aname, $aval) = split(/=/, $att);
    if ($aname =~ /Target/) {
      ($qname, $t_start, $t_end) = split(/ /, $aval);
      $target_match_length = $t_end - $t_start + 1;
      $cigar = $target_match_length . "M"; #default cigar;
      $cigar_length = $target_match_length;
    }
    if ($aname =~ /Gap/) { # Use Gap for cigar
      my @cigar_array = split(/ /, $aval);
      my $l = '';
      $cigar = "";
      $cigar_length = 0;
      foreach my $a (@cigar_array) {
        my $nums = my $letter = '';
        ($letter, $nums) = ($a =~ m/(\D)(\d+)/);
        $cigar .= $nums . $letter;
        $cigar_length += $nums if (($letter eq 'M') || ($letter eq 'I'));
      }
        $cigar =~ s/D/N/;
    }
    if ($aname =~ /seq/) {
      $seq = $aval;
      if ($strand eq "-") {
        $seq = revcomp($seq);
      }
      $seq_length = length ($seq);
      if ($seq_length > $target_match_length) {
        #assume soft clipping on ends of read
        if ($t_start > 1) {
          $cigar5 = ($t_start - 1) ;
        }
        if ($t_end < $seq_length) {
          $cigar3 = ($seq_length - $t_end) ;
        }
      }
    }
    if ($aname =~ /Parent/) {
      $tag = "Y1:Z:" . $aval;
    }
  }
  #put together the cigar string
  if ($strand =~ /-/) {
    #if the read in on the reverse strand, then add the clips in the reverse order; the original gap is
    #in relation to the + strand.
    $cigar = $cigar3 . "S" . $cigar if $cigar3 > 0;
    $cigar = $cigar . $cigar5 . "S" if $cigar5 > 0;
  } else {
    $cigar = $cigar5 . "S" . $cigar if $cigar5 > 0;
    $cigar = $cigar . $cigar3 . "S" if $cigar3 > 0;
  }
  $cigar_length += $cigar3 + $cigar5;
  if ($cigar_length != $seq_length) {
    print STDERR "Cannot reconcile cigar for $qname. seq length: $seq_length; calculated cigar: $cigar_length.\n";
  $bad_cigar = 1;
  $seq = "*";
  }
  return ($cigar, $seq, $tag, $bad_cigar);
} #</process_attributes>

sub revcomp {
  my ($sequence) = @_;
  $sequence =~ tr/atgcrymkswATGCRYMKSW/tacgyrkmswTACGYRKMSW/;
  return reverse($sequence);
}

