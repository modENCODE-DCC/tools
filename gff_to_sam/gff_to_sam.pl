#!/usr/bin/perl

use strict;
use IO::Uncompress::Gunzip;

sub usage {
  print "\n";
  print "Usage: $0 [--header header.txt] gff_file_1.gff [ .. gff_file_n.gff ] > out.sam\n";
  print "  --seq-in-id: Lai-style; the sequence is in the ID\n";
  print "  --seq-in-attr: Waterston-style; the sequence is in an attribute\n";
  print "  --header: Use contents of header.txt as SAM header\n";
  print "  gff_file can be '-', in which case STDIN is used\n";
  print "\n";
}

if (scalar(@ARGV) == 0) { usage(); exit; }

my $parse_type;
if ($ARGV[0] eq "--seq-in-id") {
  $parse_type = "seq-in-id";
} elsif ($ARGV[0] eq "--seq-in-attr") {
  $parse_type = "seq-in-attr";
} else {
  usage();
  die "Invalid parse type: " . $ARGV[0];
}
print STDERR "Parse mode: $parse_type\n";
splice(@ARGV, 0, 1);

my $header = "";
for (my $i = 0; $i < scalar(@ARGV); $i++) {
  if ($ARGV[$i] eq "--header") {
    my $header_file = $ARGV[$i+1];
    open HEADER, $header_file or die "Couldn't open header in $header_file";
    while (<HEADER>) { $header .= $_; };
    close HEADER;
    splice(@ARGV, $i, 2);
    last;
  }
}

if ($header eq "") {
  print STDERR "Using default FlyBase r5 header\n";
  # Header
  $header = <<EOF
  \@SQ	SN:2L	AS:FlyBase r5	LN:23011544	SP:Drosophila melanogaster
  \@SQ	SN:2LHet	AS:FlyBase r5	LN:368872	SP:Drosophila melanogaster
  \@SQ	SN:2R	AS:FlyBase r5	LN:21146708	SP:Drosophila melanogaster
  \@SQ	SN:2RHet	AS:FlyBase r5	LN:3288761	SP:Drosophila melanogaster
  \@SQ	SN:3L	AS:FlyBase r5	LN:24543557	SP:Drosophila melanogaster
  \@SQ	SN:3LHet	AS:FlyBase r5	LN:2555491	SP:Drosophila melanogaster
  \@SQ	SN:3R	AS:FlyBase r5	LN:27905053	SP:Drosophila melanogaster
  \@SQ	SN:3RHet	AS:FlyBase r5	LN:2517507	SP:Drosophila melanogaster
  \@SQ	SN:4	AS:FlyBase r5	LN:1351857	SP:Drosophila melanogaster
  \@SQ	SN:X	AS:FlyBase r5	LN:22422827	SP:Drosophila melanogaster
  \@SQ	SN:XHet	AS:FlyBase r5	LN:204112	SP:Drosophila melanogaster
  \@SQ	SN:YHet	AS:FlyBase r5	LN:347038	SP:Drosophila melanogaster
  \@SQ	SN:M	AS:FlyBase r5	LN:19517	SP:Drosophila melanogaster
  \@SQ	SN:U	AS:FlyBase r5	LN:10049159	SP:Drosophila melanogaster
  \@SQ	SN:Uextra	AS:FlyBase r5	LN:29004788	SP:Drosophila melanogaster
EOF
;
}

print $header;

foreach my $gff_file (@ARGV) {
  my $gff_fh;
  my $filesize;
  if ($gff_file eq "-") {
    $gff_fh = \*STDIN;
    $filesize = 0;
    print STDERR "Reading from STDIN\n";
  } elsif ($gff_file =~ /\.gz$/) {
    $gff_fh = new IO::Uncompress::Gunzip($gff_file) or die "Couldn't open $gff_file as a gzip";
    $filesize = 0;
    print STDERR "Reading (compressed data) from $gff_file\n";
  } else {
    open $gff_fh, $gff_file or die "Couldn't open $gff_file: $!";
    $filesize = -s $gff_file;
    print STDERR "Reading from $gff_file\n";
  }

  my $sam_idx = 0;
  my @hits_for_this_sequence;
  my $old_score = 0;
  my $cigar = 0;
  my $sequence = "";
  my $progress;
  my $new_progress;

    while (my $line = <$gff_fh>) {
      next if ($line =~ /^\s*$/ || $line =~ /^\s*#/);

      # Progress
      if ($filesize > 0) {
        $new_progress = int((tell($gff_fh) / $filesize) * 100);
        if ($new_progress >= $progress + 2) {
          $progress = $new_progress;
          print STDERR $progress . "%\n";;
        }
      } else {
        $new_progress++;
        if ($new_progress >= 100000) {
          $progress += $new_progress;
          print STDERR "$progress lines processed\n";
          $new_progress = 0;
        }
      }

      # Parse GFF
      my ($seq, $src, $type, $start, $end, $score, $strand, $phase, $attrs) = split(/\t/, $line);
      if ($parse_type eq "seq-in-id") {
        # <seq-in-id>
        if ($seq =~ /^Sequence:/) {
          for (my $i = 0; $i < $old_score; $i++) {
            $sam_idx++;
            foreach my $hit (@hits_for_this_sequence) {
              my ($read_id, $strand, $seq, $start) = @$hit;
              $read_id .= "_$sam_idx";
              my $num_matches = "NH:i:" . scalar(@hits_for_this_sequence);
              #my $hits = "h" x length($sequence);
              print join("\t", $read_id, $strand, $seq, $start, "255", $cigar, "*", "0", "0", $sequence, "*", $num_matches) . "\n";
            }
          }
          ($sequence) = ($attrs =~ /ID=Sequence:([^;]*)/);
          $cigar = $end . "M";
          @hits_for_this_sequence = ();
          next;
        }

        $src =~ s/\s|[@!#\$%^&*()\[\]\{\}-]/_/g;
        $strand = ($strand eq "-") ? 0x0010 : 0;
        $old_score = $score;

        push @hits_for_this_sequence, [ $src, $strand, $seq, $start ];
      } else { # </seq-in-id>
        # <seq-in-attr>
        my @attributes = split(/;/,$attrs);
        my $cigar = "";
        my $read_length = 0;
        my ($qname, $cigar, $tag);

        # Read name and length
        ($qname, $read_length) = ((grep { m/^Target=/ } @attributes)[0] =~ /Target\=(\S+)\s\d+\s(\d+)/);
        die "No read_length" unless $read_length > 0;

        # Bit flag
        $strand = ($strand eq "-") ? 0x0010 : 0;

        # Default cigar
        $cigar = $read_length . "M";

        # Sequence
        $sequence = "*";

        # Tag
        $tag = "NM:i:" . ($read_length - $score); # Waterston submissions use score to hold absolute number of matches

        # Extra attributes
        foreach my $att (@attributes) {
          my ($aname, $aval) = split(/=/, $att);
          if ($aname =~ /Gap/) {
            # Use Gap for cigar
            my @cigar_array = split(/ /, $aval);
            my $l = '';
            $cigar = "";
            foreach my $a (@cigar_array) {
              my $nums = my $letter = '';
              ($letter, $nums) = ($a =~ m/(\D)(\d+)/);
              $cigar .= $nums . $letter;
            }
            $cigar =~ s/D/N/;
          }
          if ($aname =~ /seq/) {
            $sequence = $aval;
          }
          if ($aname =~ /Parent/) {
            $tag .= ' Y1:Z:' . $aval;
          }
        }

        print join("\t", $qname, $strand, $seq, $start, "255", $cigar, "*", "0", "0", $sequence, "*", $tag) . "\n";


      } # </seq-in-attr>
    }

    if ($parse_type eq "seq-in-id") {
      # <seq-in-id>
      # Print out the last set of hits
      for (my $i = 0; $i < $old_score; $i++) {
        $sam_idx++;
        foreach my $hit (@hits_for_this_sequence) {
          my ($read_id, $strand, $seq, $start) = @$hit;
          $read_id .= "_$sam_idx";
          my $num_matches = "NH:i:" . scalar(@hits_for_this_sequence);
          #my $hits = "h" x length($sequence);
          print join("\t", $read_id, $strand, $seq, $start, "255", $cigar, "*", "0", "0", $sequence, "*", $num_matches) . "\n";
        }
      }
    } # </seq-in-id>

  # Done with this GFF
  close $gff_fh;
}
