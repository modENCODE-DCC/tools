#!/usr/bin/perl -w

# Contact: lh3
# Version: 0.1.1
# this script is going to make certain assumptions:
# 1. file has paired-reads
# 2. reads are always paired
# 3. there are no multi-matches

## SJC: Generic debug variable and print.
my $DEBUG = 1;
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
my @filearray;
my $lines_in_file = 0;
my $start = time();
my @buffer;

($lines_read, $lines_written, $lines_in_file) = &bowtie2sam;
my $stop = time();
my $time = $stop-$start;
my $time_s = printf("%02d:%02d:%02d", int($time / 3600), int(($time % 3600) / 60), int($time % 60));
  print STDERR "Done. Processed $lines_written/$lines_in_file reads in file in " . $time . " sec \n";

exit;

sub bowtie2sam {
  my %opts = ();
  die("Usage: bowtie2sam.pl <aln.bowtie>\n") if (@ARGV == 0 && -t STDIN);
  my $file = $ARGV[0];
  my $tmp_file = $file . ".tmp";
  print STDERR "Sorting bowtie file \"$file\"... ";
  `sort $file > $tmp_file`;
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
  while (<>) {
      #print STDERR "buffer size after $lines_read is " . ($#buffer+1) . "\n";
      if ($#buffer+1 < 3) {
	  if (($lines_read)<$lines_in_file) {
	      push @buffer, $_;
	      $lines_read++;
	      next;
	  } else {
	      #continue;
	  }
      } else {
      }
	  #print STDERR "Buffer at line $lines_read: ( " . ($#buffer+1) . "lines)\n" . join("\n", @buffer);
	  push @buffer, $_;
	  $lines_read++;

      &process_file($lines_read, \$lines_written, $lines_in_file);
  }
  #clear out buffer
  while ($#buffer+1>0) {
      &process_file($lines_read, \$lines_written, $lines_in_file);
  }
  #untie @filearray;
  unlink($tmp_file);
  return ($lines_read, $lines_written, $lines_in_file);
}

sub process_file {
    my ($lines_read, $lines_written, $lines_in_file) = @_;
    my (@read1, @read2, $last, @staging, $k, $best_s, $subbest_s, $best_k);
    $last = '';
    my $line1 = shift @buffer;
    chomp($line1);
    #print "LINE1 (" . $line_count . "): $line1\n";
    my @t1 = split(/\t/, $line1);
    $t1[0] =~ s/\/[12]$//;
    
    my $line2 = shift @buffer;
    chomp($line2);
    my @t2 = ();
    @t2 = split(/\t/, $line2);
    $t2[0] =~ s/\/[12]$//;
    
    my ($name1, $nm1, $name2, $nm2) = &bowtie2sam_paired($line1, \@read1, $line2, \@read2); # read_name, number of mismatches, read_object
    #print STDERR"LINE $lines_read/${$lines_written}: " . join("\t", @read1) .  "\n";
    print join("\t", @read1) .  "\n";
    ${$lines_written}++;
    if ($t1[0]=~ $t2[0]) {
	#print STDERR "LINE $lines_read/${$lines_written} " . join("\t", @read2) .  "\n"; 
	print join("\t", @read2) .  "\n"; 
	${$lines_written}++;
	#kvetch("___are same");
    } else {
	unshift @buffer, $line2;
	#print STDERR "unmated read found at line $lines_written\n"
    }
    if (($lines_read)>=$lines_in_file) {
	last;
    } else {
	
    }
    print STDERR "processed $lines_read reads " . "\n" if ($lines_read % 50000 == 0);
}

sub bowtie2sam_paired {
  my ($line1, $s1, $line2, $s2) = @_;

  chomp($line1);
  chomp($line2);
  my @t1 = split("\t", $line1);
  my @t2 = split("\t", $line2);
  my $ret1;
  my $ret2;
  @$s1 = ();
  @$s2 = ();

  # initial flag (will be updated later)
  $s1->[1] = $s2->[1] = 0;
  $s1->[1] = $s2->[1] = 0x01;  #read is paired

  # read name
  $s1->[1] = ($t1[0] =~ /\/1$/) ? 0x40 : 0x80;
  $s2->[1] = ($t2[0] =~ /\/1$/) ? 0x40 : 0x80;
  #$s1->[1] = 0x40 if ($t1[0] =~ /\/1$/);
  #$s2->[1] = 0x80 if ($s2->[0] =~ /\/2$/);
  $ret1 = $t1[0];
  $ret2 = $t2[0];
  my $name = $t1[0]; 
  $name =~ s/\/[12]$//;
  $s1->[0] = $s2->[0] = $name;

  # coor
  #$s->[2] = $t[2]; 
  #$s->[2] = get_start($t[2]);
  #$s->[3] = $t[3] + 1;
  ($s1->[2],$s1->[3]) = get_chrom_and_start($t1[2],$t1[3]);
  ($s2->[2],$s2->[3]) = get_chrom_and_start($t2[2],$t2[3]);
  
  # read & quality
  $s1->[9] = $t1[4]; $s1->[10] = $t1[5];
  $s2->[9] = $t2[4]; $s2->[10] = $t2[5];
  
  # cigar
  #$s->[5] = length($s->[9]) . "M";
  $s1->[5] = get_cigar($t1[3],$s1->[9],$t1[2]);
  $s2->[5] = get_cigar($t2[3],$s2->[9],$t2[2]);
  
  #strandedness
  $s1->[1] += 0x10 if ($t1[1] eq '-');  #strand of query
  $s2->[1] += 0x10 if ($t2[1] eq '-');  #strand of query
  
  if ((split(/\/[12]$/,$ret1))[0] =~ (split(/\/[12]$/,$ret2))[0]) {
      #there's mates!
      # mate coordinate

      $s1->[1] += 0x20 if ($t2[1] eq '-');  #strand of mate
      $s2->[1] += 0x20 if ($t1[1] eq '-');  #strand of mate


      my $pair_start = $t1[1] =~ /\+/ ? $s1->[3] : $s2->[3];
      my $pair_end = 0;
      if ($t1[1] =~ /\-/) {
	  my $cigar = $s1->[5];
	  my @temp = split(/\D/,$cigar);
	  my $dist = 0;
	  my $i = 0;
	  #print "cigar parts: $cigar - " . join(" ", @temp) ;
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
	  #print "cigar parts: $cigar - " . join(" ", @temp) ;
	  while ($i < @temp) {
	      my $t = pop(@temp);
	      $dist += $t if ($t =~ /\d+/); 
	      $i++;
	  }
	  #print "dist = " . $dist . "\n";
	  $pair_end = $s2->[3]+$dist;
      }
      my $isize = abs($pair_end - $pair_start);
      #print "start: $pair_start end $pair_end isize: $isize \n";
      
      $s1->[6] = $s2->[6] = '=';
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
  }
  my $nm1 = &some_processing(\@t1,\@$s1);
  my $nm2 = &some_processing(\@t2,\@$s2);  #only print the mate if paired

  
  return ($ret1, $nm1, $ret2, $nm2);
}

sub some_processing {
  my ($t, $s) = @_;
  my $temp = @{$s};

  # aux
  my $nm = @{$t} - 7;
  push(@$s, "NM:i:" . (@{$t}-7));  #nt diffs

  #this is the read match count, for multiple hits
  push(@$s, "X$nm:i:" . (@{$t}[6]+1));

  # mapQ
  $s->[4] = @{$t}[6] == 0? 25 : 0;

  my $md = '';
  if (@{$t}[7]) {
	$_ = @{$t}[7];
	my $a = 0;
	while (/(\d+):[ACGTN]>([ACGTN])/gi) {
	  my ($y, $z) = ($1, $2);
	  $md .= (int($y)-$a) . $z;
	  $a += $y - $a + 1;
	}
	$md .= length($s->[9]) - $a;
  } else {
	$md = length($s->[9]);
  }
  push(@$s, "MD:Z:$md");  #mismatching positions

  #add a tag for the junction
  #junction, if present, will go into the Y0 tag
  my @c = split("_", @{$t}[2]);
  push (@$s, "Y0:Z:" . @{$t}[2]) if (length(@c) > 1);

  return $nm;
}

sub get_cigar {
    my ($rel_start, $seq, $junction) = @_;
    my $read_length = length($seq);
    my $cigar = "";
    my @c = split("_", $junction);

    if (@c==1) {
	$cigar = $read_length . "M";
    } else {
	#its a junction read
	#dm3_chr4_162722_162753_+>dm3_chr4_162825_162856_+_A
	my $fiveprimejxn_start = $c[2]+1;
	my $fiveprimejxn_end   = $c[3];
	my $threeprimejxn_start = $c[6]+1;
	my $threeprimejxn_end   = $c[7];
	my $read_length_A = $fiveprimejxn_end-($fiveprimejxn_start+$rel_start);
	my $intron_length = $threeprimejxn_start-$fiveprimejxn_end-1;
	my $read_length_B = $read_length - $read_length_A;
	$cigar .= $read_length_A . "M" . $intron_length . "N" . $read_length_B . "M";
    }
    return $cigar;

}

sub get_chrom_and_start {

    my ($chrom, $start) = @_;
    my @c = split("_", $chrom);
    $start++;  #dm3 coords are 0-based
    if (length(@c)>1) {
	#there's a junction read
	#assuming that junctions are same chrom
	$start += $c[2];
	$chrom = $c[1];
    }
    return ($chrom, $start);
}



