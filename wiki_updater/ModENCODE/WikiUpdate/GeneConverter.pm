package ModENCODE::WikiUpdate::GeneConverter;

use strict;

my $root_dir;
BEGIN {
  $root_dir = $0;
  $root_dir =~ s/[^\/]*$//;
  $root_dir = "./" unless $root_dir =~ /\//;
}

my %fly_genes;

sub get_fly_gene {
  my ($gene_id) = @_;
  if ($gene_id !~ /^FBgn/) {
    print STDERR "Don't know how to convert gene ID $gene_id into a gene name; not updating.\n";
    return $gene_id;
  }
  init_fly_genes() unless %fly_genes;

  if ($fly_genes{$gene_id}) {
    return $fly_genes{$gene_id};
  } else {
    print STDERR "Couldn't find gene for ID $gene_id, leaving unchanged.\n";
    return $gene_id;
  }
}

sub init_fly_genes {
  print STDERR "Initializing fly gene_name->id data structure.\n";
  my $obo_file = "$root_dir/ontologies/fly_genes.obo";
  open FH, $obo_file or die "Couldn't open $obo_file";

  my $current_gene_id;
  while (my $line = <FH>) {
    $current_gene_id = undef if ($line =~ /\[Term\]/);
    if ($line =~ /^id: FlyBase:FBgn/) {
      ($current_gene_id) = ($line =~ m/id: FlyBase:(.*)/);
    }
    if ($current_gene_id && $line =~ m/^name:/) {
      ($fly_genes{$current_gene_id}) = ($line =~ m/name:\s*(.*)/);
    }
  }
  close FH;
  print STDERR "Done.";
}

1;
