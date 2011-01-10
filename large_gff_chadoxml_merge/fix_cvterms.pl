#!/usr/bin/perl

use strict;
use Data::Dumper;

open(IN, "bad_cvterms_2934.chadoxml");
open(OUT, ">no_cvterms_2934.chadoxml");

my $collected_lines = "";
my $collecting = 0;
my @cvterms;
print "Collecting terms.\n";
while (my $line = <IN>) {
  if (!$collecting) {
    ($collecting) = ($line =~ m/<cvterm id="([^"]*)"/);
  }
  if ($collecting) {
    $collected_lines .= $line;
    if ($line =~ /<\/cvterm>/) {
      my ($term) = ($collected_lines =~ m/<name>([^<]*)</m);
      my ($id, $dbxref) = ($collected_lines =~ m/<cvterm id="([^"]*)"(?:.*<dbxref_id>([^<]*)<)?/s);
      push @cvterms, { 'id' => $id, 'dbxref' => $dbxref, 'term' => $term, 'lines' => $collected_lines };
      $collecting = 0;
      $collected_lines = "";
      next;
    }
  }
  if (!$collecting) {
    print OUT $line;
  }
}
print "Done.\n";

# Hardcoded missing terms
push @cvterms, { 'id' => 'cvtermz_001', 'dbxref' => 'n/a', 'term' => 'part_of', 'lines' => 
  '                <cvterm id="cvtermz_001">
                  <name>part_of</name>
                  <definition></definition>
                  <is_obsolete>0</is_obsolete>
                  <cv_id>cv_6</cv_id>
                  <dbxref_id>
                    <dbxref>
                      <accession>part_of</accession>
                      <version></version>
                      <db_id>db_62</db_id>
                    </dbxref>
                  </dbxref_id>
                </cvterm>
'};
push @cvterms, { 'id' => 'cvtermz_002', 'dbxref' => 'n/a', 'term' => 'CDS', 'lines' => 
  '                <cvterm id="cvtermz_002">
                  <name>CDS</name>
                  <definition></definition>
                  <is_obsolete>0</is_obsolete>
                  <cv_id>cv_6</cv_id>
                  <dbxref_id>
                    <dbxref>
                      <accession>0000316</accession>
                      <version></version>
                      <db_id>db_62</db_id>
                    </dbxref>
                  </dbxref_id>
                </cvterm>
'};
push @cvterms, { 'id' => 'cvtermz_003', 'dbxref' => 'n/a', 'term' => 'exon', 'lines' => 
  '                <cvterm id="cvtermz_003">
                  <name>exon</name>
                  <definition></definition>
                  <is_obsolete>0</is_obsolete>
                  <cv_id>cv_6</cv_id>
                  <dbxref_id>
                    <dbxref>
                      <accession>0000147</accession>
                      <version></version>
                      <db_id>db_62</db_id>
                    </dbxref>
                  </dbxref_id>
                </cvterm>
'};
push @cvterms, { 'id' => 'cvtermz_004', 'dbxref' => 'n/a', 'term' => 'transcription_end_site', 'lines' => 
  '                <cvterm id="cvtermz_004">
                  <name>transcription_end_site</name>
                  <definition></definition>
                  <is_obsolete>0</is_obsolete>
                  <cv_id>cv_6</cv_id>
                  <dbxref_id>
                    <dbxref>
                      <accession>0000616</accession>
                      <version></version>
                      <db_id>db_62</db_id>
                    </dbxref>
                  </dbxref_id>
                </cvterm>
'};
push @cvterms, { 'id' => 'cvtermz_005', 'dbxref' => 'n/a', 'term' => 'TSS', 'lines' => 
  '                <cvterm id="cvtermz_005">
                  <name>TSS</name>
                  <definition></definition>
                  <is_obsolete>0</is_obsolete>
                  <cv_id>cv_6</cv_id>
                  <dbxref_id>
                    <dbxref>
                      <accession>0000315</accession>
                      <version></version>
                      <db_id>db_62</db_id>
                    </dbxref>
                  </dbxref_id>
                </cvterm>
'};
push @cvterms, { 'id' => 'cvtermz_006', 'dbxref' => 'n/a', 'term' => 'fp', 'lines' => 
'               <cvterm id="cvtermy_006">
                  <name>fp</name>
                  <definition></definition>
                  <is_obsolete>0</is_obsolete>
                  <cv_id>cv_7</cv_id>
                  <dbxref_id>
                    <dbxref>
                      <accession>fp</accession>
                      <version></version>
                      <db_id>db_57</db_id>
                    </dbxref>
                  </dbxref_id>
                </cvterm>
'};

my %seen;
my @unique_names = grep { !$seen{$_}++ } map { $_->{'term'} } @cvterms;

close OUT;
close IN;

open(IN, "no_cvterms_2934.chadoxml");
open(OUT, ">2934.chadoxml");

# Print through all dbxrefs
while (my $line = <IN>) {
  if ($line =~ /<organism/) {
    seek(IN, -1*length($line), 1);
    last;
  }
  print OUT $line;
}

# Print any CVTerms
my %mappings;
foreach my $name (@unique_names) {
  # Find a dbxref
  my ($term_w_dbxref) = grep { $_->{'term'} eq $name && $_->{'id'} !~ /cvtermx/ } @cvterms;
  if (!$term_w_dbxref) {
    # TODO: Generate a new DBXREF?
    die "Bad term: $name";
  } else {
    print "Good term: $name\n";
    print OUT $term_w_dbxref->{'lines'};
  }
  my @xterms = grep { $_->{'term'} eq $name && $_->{'id'} =~ /cvtermx/ } @cvterms;
  foreach my $xterm (@xterms) {
    $mappings{$xterm->{'id'}} = $term_w_dbxref->{'id'};
  }
}
while (my $line = <IN>) {
  my ($cvterm_id) = ($line =~ m/>(cvtermx[^<]*)</);
  if ($cvterm_id) {
    my $new_id = $mappings{$cvterm_id};
    die "No mapping for $cvterm_id" unless $new_id;
    $line =~ s/\Q$cvterm_id\E/$new_id/;
  }
  print OUT $line;
}

close IN;
