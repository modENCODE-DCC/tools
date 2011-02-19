#!/usr/bin/perl

use strict;
use lib "/home/yostinso/liftover/perl/lib/perl5/x86_64-linux-gnu-thread-multi/";
use IO::Uncompress::Gunzip qw();
use IO::Uncompress::Bunzip2 qw();
use IO::Uncompress::Unzip qw();

sub go {
  open OUT, ">", "02_types_and_files.txt";
  open FH, "<", "01_extracted_and_tracks.txt";
  while (my $line = <FH>) {
    chomp $line;
    # MISC:
    if (is_folder($line)) {
    } elsif (is_empty($line)) {
    } elsif (is_bak($line)) {
    } elsif (is_sdrf($line)) {
    } elsif (is_idf($line)) {
    } elsif (is_readme($line)) {
    } elsif (is_md5($line)) {
    } elsif (is_liftover_report($line)) {
    } elsif (is_tarball($line)) {
    } elsif (is_hidden_file($line)) {

    # TRACKS:
    } elsif (is_track($line)) {
      if (is_wigdb($line)) {
      } elsif (is_gff($line)) {
      } elsif (is_bigwig($line)) {
      } elsif (is_bam($line)) {
      } elsif (is_sam($line)) {
      } elsif (is_bam_support($line)) {
      } else {
        die "What is $line";
      }

    # DATA that can/should be lifed:
    } elsif (is_chadoxml($line)) {
      print OUT "XML\t$line\n";
    } elsif (is_wig($line)) {
      print OUT "WIG\t$line\n";
    } elsif (is_gff($line)) {
      print OUT "GFF\t$line\n";
    } elsif (is_bam($line)) {
      print OUT "BAM\t$line\n";
    } elsif (is_sam($line)) {
      print OUT "SAM\t$line\n";
    } elsif (is_bam_support($line)) {
    } elsif (is_chadoxml_patch($line)) {

    # RAW DATA:
    } elsif (is_raw_data($line)) {
      die if ($line =~ /gff/i);
    } elsif (is_img_data($line)) {
      die if ($line =~ /gff/i);
    } elsif (is_gtf_data($line)) {
      die if ($line =~ /gff/i);

    # OTHER:
    } else {
      die "What is $line?";
    }
  }
  close FH;
  close OUT;
}

sub is_bam_support {
  my $filename = shift;
  return ($filename =~ /\.bai$|\.sorted\.bam$/i);
}

sub is_bam {
  my $filename = shift;
  if ($filename =~ /\.bam$/i && $filename !~ /\.sorted\.bam$/i ) {
    return 1 if (read_bam_header($filename) =~ /^\@SQ|\@HD/);
  }
}

sub is_sam {
  my $filename = shift;
  if ($filename =~ /\.sam(\.gz|\.bz2|\.zip)?$/i) {
    return 1 if (read_sam_header($filename) =~ /^\@SQ|\@HD/);
  }
}

sub is_gff {
  my $filename = shift;
  my $line = "";
  if ($filename =~ /\.(gff3?|alignments)$/i) {
    $line = read_line($filename);
  } elsif ($filename =~ /\.(gff3?|alignments)\.gz$/i) {
    $line = read_gz_line($filename);
  } elsif ($filename =~ /\.(gff3?|alignments)\.bz2$/i) {
    $line = read_bz2_line($filename);
  } elsif ($filename =~ /\.(gff3?|alignments)\.zip$/i) {
    $line = read_zip_line($filename);
  }
  return 1 if ($line =~ /^##/);
  return 1 if ($line =~ /\S+\t\S+\t\S+\t\d+\t\d+(\.|\d+)\t(\+|\-|\.)\t(\.|\d+)\t/);
  return 0;
}

sub is_wigdb {
  my $filename = shift;
  return ($filename =~ /\.wigdb$/i);
}

sub is_bigwig {
  my $filename = shift;
  return ($filename =~ /\.bw$/i);
}

sub is_track {
  my $filename = shift;
  return ($filename =~ m|/tracks/|i);
}

sub is_chadoxml {
  my $filename = shift;
  return ($filename =~ /\/\d+\.chadoxml$/i);
}

sub is_chadoxml_patch {
  my $filename = shift;
  return (($filename =~ /\.chadoxml$/i) && ($filename !~ /\/\d+\.chadoxml$/i));
}

sub is_wig {
  my $filename = shift;
  if ($filename =~ /\.gr$|\.wig$|\.bed(Graph)?$/i) {
    for (my $i = 0; $i < 5; $i++) {
      my $line = read_line($filename, $i);
      return 1 if ($line =~ /^track/);
      return 1 if ($line =~ /^\S+\s+\d+\s+\d+/);
    }
  }
  return 0;
}

sub is_img_data {
  my $filename = shift;
  return 1 if ($filename =~ /\.jpg$|\.tif$/i);
  return 0;
}

sub is_gtf_data {
  my $filename = shift;
  return 1 if ($filename =~ /\.gtf$/i);
  return 0;
}

sub is_raw_data {
  my $filename = shift;
  my $line;
  return 1 if $filename =~ /\/exp.zip$/;
  return 1 if $filename =~ /\.keys$/;
  return 1 if $filename =~ /\.sff$/;
  if ($filename =~ /\.gz$/i) {
    $line = read_gz_line($filename);
  } elsif ($filename =~ /\.bz2$/i) {
    $line = read_bz2_line($filename);
  } elsif ($filename =~ /\.zip$/i) {
    $line = read_zip_line($filename);
  } else {
    $line = read_line($filename);
  }
  if ($filename =~ /fasta|\.fa$|\.fna$|\.qual$/i) {
    return 1 if ($line =~ /^>/);
  } elsif ($filename =~ /\.bpmap$/i) {
    return 1;
  } elsif ($filename =~ /\.txt(\.gz)?$/i) {
    return 1;
  } elsif ($filename =~ /\.zhmm/i) {
    return 1 if ($line =~ /^zHMM/);
  } elsif ($filename =~ /fastq/i) {
    return 1 if ($line =~ /^@/);
    return 1 if (read_gz_line($filename) =~ /^@/);
  } elsif ($filename =~ /\.txt(\.gz|\.bz2|\.zip)?$/i) {
    return 1 if ($line =~ /^TYPE/); # microarray
  } elsif ($filename =~ /\.CEL(\.gz|\.bz2|\.zip)?$/i) {
    return 1;
    return 1 if ($line =~ /^\[CEL\]|^\@/); # microarray
    return 1 if ($line =~ /placeholder/); # placeholder
  } elsif ($filename =~ /\.(pair|calls)(\.gz|\.bz2|\.zip)?$/i) {
    return 1 if ($line =~ /^IMAGE_ID|^# software/); # microarray
    return 1 if $filename eq "/modencode/raw/data/2758/extracted/NimbHX_O_57A0A1_353281-4_532.pair"; # This is actually a TGZ, eh?
  } elsif ($filename =~ /\.ndf(\.gz|\.bz2|\.zip)?$/i) {
    return 1 if ($line =~ /DESIGN_ID/i);
  } elsif ($filename =~ /\.pos(\.gz|\.bz2|\.zip)?$/i) {
    return 1 if ($line =~ /PROBE_ID/i);
  } elsif ($filename =~ /\.tag(\.gz|\.bz2|\.zip)?$/i) {
    return 1;
  }
  return 0;
}
sub is_empty {
  my $filename = shift;
  return 1 if -z $filename;
  return 1 if ((-s $filename) == 1);
  if ($filename =~ /\.tar\.gz$|\.tgz$/) {
    my $line = read_gz_line($filename);
    my $line = join("", grep { ord($_) } split(//, $line));
    return 1 if (length($line) == 0);
  }
  return 0;
}
sub is_tarball {
  my $filename = shift;
  return ($filename =~ /\.tgz$|\.tar.tgz$/);
}

sub is_hidden_file {
  my $filename = shift;
  return ($filename =~ /\/\.[^\/]*$/);
}

sub is_liftover_report {
  my $filename = shift;
  return ($filename =~ /liftover_report$/);
}

sub is_sdrf {
  my $filename = shift;
  return 0 unless $filename =~ /sdrf/i;
  return 1 if (read_line($filename) =~ /Protocol REF/i);
}

sub is_idf {
  my $filename = shift;
  return 0 unless $filename =~ /idf/i;
  return 1 if (read_line($filename) =~ /Investigation Title/i);
}

sub is_folder {
  my $filename = shift;
  return -d $filename;
}

sub is_bak {
  my $filename = shift;
  return ($filename =~ /\.bak$|\.orig$/);
}

sub is_readme {
  my $filename = shift;
  return ($filename =~ /\/\d+_WS\d+$|(README|MANIFEST)(.txt)?$|\.info\.xml$|\.pptx?$|\.psd$|\.xls$|\.doc$|\/go$/i);
}

sub is_md5 {
  my $filename = shift;
  return ($filename =~ /\.md5$/i);
}

sub read_gz_line {
  my ($filename, $lineno) = @_;
  $lineno ||= 0;
  open RAW, "<", $filename or die "Couldn't open $filename";
  my $f = new IO::Uncompress::Gunzip($filename);
  my $line;
  for (my $i = 0; $i <= $lineno; $i++) {
    $line = $f->getline();
  }
  $f->close;
  chomp $line;
  close RAW;
  return $line;
}

sub read_bz2_line {
  my ($filename, $lineno) = @_;
  $lineno ||= 0;
  open RAW, "<", $filename or die "Couldn't open $filename";
  my $f = new IO::Uncompress::Bunzip2($filename);
  my $line;
  for (my $i = 0; $i <= $lineno; $i++) {
    $line = $f->getline();
  }
  $f->close;
  chomp $line;
  close RAW;
  return $line;
}

sub read_zip_line {
  my ($filename, $lineno) = @_;
  $lineno ||= 0;
  open RAW, "<", $filename or die "Couldn't open $filename";
  my $f = new IO::Uncompress::Unzip($filename);
  my $line;
  for (my $i = 0; $i <= $lineno; $i++) {
    $line = $f->getline();
  }
  $f->close;
  chomp $line;
  close RAW;
  return $line;
}

sub read_line {
  my ($filename, $lineno) = @_;
  $lineno ||= 0;
  open RAW, "<", $filename or die "Couldn't open $filename";
  my $line;
  for (my $i = 0; $i <= $lineno; $i++) {
    $line = <RAW>;
  }
  chomp $line;
  close RAW;
  return $line;
}

sub read_bam_header {
  my $filename = shift;
  return `/var/www/submit/script/validators/modencode/samtools/samtools view -H "$filename" 2>/dev/null`;
}

sub read_sam_header {
  my $filename = shift;
  return `/var/www/submit/script/validators/modencode/samtools/samtools view -S -H "$filename" 2>/dev/null`;
}



go();
