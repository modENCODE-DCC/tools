#!/usr/bin/perl -w

# this is a customized script to convert bowtie alignment output to 
# SAM format.  this script can accomodate splice junction chromosome
# alignments when in the form: 
# dm3_chr3L_4414828_4414858_+>dm3_chr3L_4417819_4417849_+_A
# where the first-half is x(bp)+splice-donor site, and the second-half
# is the splice-acceptor site+x(bp).  the chromosomal position in column 3
# of the bowtie file is the position from the 5'-end of the splice-donor
# site coordinates.  if a splice junction is encountered, the splice junction
# will be added to a special attribute Y0.

# this script can process either single-read or paired-end reads
# run this script with the "-p" flag to accomodate paired-end reads

# for paired-end processing, there are certain assumptions:
# 1. file has paired-reads
# 2. reads are always paired
# 3. there are no multi-matches
# 4. mates are always on the same chromosome

# regardless of the sequencing done, this script assumes:
# A. using UCSC coords which are 0-based, but 
#    SAM needs 1-based coords, so +1 added to start positions.
# B. this script requires that the file be sorted on the read name,
#    hence 'sort' is called on the input bowtie files

# this script needs to be updated so that multiple matches can be 
# accommodated properly

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

my $lines_read = 0;
my $lines_written = 0;
my $lines_in_file = 0;
my $start = time();
my @buffer;
my $pair_flag = 0;
($lines_read, $lines_written, $lines_in_file) = &bowtie2sam;
my $stop = time();
my $time = $stop-$start;
my $time_s = printf("%02d:%02d:%02d", int($time / 3600), int(($time % 3600) / 60), int($time % 60));
  print STDERR "Done. Processed $lines_written/$lines_in_file reads in file in " . $time . " sec \n";

exit;

sub usage {
    return ("\nUsage: bowtie2sam.pl [-p] <aln.bowtie>\nOptions: -p  reads are from paired-end sequencing.  otherwise assumes single-read.\n\n");
}

sub bowtie2sam {

  GetOptions("p" => \$pair_flag) or die (&usage);
  die(&usage) if (@ARGV == 0 && -t STDIN);
  if ($pair_flag) {
      print STDERR "processing paired-end file\n";
  } else {
      print STDERR "processing non-paired-end file\n";
  }

  my $file = $ARGV[0];
  my $tmp_file = $file . ".tmp";
  print STDERR "Sorting bowtie file \"$file\"... ";
  `sort $file > $tmp_file`;
  print STDERR "Done.\n";
  #copy($file,$tmp_file) or die "Copy failed: $!";

  
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

      if ($pair_flag) {
	  &process_pe_file($lines_read, \$lines_written, $lines_in_file);
      } else {
	  &process_file($lines_read, \$lines_written, $lines_in_file);
      }
  }
  #clear out buffer
  while (@buffer > 0) {
      if ($pair_flag) {
	  &process_pe_file($lines_read, \$lines_written, $lines_in_file);
      } else {
	  &process_file($lines_read, \$lines_written, $lines_in_file);
      }
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
    
    
    my ($name, $nm) = &bowtie2sam_unpaired($line1, \@read1); # read_name, number of mismatches, read_object

    print join("\t", @read1) .  "\n";
    ${$lines_written}++;
    print STDERR "processed $lines_read reads " . "\n" if ($lines_read % 50000 == 0);
}

sub process_pe_file {
    my ($lines_read, $lines_written, $lines_in_file) = @_;
    my (@read1, @read2, $last, @staging, $k, $best_s, $subbest_s, $best_k);
    $last = '';
    my $line1 = shift @buffer;
    chomp($line1);
    my @t1 = split(/\t/, $line1);
    $t1[0] =~ s/\/[12]$//;
    

    my @t2 = ();
    my $line2 = "";
    if ($#buffer > 0) {

	$line2 = shift @buffer;
	chomp($line2);
	@t2 = split(/\t/, $line2);
	$t2[0] =~ s/\/[12]$//;
    }
    
    my ($name1, $nm1, $name2, $nm2) = &bowtie2sam_paired($line1, \@read1, $line2, \@read2); # read_name, number of mismatches, read_object

    print join("\t", @read1) .  "\n";
    ${$lines_written}++;
    if ($line2 ne "") {
	if ($t1[0]=~ $t2[0]) {
	    print join("\t", @read2) .  "\n"; 
	    ${$lines_written}++;

	} else {
	    unshift @buffer, $line2 if ($line2 ne "");
	    #print STDERR "unmated read found at line $lines_written\n"
	}
    }
    print STDERR "processed $lines_read reads " . "\n" if ($lines_read % 50000 == 0);
}

sub bowtie2sam_unpaired {
  my ($line, $s) = @_;
  my ($nm, $ret);
  chomp($line);
  my @t = split("\t", $line);
  #my $ret;
  @$s = ();
  # read name
  $s->[0] = $ret = $t[0];
  $s->[0] =~ s/\/[12]$//g;
  # initial flag (will be updated later)
  $s->[1] = 0;
  my $name = $t[0]; 
  $name =~ s/\/[12]$//;
  $s->[0] = $name;

  # read & quality
  $s->[9] = $t[4]; $s->[10] = $t[5];
  # cigar
  $s->[5] = get_cigar($t[3],$s->[9],$t[2]);
  # coor
  ($s->[2],$s->[3]) = get_chrom_and_start($t[2],$t[3]);
  $s->[3] = $t[3] + 1;
  $s->[1] |= 0x10 if ($t[1] eq '-');
  # mapQ
  $s->[4] = $t[6] == 0? 25 : 0;
  # mate coordinate
  $s->[6] = '*'; $s->[7] = $s->[8] = 0;
  $nm = &some_processing(\@t,\@$s);
  return ($ret, $nm);
}

sub bowtie2sam_paired {
  my ($line1, $s1, $line2, $s2) = @_;

  chomp($line1);
  chomp($line2);
  my @t1 = split("\t", $line1);
  my @t2 = split("\t", $line2);
  my $ret1 = "";
  my $ret2 = "";
  my $nm2 = "";
  my $nm1 = "";
  @$s1 = ();
  @$s2 = ();

  # initial flag (will be updated later)
  $s1->[1] = $s2->[1] = 0;
  $s1->[1] = $s2->[1] = 0x01;  #read is paired

  # read name
  $s1->[1] = ($t1[0] =~ /\/1$/) ? 0x40 : 0x80;
  $s2->[1] = ($t2[0] =~ /\/1$/) ? 0x40 : 0x80 if ($line2 ne "");
  #$s1->[1] = 0x40 if ($t1[0] =~ /\/1$/);
  #$s2->[1] = 0x80 if ($s2->[0] =~ /\/2$/);
  $ret1 = $t1[0];
  $ret2 = $t2[0] if ($line2 ne "");
  my $name = $t1[0]; 
  $name =~ s/\/[12]$//;
  $s1->[0] = $s2->[0] = $name;

  # coor
  #$s->[2] = $t[2]; 
  #$s->[2] = get_start($t[2]);
  #$s->[3] = $t[3] + 1;
  ($s1->[2],$s1->[3]) = get_chrom_and_start($t1[2],$t1[3]);
  ($s2->[2],$s2->[3]) = get_chrom_and_start($t2[2],$t2[3]) if ($line2 ne "");
  
  # read & quality
  $s1->[9] = $t1[4]; $s1->[10] = $t1[5];
  $s2->[9] = $t2[4] if ($line2 ne ""); $s2->[10] = $t2[5] if ($line2 ne "");
  
  # cigar
  #$s->[5] = length($s->[9]) . "M";
  $s1->[5] = get_cigar($t1[3],$s1->[9],$t1[2]);
  $s2->[5] = get_cigar($t2[3],$s2->[9],$t2[2]) if ($line2 ne "");
  
  #strandedness
  $s1->[1] += 0x10 if ($t1[1] eq '-');  #strand of query
  if ($line2 ne "") {  #strand of query
      $s2->[1] += 0x10 if ($t2[1] eq '-'); 
      if ((split(/\/[12]$/,$ret1))[0] =~ (split(/\/[12]$/,$ret2))[0]) {
	  # there's mates!
	  
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
	  $nm2 = &some_processing(\@t2,\@$s2);  #only print the mate if paired
      } else {
	  #for unpaired
	  #print "UNPAIRED! at $line_count\n";
	  $s1->[6] = $s2->[6] = '*'; 
	  $s1->[7] = $s1->[8] = $s2->[7] = $s2->[8] = 0;
	  $s1->[1] += 0x08;
      }
  } else {
      #also unpaired, but the last line in the file
      #for unpaired
      #print "UNPAIRED! at $line_count\n";
      $s1->[6] = $s2->[6] = '*'; 
      $s1->[7] = $s1->[8] = $s2->[7] = $s2->[8] = 0;
      $s1->[1] += 0x08;
  }
  $nm1 = &some_processing(\@t1,\@$s1);
  
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
	#its a junction read like this:
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
    $start++;  #dm3 coords are 0-based, but we need 1-based
    if (length(@c)>1) {
	#there's a junction read
	#assuming that junctions are same chrom
	$start += $c[2];
	$chrom = $c[1];
    }
    return ($chrom, $start);
}



