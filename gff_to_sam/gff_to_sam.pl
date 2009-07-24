#!/usr/bin/perl

use strict;

open GFF, $ARGV[0] or die "Couldn't open ${ARGV[0]}: $!";
my $filesize = -s $ARGV[0];

# Header
print <<EOF
\@SQ	SN:chr2L	AS:FlyBase r5	LN:23011544	SP:Drosophila melanogaster
\@SQ	SN:chr2LHet	AS:FlyBase r5	LN:368872	SP:Drosophila melanogaster
\@SQ	SN:chr2R	AS:FlyBase r5	LN:21146708	SP:Drosophila melanogaster
\@SQ	SN:chr2RHet	AS:FlyBase r5	LN:3288761	SP:Drosophila melanogaster
\@SQ	SN:chr3L	AS:FlyBase r5	LN:24543557	SP:Drosophila melanogaster
\@SQ	SN:chr3LHet	AS:FlyBase r5	LN:2555491	SP:Drosophila melanogaster
\@SQ	SN:chr3R	AS:FlyBase r5	LN:27905053	SP:Drosophila melanogaster
\@SQ	SN:chr3RHet	AS:FlyBase r5	LN:2517507	SP:Drosophila melanogaster
\@SQ	SN:chr4	AS:FlyBase r5	LN:1351857	SP:Drosophila melanogaster
\@SQ	SN:chrX	AS:FlyBase r5	LN:22422827	SP:Drosophila melanogaster
\@SQ	SN:chrXHet	AS:FlyBase r5	LN:204112	SP:Drosophila melanogaster
\@SQ	SN:chrYHet	AS:FlyBase r5	LN:347038	SP:Drosophila melanogaster
\@SQ	SN:chrM	AS:FlyBase r5	LN:19517	SP:Drosophila melanogaster
\@SQ	SN:chrU	AS:FlyBase r5	LN:10049159	SP:Drosophila melanogaster
\@SQ	SN:chrUextra	AS:FlyBase r5	LN:29004788	SP:Drosophila melanogaster
EOF
;


my $sam_idx = 0;
my @hits_for_this_sequence;
my $old_score = 0;
my $seq_length = 0;
my $sequence = "";
my $progress;
while (my $line = <GFF>) {
  next if ($line =~ /^\s*$/ || $line =~ /^\s*#/);

  my $new_progress = int((tell(GFF) / $filesize) * 100);
  if ($new_progress >= $progress + 2) {
    $progress = $new_progress;
    print STDERR $progress . "%\n";;
  }

  my ($seq, $src, $type, $start, $end, $score, $strand, $phase, $attrs) = split(/\t/, $line);
  if ($seq =~ /^Sequence:/) {
    for (my $i = 0; $i < $old_score; $i++) {
      $sam_idx++;
      foreach my $hit (@hits_for_this_sequence) {
        my ($read_id, $strand, $seq, $start) = @$hit;
        $read_id .= "_$sam_idx";
        my $num_matches = "NH:i:" . scalar(@hits_for_this_sequence);
        my $hits = "h" x length($sequence);
        print join("\t", $read_id, $strand, $seq, $start, "0", $seq_length, "*", "0", "0", $sequence, $hits, $num_matches) . "\n";
      }
    }
    ($sequence) = ($attrs =~ /ID=Sequence:([^;]*)/);
    $seq_length = $end . "M";
    @hits_for_this_sequence = ();
    next;
  }

  
  $src =~ s/\s|[@!#\$%^&*()\[\]\{\}-]/_/g;
  my $strand = $strand =~ "-" ? 16 : 0; # 0x10 is the "strand of the query" flag
  $old_score = $score;

  push @hits_for_this_sequence, [ $src, $strand, $seq, $start ];
}
# Print out the last set of hits
for (my $i = 0; $i < $old_score; $i++) {
  $sam_idx++;
  foreach my $hit (@hits_for_this_sequence) {
    my ($read_id, $strand, $seq, $start) = @$hit;
    $read_id .= "_$sam_idx";
    my $num_matches = "NH:i:" . scalar(@hits_for_this_sequence);
    my $hits = "h" x length($sequence);
    print join("\t", $read_id, $strand, $seq, $start, "0", $seq_length, "*", "0", "0", $sequence, $hits, $num_matches) . "\n";
  }
}

close GFF;

sub get_next_line {
  my ($fh) = @_;
  while (my $line = <$fh>) {
    next if ($line =~ /^\s*$/ || $line =~ /^\s*#/);
    return $line;
  }
}
