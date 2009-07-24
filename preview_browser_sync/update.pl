#!/usr/bin/perl

use strict;
use lib '/srv/gbrowse/gbrowse/modencode_preview/lib';
use Bio::DB::SeqFeature::Store;
use File::Spec qw();
use File::Copy::Recursive qw();
use Data::Dumper;
use constant NEW_DATA_PATH => "/srv/gbrowse/gbrowse/modencode_preview/data/";
use constant NEW_CONF_PATH => "/srv/gbrowse/gbrowse/modencode_preview/conf/";

# MOVE FILES WHERE THEY BELONG #
my $this_project_id;
my ($prefix, $project_id, $suffix);
print "Moving files to " . NEW_DATA_PATH . "\n";
my $data_glob = File::Spec->catfile($ARGV[0], "*");
my @data_files = grep { !/\d+.conf$/ } glob($data_glob);
my $conf_glob = File::Spec->catfile($ARGV[0], "*.conf");
my @conf_files = grep { /\d+.conf$/ } glob($conf_glob);
foreach my $conf_file (@conf_files) {
  ($this_project_id) = ($conf_file =~ m/^.*?\/?(\d+).conf$/);
  my $new_conf_file = $conf_file;
  $new_conf_file =~ s/\Q${ARGV[0]}\E\/?//;
  $new_conf_file = File::Spec->catfile(NEW_CONF_PATH, "$this_project_id.conf");
  print "  Copying conf from $conf_file to $new_conf_file.\n";
  File::Copy::Recursive::rcopy($conf_file, $new_conf_file) or die "Couldn't copy: $!";
}
foreach my $data_file (@data_files) {
  my $new_data_file = $data_file;
  $new_data_file =~ s/\Q${ARGV[0]}\E\/?//;
  $new_data_file = File::Spec->catfile(NEW_DATA_PATH, $this_project_id, $new_data_file);
  $data_file = File::Spec->rel2abs($data_file);
  print "  Symlinking data from $data_file to $new_data_file.\n";
  mkdir(File::Spec->catfile(NEW_DATA_PATH, $this_project_id));
  unlink($new_data_file) if -e $new_data_file;
  symlink($data_file, $new_data_file) or die "Couldn't symlink: $!";
}

# CONFIG FILES #
print "\nUpdating DSN in config file:\n";
$conf_glob = File::Spec->catfile(NEW_CONF_PATH, "*.conf");
@conf_files = grep { /\d+.conf$/ } glob($conf_glob);
foreach my $conf_file (@conf_files) {
  open(FH, "<", $conf_file) or die "Couldn't open $conf_file for reading";
  my $conf_data;
  while (my $line = <FH>) {
    ($prefix, $project_id, $suffix) = ($line =~ /^(.*\s*-dsn\s+)\/.*\/(\d+)\/browser\/(.*)$/);
    if ($prefix) {
      my $new_path = File::Spec->catfile(NEW_DATA_PATH, $project_id, $suffix);
      print "  Updated: $line";
      $line = $prefix . $new_path . "\n";
      print "       to: $line";
    }
    $conf_data .= $line;
  }
  close FH;
  open(FH, ">", $conf_file) or die "Couldn't open $conf_file for writing";
  print FH $conf_data;
  close FH;
}

# WIGGLE FILES #
print "\nUpdating wiggle paths:\n";
my $db = Bio::DB::SeqFeature::Store->new(
  -adaptor => 'berkeleydb',
  -dsn     => File::Spec->catfile(NEW_DATA_PATH, $this_project_id, "db"),
  -dir     => File::Spec->catfile(NEW_DATA_PATH, $this_project_id, "db"),
  -write   => 1
);

my @wiggle_features = $db->features( -type => [ 'microarray_oligo', 'summary' ] );
foreach my $wiggle_feature (@wiggle_features) {
  ($prefix, $project_id, $suffix) = (
    $wiggle_feature->{'attributes'}->{'wigfile'}->[0] =~ m/^(.*\/(\d+)\/browser\/)(.*)$/
  );
  my ($wigfile) = $wiggle_feature->get_tag_values("wigfile");
  print "  $wigfile\n";
  unless ($prefix) {
    print "    Not updating...\n";
    next;
  }
  my $new_path = File::Spec->catfile(NEW_DATA_PATH, $project_id, $suffix);
  $wiggle_feature->remove_tag("wigfile");
  {
    # Hack to remove old attribute from a berkeleydb
    # Otherwise, doing a $db->search_attributes returns both old and new wigfile attrs
    my $attr_db = $db->index_db('attributes')
      or $db->throw("Couldn't find 'attributes' index file");

    my $key = "wigfile:${wigfile}";
    $db->update_or_delete(1, $attr_db, $key, $wiggle_feature->primary_id);
  }
  $wiggle_feature->add_tag_value("wigfile", $new_path);
  print "    Updating to: $new_path\n";
  $db->store($wiggle_feature) or die "Couldn't store wiggle to DB";
}
# Flush database
$db->_close_databases;

