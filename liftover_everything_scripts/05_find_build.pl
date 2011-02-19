#!/usr/bin/perl

use strict;
use IO::Uncompress::Gunzip qw();
use Data::Dumper;

use constant SAMTOOLS => "/var/www/submit/script/validators/modencode/samtools/samtools";
use constant BUILDS => "/var/www/submit/script/validators/modencode/genome_builds.ini";

sub uniq {
  my %seen;
  return grep { !$seen{$_}++ } @_;
}
sub read_all_until {
  my ($filename, $re, $max) = @_;
  my $ret = "";
  open RAW, "<", $filename or die "Couldn't open $filename";
  if ($filename =~ /\.gz$/) {
    my $f = new IO::Uncompress::Gunzip(*RAW);
    while ($_ = $f->getline()) {
      last if ($_ =~ /$re/);
      $ret .= $_;
      return undef if (--$max <= 0);
    }
    $f->close;
  } else {
    while (<RAW>) {
      last if ($_ =~ /$re/);
      $ret .= $_;
      return undef if (--$max <= 0);
    }
  }
  close RAW;
  return $ret;
}
sub read_until {
  my ($filename, $re, $max) = @_;
  open RAW, "<", $filename or die "Couldn't open $filename";
  my $ret;
  if ($filename =~ /\.gz$/) {
    my $f = new IO::Uncompress::Gunzip(*RAW);
    while ($ret = $f->getline()) {
      last if ($ret =~ /$re/);
      return undef if (--$max <= 0);
    }
    $f->close;
  } else {
    while ($ret = <RAW>) {
      last if ($ret =~ /$re/);
      return undef if (--$max <= 0);
    }
  }
  close RAW;
  return $ret;
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
my %genome_builds;
sub get_genome_builds {
  return %genome_builds if (keys(%genome_builds));
  open BFH, "<", BUILDS;
  my $current_build;
  while (my $line = <BFH>) {
    chomp $line;
    next if $line =~ /^\s*$/;
    if ($line =~ /^\[genome_build/) {
      ($current_build) = ($line =~ /genome_build.*WS(\d{3})/i);
      $genome_builds{$current_build} = {};
    } else {
      next if $line !~ /_start=|_end=/;
      next unless $current_build;
      my ($attr, $value) = split(/=/, $line, 2);
      $genome_builds{$current_build}->{$attr} = $value;
    }
  }
  close BFH;
  delete($genome_builds{''});
  return %genome_builds;
}

my %seen_builds;
sub get_sam_build {
  my ($file, $type) = @_;
  my $opts = ($type eq "SAM") ? "-S -H" : "-H";
  my $cmd = SAMTOOLS . " view $opts \"$file\"";
  my $header = `$cmd`;
  my @builds = uniq($header =~ /AS:[^:]*ws(\d{3})/mig);
  return $builds[0] if (scalar(@builds) == 1);
  return undef;
}
sub get_gff_build {
  my $file = shift;
  my $line = read_until($file, "^##genome-(build|version)", 5);
  my ($build) = ($line =~ /^##genome-(?:build|version).*WS(\d{3})/i);
  if (!$build) {
    # Maybe it's using sequence regions
    my %genome_builds = get_genome_builds();
    my $header = read_all_until($file, "^[^#]", 100);
    my @regions = ($header =~ /##sequence-region\s+(\S+)\s+(\d+)\s+(\d+)\s*$/mg);
    foreach my $gbuild (keys(%genome_builds)) {
      next unless scalar(@regions);
      my $is_okay = 1;
      for (my $i = 0; $i < scalar(@regions); $i+=3) {
        my ($chr, $start, $end) = ($regions[$i], $regions[$i+1], $regions[$i+2]);
        if ($chr eq "III" && $end == 13783685) {
          $end = 13783681; # Someone put up a bad header in the GBrowse tutorial, and it got used in some submissions
        }
        my ($gstart, $gend) = ($genome_builds{$gbuild}->{"${chr}_start"}, $genome_builds{$gbuild}->{"${chr}_end"});
        if ($start != $gstart || $end != $gend) {
          $is_okay = 0;
          last;
        }
      }
      if ($is_okay) {
        $build = $gbuild;
        last;
      }
    }
  }
  if (!$build) {
    # Last chance
    my ($project_id) = ($file =~ /\/(\d+)\/extracted\//);
    $build = $seen_builds{$project_id};
  }
  return $build;
}
sub get_wig_build {
  my $file = shift;
  my ($project_id) = ($file =~ /\/(\d+)\/extracted\//);
  my $build = $seen_builds{$project_id};
  if (!$build) {
    # Check the SDRF?
    my ($sdrf) = glob("/modencode/raw/data/$project_id/extracted/*[Ss][Dd][Rr][Ff]*");
    ($sdrf) = glob("/modencode/raw/data/$project_id/extracted/*/*[Ss][Dd][Rr][Ff]*") unless $sdrf;
    open SDRF, "<", $sdrf;
    while (<SDRF>) {
      ($build) = (/\t"?WS(\d{3})"?(?:\t|$)/);
      last if $build;
    }
    close SDRF;
  }
  return $build;
}
sub get_xml_build {
  my $file = shift;
  my ($project_id) = ($file =~ /\/(\d+)\/extracted\//);
  my $build = $seen_builds{$project_id};
  # Maybe there's just no features?
  if (!$build && system("grep -l featureloc \"$file\" >/dev/null")) {
    return -1;
  }
  return $build;
}
open IN, "04_worm_only.txt";
open OUT, ">", "05_type_build_file.txt";

my %genome_builds = get_genome_builds();
while (my $line = <IN>) {
  chomp $line;
  my ($type, $file) = split(/\t/, $line);

  my $build;

  if ($type eq "BAM" || $type eq "SAM") {
    $build = get_sam_build($file, $type);
  } elsif ($type eq "GFF") {
    $build = get_gff_build($file, $type);
  } elsif ($type eq "WIG") {
    $build = get_wig_build($file, $type);
  } elsif ($type eq "XML") {
    $build = get_xml_build($file, $type);
    next if $build == -1; # No featurelocs in this to liftover...
  } else {
    die "Unknown type: $type\n";
  }

  my ($project_id) = ($file =~ /\/(\d+)\/extracted\//);
  $seen_builds{$project_id} = $build;

  if (!$build) {
    die "No build for $line"
  }

  print OUT join("\t", $type, $build, $file) . "\n";
}
close IN;
close OUT;
