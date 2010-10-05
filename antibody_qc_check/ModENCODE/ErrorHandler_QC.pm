package ModENCODE::ErrorHandler_QC;
use strict;
use base qw( ModENCODE::ErrorHandler );
use Class::Std;

my %tries    :ATTR( :get<tries>, :default<{}> );
my %state    :ATTR( :default<''> );

sub BUILD {
  my ($self, $ident, $args) = @_;
  $self->SUPER::BUILD();
  $self->reset();
}

sub _log_error {
  my ($self, $message, $level, $change_indent) = @_;
  if ($message eq "Checking antibody QC status.") {
    $self->reset();
  # WESTERN
  } elsif ($message eq "Looking for valid immunoblot/Western QC info.") {
    $state{ident $self} = 'immunoblot';
    $self->set_try("Immunoblot", "Immunoblot", 0);
  } elsif ($message eq "Found a successful immunoblot validation.") {
    $self->set_try("Immunoblot", "Immunoblot", 1);
  } elsif ($state{ident $self} eq 'immunoblot' && $message eq "Looking for valid Knockdown+RNAi secondary assay.") {
    $self->set_try("Immunoblot", "Secondary Knockdown+RNAi", 0);
  } elsif ($message eq "Antibody is valid (Western + RNAi Knockdown)!") {
    $self->set_try("Immunoblot", "Secondary Knockdown+RNAi", 1);
  } elsif ($state{ident $self} eq 'immunoblot' && $message eq "Looking for valid Knockdown+siRNA secondary assay.") {
    $self->set_try("Immunoblot", "Secondary Knockdown+siRNAi", 0);
  } elsif ($message eq "Antibody is valid (Western + siRNA Knockdown)!") {
    $self->set_try("Immunoblot", "Secondary Knockdown+siRNAi", 1);
  } elsif ($state{ident $self} eq 'immunoblot' && $message eq "Looking for valid Knockdown+mutant secondary assay.") {
    $self->set_try("Immunoblot", "Secondary Knockdown+mutant", 0);
  } elsif ($message eq "Antibody is valid (Western + Mutant Knockdown)!") {
    $self->set_try("Immunoblot", "Secondary Knockdown+mutant", 1);
  } elsif ($state{ident $self} eq 'immunoblot' && $message eq "Looking for valid IP+Mass Spec secondary assay.") {
    $self->set_try("Immunoblot", "Secondary IP+Mass Spec", 0);
  } elsif ($message eq "Antibody is valid (Western + IP+Mass Spec)!") {
    $self->set_try("Immunoblot", "Secondary IP+Mass Spec", 1);
  } elsif ($state{ident $self} eq 'immunoblot' && $message eq "Looking for valid IP+Multiple Antibodies secondary assay.") {
    $self->set_try("Immunoblot", "Secondary IP+Multiple Antibodies", 0);
  } elsif ($message eq "Antibody is valid (Western + IP+Multiple Antibodies)!") {
    $self->set_try("Immunoblot", "Secondary IP+Multiple Antibodies", 1);
  } elsif ($state{ident $self} eq 'immunoblot' && $message eq "Looking for valid IP+Epitope-Tagged Protein secondary assay.") {
    $self->set_try("Immunoblot", "Secondary IP+Epitope-Tagged Protein", 0);
  } elsif ($message eq "Antibody is valid (Western + IP+Eptitope-Tagged Protein)!") {
    $self->set_try("Immunoblot", "Secondary IP+Epitope-Tagged Protein", 1);
  # IF
  } elsif ($message eq "Looking for valid immunofluorescence QC info.") {
    $state{ident $self} = 'immunofluorescence';
    $self->set_try("Immunofluorescence", "Immunofluorescence", 0);
  } elsif ($message eq "Found a successful immunofluorescence validation.") {
    $self->set_try("Immunofluorescence", "Immunofluorescence", 1);
  } elsif ($state{ident $self} eq 'immunofluorescence' && $message eq "Looking for valid Knockdown+RNAi secondary assay.") {
    $self->set_try("Immunofluorescence", "Secondary Knockdown+RNAi", 0);
  } elsif ($message eq "Antibody is valid (Western + RNAi Knockdown)!") {
    $self->set_try("Immunofluorescence", "Secondary Knockdown+RNAi", 1);
  } elsif ($state{ident $self} eq 'immunofluorescence' && $message eq "Looking for valid Knockdown+siRNA secondary assay.") {
    $self->set_try("Immunofluorescence", "Secondary Knockdown+siRNAi", 0);
  } elsif ($message eq "Antibody is valid (Western + siRNA Knockdown)!") {
    $self->set_try("Immunofluorescence", "Secondary Knockdown+siRNAi", 1);
  } elsif ($state{ident $self} eq 'immunofluorescence' && $message eq "Looking for valid Knockdown+mutant secondary assay.") {
    $self->set_try("Immunofluorescence", "Secondary Knockdown+mutant", 0);
  } elsif ($message eq "Antibody is valid (Western + Mutant Knockdown)!") {
    $self->set_try("Immunofluorescence", "Secondary Knockdown+mutant", 1);
  # OVERRIDE
  } elsif ($message eq "Antibody marked known good, but no prior literature referenced.") {
    $self->set_try("Override", "No References", 1);
  } elsif ($message eq "Marking an antibody as good (by prior literature) even though it failed/doesn't have other validation.") {
    $self->set_try("Override", "Override", 1);
  }
}

sub set_try {
  my ($self, $primary, $secondary, $value) = @_;
  $tries{ident $self}->{$primary} = {} unless defined($tries{ident $self}->{$primary});
  $tries{ident $self}->{$primary}->{$secondary} = $value unless $tries{ident $self}->{$primary}->{$secondary}; # Don't change a 1 to a 0
}

sub reset {
  my $self = shift;
  $tries{ident $self} = {};
  $self->set_try("Immunoblot", "Immunoblot", 0);
  $self->set_try("Immunoblot", "Secondary Knockdown+RNAi", 0);
  $self->set_try("Immunoblot", "Secondary Knockdown+siRNAi", 0);
  $self->set_try("Immunoblot", "Secondary Knockdown+mutant", 0);
  $self->set_try("Immunoblot", "Secondary IP+Mass Spec", 0);
  $self->set_try("Immunoblot", "Secondary IP+Multiple Antibodies", 0);
  $self->set_try("Immunoblot", "Secondary IP+Epitope-Tagged Protein", 0);

  $self->set_try("Immunofluorescence", "Immunofluorescence", 0);
  $self->set_try("Immunofluorescence", "Secondary Knockdown+RNAi", 0);
  $self->set_try("Immunofluorescence", "Secondary Knockdown+siRNAi", 0);
  $self->set_try("Immunofluorescence", "Secondary Knockdown+mutant", 0);

  $self->set_try("Override", "Override", 0);
  $self->set_try("Override", "No References", 0);
}

1;
