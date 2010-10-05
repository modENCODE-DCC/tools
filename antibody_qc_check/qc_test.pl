#!/usr/bin/perl

use strict;
my $validator_dir;
BEGIN {
  # Find the validator
  my @dirs = (
    $ENV{'ME_VALIDATOR'},
    "/var/www/pipeline/submit/script/validators/modencode",
    "/var/www/submit/script/validators/modencode"
  );
  for my $dir (@dirs) {
    if (-d $dir) {
      push @INC, $dir;
      $validator_dir = $dir;
      last;
    }
  }
  unless ($validator_dir && -e "$validator_dir/validator.ini") {
    print STDERR "Couldn't find validator directory in " . join(", ", @dirs) . "\n";
    print STDERR "  Consider setting the ME_VALIDATOR environment variable.\n";
    die "Unable to continue";
  }
}
use ModENCODE::Validator::Data::AntibodyQC_Standalone;
use ModENCODE::Chado::Experiment;
use ModENCODE::Chado::Data;
use ModENCODE::Chado::Data_Wrapper;
use ModENCODE::Config;
use DBI;
ModENCODE::Config::set_cfg("$validator_dir/validator.ini");


my $dbh = DBI->connect("dbi:Pg:dbname=modencode_chado;host=localhost", "db_public", "ir84#4nm");

my @ids;
if ($ARGV[0] && $ARGV[0] ne "-") {
  @ids = @ARGV;
} elsif ($ARGV[0] && $ARGV[0] eq "-") {
  while (<>) {
    chomp;
    push @ids, $_;
  }
}
my %seen; @ids = grep { $_ eq (0 + $_) && !$seen{$_}++ } @ids; %seen = {};
if (!scalar(@ids)) {
  print STDERR "Usage:\n";
  print STDERR "  From a file:\n    cat ids.txt | $0 -\n";
  print STDERR "  On the command line:\n    $0 123 234 432\n";
  exit;
}
print STDERR "Checking projects: " . join(", ", @ids) . "\n";


foreach my $proj_id (@ids) {
  print STDERR "Checking project $proj_id\n";
  my $schema = "modencode_experiment_${proj_id}_data";
  my $sth_antibodies = $dbh->prepare("SELECT d.value FROM $schema.data d
    INNER JOIN $schema.cvterm cvt ON d.type_id = cvt.cvterm_id
    WHERE cvt.name = 'antibody'");
  my $res = $sth_antibodies->execute();
  next unless $res;

  my @ab_urls;
  while (my $ab_url = $sth_antibodies->fetchrow_array()) {
    if ($ab_url !~ /oldid=/) {
      print STDERR "Not a normal wiki URL ($proj_id): $ab_url\n";
    } else {
      push @ab_urls, $ab_url;
    }
  }
  $sth_antibodies->finish();
  unless (scalar(@ab_urls)) {
    print STDERR "  No antibodies found.\n";
    next;
  } else {
    print STDERR "  Checking " . scalar(@ab_urls) . " antibodies.\n";
  }

  my $v = init_validator($dbh, $schema);
  print_tries_header($v->get_tries());

  foreach my $ab_url (@ab_urls) {
    my $data_wrapper = new ModENCODE::Chado::Data_Wrapper({ 'object' => ModENCODE::Chado::Data->new_no_cache({ 'value' => $ab_url, 'heading' => $ab_url })});
    $v->add_datum_pair([0, 0, $data_wrapper ]);
    my $res = $v->validate();
    print_tries($proj_id, $ab_url, $res, $v->get_tries());
    $v->clear_data();
  }

}

sub print_tries_header {
  my ($tries) = @_;
  my @fields = ("Submission", "Antibody", "Passed");
  foreach my $primary ("Immunoblot", "Immunofluorescence", "Override") {
    my $assay = $tries->{$primary};
    foreach my $key (sort(keys(%$assay))) {
      push @fields, $key;
    }
  }
  print join("\t", @fields) . "\n";
}

sub print_tries {
  my ($proj_id, $ab_url, $passed, $tries) = @_;
  my @fields = ($proj_id, $ab_url, $passed);
  foreach my $primary ("Immunoblot", "Immunofluorescence", "Override") {
    my $assay = $tries->{$primary};
    foreach my $key (sort(keys(%$assay))) {
      push @fields, $assay->{$key};
    }
  }
  print join("\t", @fields) . "\n";
}

sub init_validator {
  my ($dbh, $schema) = @_;
  my $v = new ModENCODE::Validator::Data::AntibodyQC_Standalone({ 'experiment' => new ModENCODE::Chado::Experiment() });
  $v->cached_samples->{'cell_lines'} = [];
  $v->cached_samples->{'stages'} = [];
  $v->cached_samples->{'strains'} = [];
  my $sth_line_or_strain = $dbh->prepare("SELECT cvt.name, a.value FROM $schema.attribute a
    INNER JOIN $schema.data_attribute da ON a.attribute_id = da.attribute_id
    INNER JOIN $schema.data d ON d.data_id = da.data_id
    INNER JOIN $schema.dbxref dbx ON d.dbxref_id = dbx.dbxref_id
    INNER JOIN $schema.db ON dbx.db_id = db.db_id
    INNER JOIN $schema.cvterm cvt ON d.type_id = cvt.cvterm_id
    WHERE a.heading = 'official name' AND db.url = 'http://wiki.modencode.org/project/index.php?title='");
  $sth_line_or_strain->execute();
  while (my $sample_row = $sth_line_or_strain->fetchrow_hashref()) {
    if ($sample_row->{"name"} =~ /cell_?line/i) {
      push (@{$v->cached_samples->{'cell_lines'}}, $sample_row->{"value"});
    } elsif ($sample_row->{"name"} =~ /strain/i) {
      push (@{$v->cached_samples->{'strains'}}, $sample_row->{"value"});
    }
  }
  $sth_line_or_strain->finish();
  my $sth_stage = $dbh->prepare("SELECT cvt.name, a.value FROM $schema.attribute a
    INNER JOIN $schema.data_attribute da ON a.attribute_id = da.attribute_id
    INNER JOIN $schema.data d ON d.data_id = da.data_id
    INNER JOIN $schema.dbxref dbx ON d.dbxref_id = dbx.dbxref_id
    INNER JOIN $schema.db ON dbx.db_id = db.db_id
    INNER JOIN $schema.cvterm cvt ON d.type_id = cvt.cvterm_id
    WHERE a.heading = 'developmental stage' AND db.url = 'http://wiki.modencode.org/project/index.php?title='");
  $sth_stage->execute();
  while (my $sample_row = $sth_stage->fetchrow_hashref()) {
    if ($sample_row->{"name"} =~ /stage/i) {
      push (@{$v->cached_samples->{'stages'}}, $sample_row->{"value"});
    }
  }
  $sth_stage->finish();
  return $v;
}

$dbh->disconnect();
