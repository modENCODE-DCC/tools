#!/usr/bin/perl
use lib '/var/www/submit/script/validators/modencode';
use Data::Dumper;
use ModENCODE::Parser::GFF3;
use ModENCODE::Config;
use XMLWriter;
ModENCODE::Config::set_cfg('/var/www/submit/script/validators/modencode/validator.ini');
ModENCODE::Cache::init();

use strict;

sub get_build_config {
  my $config = ModENCODE::Config::get_genome_builds();
  my @build_config_strings = keys(%$config);
  my $build_config = {};
  foreach my $build_config_string (@build_config_strings) {
    my (undef, $source, $build) = split(/ +/, $build_config_string);
    $build_config->{$source} = {} unless $build_config->{$source};
    $build_config->{$source}->{$build} = {} unless $build_config->{$source}->{$build};
    my @chromosomes = split(/, */, $config->{$build_config_string}->{'chromosomes'});
    my $type = $config->{$build_config_string}->{'type'};
    foreach my $chr (@chromosomes) {
      $build_config->{$source}->{$build}->{$chr}->{'seq_id'} = $chr;
      $build_config->{$source}->{$build}->{$chr}->{'type'} = $type;
      $build_config->{$source}->{$build}->{$chr}->{'start'} = $config->{$build_config_string}->{$chr . '_start'};
      $build_config->{$source}->{$build}->{$chr}->{'end'} = $config->{$build_config_string}->{$chr . '_end'};
      $build_config->{$source}->{$build}->{$chr}->{'organism'} = $config->{$build_config_string}->{'organism'};
    }
  }
  return $build_config;
}
my $gff_counter = 1;
sub id_callback {
  my ($parser, $id, $name, $seqid, $source, $type, $start, $end, $score, $strand, $phase) = @_;
  $id ||= "gff_" . sprintf("ID%.6d", ++$gff_counter);
  if ($type !~ /^(gene|transcript|CDS|EST|chromosome|chromosome_arm)$/) {
    $id = $parser->{'gff_submission_name'} . "." . $id;
  }
  return $id;
}



open(IN, "../small.xml");

my $submission_name = "Aggregate C. elegans transcript creation from 19 stages";
my @filenames = (
  "Aggregate_1003.integrated_genelets.ws170.gff3",
  "Aggregate_1003.confirmed_introns_all.ws170.gff3",
  "Aggregate_1003.confirmed_polya.ws170.gff3",
  "Aggregate_1003.confirmed_splice_leaders.ws170.gff3",
  "Aggregate_1003.genelets.ws170.gff3",
  "Aggregate_1003.integrated_transcripts.ws170.gff3"
);


my $collected_lines = "";
my $collecting = 0;
my $skipping_data_features = 0;
my $collected_data_feature = "";
my %filename_to_datum;

open(TMP, ">out_001_no_data_features.tmp");

# Find all the <data_feature> entries for the <data> entry for the given GFF
print STDERR "Scanning XML for GFF files.\n";
#my $filename = $filenames[0];
my %delete_features;
while (my $line = <IN>) {
  if (!$collecting) {
    ($collecting) = ($line =~ m/^\s*<data id="([^"]*)"/);
  }
  if ($skipping_data_features && ($line !~ /<data_feature>/ && $line !~ /<data_id>/ && $line !~ /<feature_id>/ && $line !~ /<\/data_feature>/)) {
    my ($spaces) = ($line =~ m/^(\s*)/);
    print TMP "$spaces<!-- Replace " . scalar(keys(%delete_features)) . " features from $skipping_data_features here -->\n";
    $skipping_data_features = 0;
  }
  if ($collecting) {
    $collected_lines .= $line;
    if ($line =~ /^\s*<\/data>/) {
      foreach my $filename (@filenames) {
        if ($collected_lines =~ /^\s*<value>\E$filename\E<\/value>/m) {
          print STDERR "  Found: $filename\n";
          $collected_data_feature = "";
          $skipping_data_features = $filename;
          $filename_to_datum{$filename} = $collecting;
        }
      }
      print TMP $collected_lines;
      $collecting = 0;
      $collected_lines = "";
      next;
    }
  }

  if (!$collecting && !$skipping_data_features) {
    print TMP $line;
  }
  if ($skipping_data_features) {
    my ($feature_id) = ($line =~ m/<feature_id>([^<]*)<\/feature_id>/);
    $delete_features{$feature_id} = 1 if ($feature_id);
  }
}
print STDERR "  Collected " . scalar(keys(%delete_features)) . " features attached to the above GFF file(s).\n";

close(IN);
close(TMP);

# Delete all the <feature> entries that we saw in the above <data_feature>s
open(TMP, ">out_002_no_features.tmp");
open(IN, "out_001_no_data_features.tmp");

print STDERR "    Deleting <feature> elements associated with GFF(s).\n";
$collected_lines = "";
$collecting = 0;
my $removed_features = 0;
while (my $line = <IN>) {
  if ($line =~ /^\s*<feature id=/) {
    $collecting = 1;
  }
  if ($collecting) {
    $collected_lines .= $line;
    if ($line =~ /^\s*<\/feature>/) {
      my ($feature_id) = ($collected_lines =~ m/<feature id=\"([^"]*)\"/);
      if ($delete_features{$feature_id}) {
        $removed_features++;
      } else {
        print TMP $collected_lines;
      }
      $collecting = 0;
      $collected_lines = "";
    }
  } else {
    print TMP $line;
  }
}
print STDERR "      Removed $removed_features features.\n";
close(TMP);
close(IN);
# TODO: Unlink out_001.tmp

# Delete all the <featureloc>, <analysisfeature>, <feature_relationship>, and <featureprop> entries for these features
print STDERR "    Deleting associated <featureloc>, <analysisfeature>, <feature_relationship>, and <featureprop> entries.\n";
open(TMP, ">out_003_nolocs_noprops_noanalysis.tmp");
open(IN, "out_002_no_features.tmp");
$collected_lines = "";
$collecting = 0;
my %removed = ( "featureprop" => 0, "featureloc" => 0, "analysisfeature" => 0, "feature_relationship" => 0 );
while (my $line = <IN>) {
  if (!$collecting) {
    ($collecting) = ($line =~ /^\s*<(featureprop|featureloc|analysisfeature|feature_relationship)>/);
  }
  if ($collecting) {
    $collected_lines .= $line;
    if ($line =~ /^\s*<\/$collecting>/) {
      my ($feature_id) = ($collected_lines =~ m/<feature_id>([^<]*)<\/feature_id>/m);
      my ($subject_id) = ($collected_lines =~ m/<subject_id>([^<]*)<\/subject_id>/m);
      my ($object_id) = ($collected_lines =~ m/<object_id>([^<]*)<\/object_id>/m);
      if ($delete_features{$feature_id} || $delete_features{$subject_id} || $delete_features{$object_id}) {
        $removed{$collecting}++;
      } else {
        print TMP $collected_lines;
      }
      $collecting = 0;
      $collected_lines = "";
    }
  } else {
    print TMP $line;
  }
}
print STDERR "      Removed: {\n        " . join(",\n        ", map { $_ . " => " . $removed{$_} } keys(%removed)) . "\n      }\n";
close(TMP);
close(IN);


my $xmlwriter = new XMLWriter();
$xmlwriter->set_output_file("out_004_with_new_features.xml") or die "Failed to open new XML for writing.";
$xmlwriter->init();

foreach my $filename (@filenames) {
  my $data_id = $filename_to_datum{$filename};
  unless ($data_id) { die "No data id for $filename"; }
  print STDERR "  Scanning GFF $filename for features to add.\n";
  my $gff_filename = "group_gff/$filename";
  open(GFF, $gff_filename) or die "Couldn't open $gff_filename for reading";
  my $build_config = get_build_config();
  my $gff_sub_name = $submission_name;
  $gff_sub_name =~ s/[^0-9A-Za-z]/_/g;
  my $parser = new ModENCODE::Parser::GFF3({
      'gff3' => \*GFF,
      'builds' => $build_config,
      'id_callback' => *id_callback,
      'source_prefix' => $gff_sub_name
    });
  $parser->{'gff_submission_name'} = $gff_sub_name;

  #ModENCODE::Cache::set_paused(1);
  my $group_iter = $parser->iterator();
  my $group_num = 0;

  while ($group_iter->has_next()) {
    $group_num++;
    my @features;
    eval { @features = $group_iter->next() };
    if ($@) {
      my $errmsg = $@;
      chomp $errmsg;
      my ($message, $line) = ($errmsg =~ m/^(.*)\s+at\s+.*GFF3\.pm\s+line\s+\d+\s*.+line\s+(\d+)/);
      if ($message && $line) {
        print STDERR "Error parsing GFF '" . $gff_filename . "': $message at line $line of the GFF.", "error", "<";
      } else {
        print STDERR "Error parsing GFF: '$errmsg'", "error", "<";
      }
      exit;
    }
    ModENCODE::Cache::clear();
    # TODO: Generate ChadoXML from @features
    # This includes <data_feature>, <featureloc>, <featureprop>, <analysisfeature>, and <feature_relationship>
    print STDERR "  Writing " . scalar(@features) . " features found in $gff_filename.\n";
    foreach my $feature (@features) {
      $xmlwriter->write_feature($feature, $data_id);
      $feature->set_content(undef);
      undef($feature);
    }
  }
  close(GFF);
}

print STDERR "  Combining output files.\n";
$xmlwriter->combine();
print STDERR "    Done.\n";

