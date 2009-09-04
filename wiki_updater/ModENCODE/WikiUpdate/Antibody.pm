package ModENCODE::WikiUpdate::Antibody;

use strict;
use Class::Std;
use ModENCODE::WikiUpdate::AntibodyQC;
use ModENCODE::WikiUpdate::GeneConverter;

my %official_name               :ATTR( :name<official_name> );
my %short_name                  :ATTR( :name<short_name> );
my %target_name                 :ATTR( :name<target_name> );
my %target_gene_product         :ATTR( :get<target_gene_product>,       :init_arg<target_gene_product>, :default<undef> );
my %species_target              :ATTR( :get<species_target>,            :init_arg<species_target> );
my %species_host                :ATTR( :get<species_host>,              :init_arg<species_host> );
my %antigenic_sequence          :ATTR( :name<antigenic_sequence> );
my %purified                    :ATTR( :get<purified>,                  :init_arg<purified> );
my %clonalness                  :ATTR( :get<clonalness>,                :init_arg<clonalness> );
my %company                     :ATTR( :get<company>,                   :init_arg<company> );
my %catalog_number              :ATTR( :name<catalog_number> );
my %lot_number                  :ATTR( :name<lot_number>,               :default<undef> );
my %short_description           :ATTR( :name<short_description> );
my %reference                   :ATTR( :name<reference> );
my %contributing_lab            :ATTR( :get<contributing_lab>,          :init_arg<contributing_lab> );

my %description                 :ATTR( :name<description> );
my %notes                       :ATTR( :name<notes> );
my %quality_control             :ATTR( :get<quality_control>,           :init_arg<quality_control> );


sub START {
  my ($self, $ident, $args) = @_;
  # Required:
  $self->set_species_target($args->{'species_target'});
  $self->set_species_host($args->{'species_host'});
  $self->set_purified($args->{'purified'});
  $self->set_clonalness($args->{'clonalness'});
  $self->set_company($args->{'company'});
  $self->set_contributing_lab($args->{'contributing_lab'});
  $self->set_quality_control($args->{'quality_control'});

  # Optional
  $self->set_target_gene_product($args->{'target_gene_product'}) if ($args->{'target_gene_product'});
}

sub set_quality_control {
  my ($self, $new) = @_;
  die "Can't use a " . ref($new) . " as the quality_control, it must be a ModENCODE::WikiUpdate::AntibodyQC" unless $new->isa('ModENCODE::WikiUpdate::AntibodyQC');
  $quality_control{ident $self} = $new;
}

sub set_target_gene_product {
  my ($self, $new) = @_;
  die "target_gene_product must start with either \"worm_genes:\" or \"fly_genes:\"" unless $new =~ /^(worm_genes|fly_genes):/;
  my ($organism, $gene) = ($new =~ m/(worm_genes|fly_genes):(.*)$/);
  if ($gene =~ /^FBgn/i) {
    # Convert FBgn to real gene name
    $gene = ModENCODE::WikiUpdate::GeneConverter::get_fly_gene($gene);
    print STDERR "Converted $new to $organism:$gene\n";
    $new = "$organism:$gene";
  }
  $target_gene_product{ident $self} = $new;
}

sub set_species_target {
  my ($self, $new) = @_;
  my $options = [ "C. elegans", "D. melanogaster", "H. sapiens", "Other", "None-Control" ];
  die "species_target ($new) must be one of \"" . join('", "', @$options) . "\"" unless scalar(grep { $new eq $_ } @$options);
  $species_target{ident $self} = $new;
}

sub set_species_host {
  my ($self, $new) = @_;
  my $options = [ "Rabbit", "Mouse", "Rat", "Guinea Pig", "Goat", "Sheep", "None-Control" ];
  die "species_host ($new) must be one of \"" . join('", "', @$options) . "\"" unless scalar(grep { $new eq $_ } @$options);
  $species_host{ident $self} = $new;
}

sub set_purified {
  my ($self, $new) = @_;
  my $options = [ "Protein A/G", "Affinity", "Size", "Crude", "None-Control" ];
  die "purified ($new) must be one of \"" . join('", "', @$options) . "\"" unless scalar(grep { $new eq $_ } @$options);
  $purified{ident $self} = $new;
}

sub set_clonalness {
  my ($self, $new) = @_;
  my $options = [ "Polyclonal", "Monoclonal", "Unknown", "None-Control" ];
  die "clonalness ($new) must be one of \"" . join('", "', @$options) . "\"" unless scalar(grep { $new eq $_ } @$options);
  $clonalness{ident $self} = $new;
}

sub set_company {
  my ($self, $new) = @_;
  my $options = [ "Abcam", "Abcam ChIP grade", "Active Motif", "Aves Labs", "Covance", "DSHB", "LPBio", "LPBio ChIP grade", "Upstate", "Upstate ChIP grade", "Upstate-Millipore", "Millipore", "SDI", "Sigma", "Lab", "Other", "None-Control" ];
  die "company ($new) must be one of \"" . join('", "', @$options) . "\"" unless scalar(grep { $new eq $_ } @$options);
  $company{ident $self} = $new;
}

sub set_contributing_lab {
  my ($self, $new) = @_;
  my $options = [ 
    "Ahmad", "Ahringer", "Bellen", "Brenner", "Brent", "Celniker", "Cherbas", "Collart", "Dernburg", "Desai", "Elgin", "Gerstein", "Gingeras",
    "Gravely", "Green, Philip", "Green, Roland", "Gunsalus", "Hannon", "Henikoff", "Hoskins", "Hyman", "Karpen", "Kellis", "Kim, John", 
    "Kim Stuart", "Kuroda", "Lai", "Lieb", "Liu", "MacAlpine", "MacCoss", "Miller", "Orr-Weaver", "Park", "Perrimon", "Piano", "Pirrotta",
    "Posakony", "Rajewsky", "Reinke", "Ren", "Russell", "Segal", "Slack", "Snyder", "Strome", "Stein", "Waterston", "White, Kevin", 
    "White, Robert", "Other"
  ];
  die "contributing_lab ($new) must be one of \"" . join('", "', @$options) . "\"" unless scalar(grep { $new eq $_ } @$options);
  $contributing_lab{ident $self} = $new;
}

1;

