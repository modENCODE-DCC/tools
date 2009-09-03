#!/usr/bin/perl

use strict;

use DBI;
use DBD::Pg;
use Date::Format;
use IO::Handle;
use Term::ProgressBar;

my %conf = (
  "dbname" => "FB2009_07",
  "host" => "awol.lbl.gov",
  "username" => "db_public",
  "password" => "limecat",
);

autoflush STDERR 1;

my $connstr = "dbi:Pg:dbname=" . $conf{"dbname"}; 
$connstr .= ";host=" . $conf{"host"} if length($conf{"host"});
$connstr .= ";port=" . $conf{"port"} if length($conf{"port"});

my $db = DBI->connect($connstr, $conf{"username"}, $conf{"password"}) or die "Couldn't connect to database";

my $get_organism = $db->prepare("SELECT organism_id FROM organism WHERE genus = 'Drosophila' AND species = 'melanogaster'");
$get_organism->execute();
my ($organism_id) = $get_organism->fetchrow_array();

my $get_feature = $db->prepare("SELECT 
  f.name AS feature_name,
  f.uniquename AS feature_uniquename,
  s.name AS synonym,
  scvt.name AS synonym_type
  FROM feature f
  LEFT JOIN feature_synonym fs ON fs.feature_id = f.feature_id
  LEFT JOIN synonym s ON fs.synonym_id = s.synonym_id
  LEFT JOIN cvterm scvt ON s.type_id = scvt.cvterm_id
  WHERE f.feature_id = ?
  ");

my $get_genbank_accs = $db->prepare("SELECT accession FROM dbxref INNER JOIN db ON dbxref.db_id = db.db_id INNER JOIN feature_dbxref fdbx ON dbxref.dbxref_id = fdbx.dbxref_id WHERE feature_id = ? AND db.name = 'GB'");

my $get_genes = $db->prepare("SELECT f.feature_id FROM feature f 
  INNER JOIN cvterm cvt ON f.type_id = cvt.cvterm_id 
  INNER JOIN cv ON cvt.cv_id = cv.cv_id 
  WHERE 
    f.organism_id = ? AND 
    f.is_obsolete = false AND
    f.dbxref_id IS NOT NULL AND
    cvt.name = 'gene' AND 
    (cv.name = 'sequence' OR cv.name = 'SO')");


my $get_synonyms = $db->prepare("SELECT name FROM cvterm WHERE cvterm_id IN (SELECT DISTINCT type_id FROM synonym)");
$get_synonyms->execute();
my @synonyms;
while (my ($synonym) = $get_synonyms->fetchrow_array()) {
  push @synonyms, "synonymtypedef: $synonym \"$synonym\" EXACT";
}
my $synonym_txt = join("\n", @synonyms);

my $date = time2str("%d:%m:%Y %H:%M", time());

# BEGIN OUTPUT
print <<EOD
format-version: 1.2
date: $date
saved-by: yostinso
auto-generated-by: fly_genes.pl
$synonym_txt
default-namespace: fly_genes

EOD
;

print STDERR "Fetching genes...";
$get_genes->execute($organism_id);
print STDERR "Done.\n";

my $progbar = new Term::ProgressBar({'count' => $get_genes->rows, 'fh' => \*STDERR});
my $so_far = 0;

while (my ($feature_id) = $get_genes->fetchrow_array()) {
  $so_far++;
  $get_feature->execute($feature_id);
  my %gene = (
    'synonyms' => [],
    'accessions' => [],
  );
  while (my $row = $get_feature->fetchrow_hashref()) {
    foreach my $key (keys(%$row)) {
      $row->{$key} =~ s/\\/\\\\/g;
      $row->{$key} =~ s/"/\\"/g;
    }
    $gene{'feature_name'} = $row->{'feature_name'};
    $gene{'feature_uniquename'} = $row->{'feature_uniquename'};

    $gene{'feature_name'} =~ s/!/\\!/g;
    $gene{'feature_uniquename'} =~ s/!/\\!/g;
    $gene{'feature_uniquename'} =~ s/\s/_/g;

    if (!scalar(grep { $_->{'name'} eq $row->{'synonym'} && $_->{'type'} eq $row->{'synonym_type'} } @{$gene{'synonyms'}})) {
      push @{$gene{'synonyms'}}, { 'name' => $row->{'synonym'}, 'type' => $row->{'synonym_type'} };
    }

    $get_genbank_accs->execute($row->{'feature_id'});
    while (my ($accession) = $get_genbank_accs->fetchrow_array()) {
      if (!scalar(grep { $_ eq $accession } @{$gene{'accessions'}})) {
        push @{$gene{'accessions'}}, $accession;
      }
    }
  }

  # Print term stanzas
  print "[Term]\n";
  print "id: FlyBase:" . $gene{'feature_uniquename'} . "\n";
  print "name: " . $gene{'feature_name'} . "\n";
  print "namespace: fly_gene\n";
  print join("\n", map { "synonym: \"" . $_->{'name'} . "\" EXACT " . $_->{'type'} . " []" } @{$gene{'synonyms'}}) . "\n";
  print "\n";
  $progbar->update($so_far);
}
