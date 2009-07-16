#!/usr/bin/perl

use DBI;
use URI::Escape qw();
use strict;

my $dbh_modencode = DBI->connect("dbi:Pg:dbname=modencode_chado;host=heartbroken.lbl.gov", "db_public", "ir84#4nm", { AutoCommit => 1 }) or die "Couldn't get modENCODE database $!";
my $dbh_wiki = DBI->connect("dbi:mysql:database=modencode_wiki;host=localhost", "modencode", "modencode+++") or die "Couldn't get Wiki database $!";

$dbh_modencode->do("DROP SCHEMA IF EXISTS merged_tables CASCADE");
$dbh_modencode->do("CREATE SCHEMA merged_tables");
$dbh_modencode->do("SET search_path = merged_tables");
$dbh_modencode->do("SELECT everything.mkviewswithexptname(null, false)");


my $sth = $dbh_modencode->prepare("SELECT x_dbxref.accession FROM x_dbxref 
  INNER JOIN x_db ON x_dbxref.db_id = x_db.db_id
  LEFT JOIN x_protocol ON x_dbxref.dbxref_id = x_protocol.dbxref_id
  WHERE x_db.description = 'URL_mediawiki_expansion' OR x_protocol.dbxref_id IS NOT NULL
  GROUP BY x_dbxref.accession
  HAVING x_dbxref.accession != '__ignore'");

$sth->execute();
my @accessions;
while (my ($accession) = $sth->fetchrow_array()) {
  $accession =~ s|^\Qhttp://wiki.modencode.org/project/index.php?title=\E||g;
  $accession =~ s|&oldid=\d*\s*$||g;
  $accession = URI::Escape::uri_unescape($accession);
  push @accessions, $accession;
}
$sth->finish();

my $sth_user_id = $dbh_wiki->prepare("SELECT user_id FROM user WHERE user_name = ?");
$sth_user_id->execute('Anonymous');
my ($anonymous_user_id) = $sth_user_id->fetchrow_array();
$sth_user_id->execute('Validator Robot');
my ($robot_user_id) = $sth_user_id->fetchrow_array();
$sth_user_id->finish();

my $wl_sth = $dbh_wiki->prepare("DELETE FROM whitelist WHERE wl_user_id = ? AND wl_updated_by_user_id = ?");
$wl_sth->execute($anonymous_user_id, $robot_user_id);
$wl_sth->finish();

$wl_sth = $dbh_wiki->prepare("INSERT INTO whitelist
  (wl_user_id, wl_page_title, wl_allow_edit, wl_updated_by_user_id, wl_expires_on) 
  VALUES(?, ?, 0, ?, '')");

foreach my $accession (@accessions) {
  $wl_sth->execute($anonymous_user_id, $accession, $robot_user_id);
#  print "Whitelisting: $accession\n";
}
$wl_sth->finish();

$dbh_modencode->disconnect();
$dbh_wiki->disconnect();

