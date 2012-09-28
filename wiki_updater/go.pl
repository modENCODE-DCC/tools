#!/usr/bin/perl

use ModENCODE::WikiUpdate;

# Create the wiki-update object; this'll login to the wiki
my $updater = new ModENCODE::WikiUpdate({
    # TODO: You should change the login credentials to a user from your lab
    'username' => 'Validator_Robot', 
    'password' => 'pw',
    # TODO: smaug.aradine.com is the sandbox, wiki.modencode is the official wiki
    'wiki_path' => 'smaug.aradine.com/project',
    #'wiki_path' => 'wiki.modencode.org/project',
    'DEBUG' => 1,
    'IGNORE_ERRORS' => 0,
    'PROMPT_OVERWRITE' => 1,
  });

# Defaults for all antibodies
# TODO: Use the "GK" (for Gary Karpen) PI code, rather than "LS" (Lincoln Stein)
my $pi_code = "LS";
#my $pi_code = "GK";


#############################
#       FULL EXAMPLE        #
#############################
print STDERR "-------Loading fully populated antibody example------\n";
# Specify the name of the wiki page, the full title of the wiki page will be Ab:$wiki_name:$pi_code:1
my $antibody_name = "AntibodyName";
# Define the antibody you are going to load (this one has all fields populated)
my $antibody = new ModENCODE::WikiUpdate::Antibody({
    'official_name' => $antibody_name,
    'short_name' => 'Short Name',
    'target_name' => 'TargetName',
    'target_gene_product' => 'fly_genes:Blimp-1',
    'species_target' => 'C. elegans',
    'species_host' => 'Rabbit',
    'antigenic_sequence' => 'GATTACA',
    'purified' => 'None-Control',
    'clonalness' => 'None-Control',
    'company' => 'Other',
    'catalog_number' => 'CatalogNumber001',
    'lot_number' => '23',
    'reference' => 'Ref',
    'contributing_lab' => 'Stein',
    'short_description' => 'Short description',
    'description' => 'Long description',
    'notes' => 'Some notes',
    # Quality control information; with all types filled in
    'quality_control' => new ModENCODE::WikiUpdate::AntibodyQC({
        'ip' => { 'worm' => 'VERY GOOD', 'fly' => 'OK', 'human' => 'untested', 'notes' => "Some notes" },
        'western' => { 'worm' => 'VERY GOOD', 'fly' => 'OK', 'human' => 'untested', 'notes' => '' },
        'chip_qpcr' => { 'worm' => 'VERY GOOD', 'fly' => 'OK', 'human' => 'untested', 'notes' => '' },
        'if' => { 'worm' => 'VERY GOOD', 'fly' => 'OK', 'human' => 'untested', 'notes' => '' },
        'other' => { 'worm' => 'VERY GOOD', 'fly' => 'OK', 'human' => 'untested', 'notes' => '' },
        # Note that "overall" uses "incomplete" rather than "untested"
        'overall' => { 'worm' => 'VERY GOOD', 'fly' => 'OK', 'human' => 'incomplete', 'notes' => '' },
      })
  });
my $permalink = $updater->update(
  $antibody_name,
  $pi_code,
  $antibody
);
print STDERR "Got $permalink for $antibody_name.\n";

print STDERR "-------Loaded fully populated antibody example-------\n";
print STDERR "Take a look at this example at http://" . $updater->get_wiki_path() . "/index.php/Ab:AntibodyName:LS:1\n";
print STDERR "Press Enter to continue or Ctrl-C to abort.\n";
<>;

#############################
#      MINIMAL EXAMPLE      #
#############################
print STDERR "-------Loading minimally populated antibody example--\n";
print STDERR "  (Disabling prompting for overwriting.)\n";
$updater->set_PROMPT_OVERWRITE(0);
my $antibody = new ModENCODE::WikiUpdate::Antibody({
    'official_name' => $antibody_name,
    'short_name' => 'Short Name',
    'target_name' => 'TargetName',
    'species_target' => 'C. elegans',
    'species_host' => 'Rabbit',
    'antigenic_sequence' => 'GATTACA',
    'purified' => 'None-Control',
    'clonalness' => 'None-Control',
    'company' => 'Other',
    'catalog_number' => 'CatalogNumber001',
    'reference' => 'Ref',
    'contributing_lab' => 'Stein',
    'short_description' => 'Short description',
    'description' => 'Long description',
    'notes' => 'Some notes',
    # Quality control information; all defaulting to untested
    'quality_control' => new ModENCODE::WikiUpdate::AntibodyQC({
      })
  });
$permalink = $updater->update(
  $antibody_name,
  $pi_code,
  $antibody
);
print STDERR "Got $permalink for $antibody_name.\n";

print STDERR "-------Loaded minimally populated antibody example---\n";
print STDERR "Take a look at this example at http://" . $updater->get_wiki_path() . "/index.php/Ab:AntibodyName:LS:1\n";
print STDERR "(Yep, just overwrote the same page.)\n";


