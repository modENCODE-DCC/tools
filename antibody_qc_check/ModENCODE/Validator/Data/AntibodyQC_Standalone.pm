package ModENCODE::Validator::Data::AntibodyQC_Standalone;

use strict;
use base qw( ModENCODE::Validator::Data::AntibodyQC );
use ModENCODE::ErrorHandler_QC;
use Class::Std;

my %data                        :ATTR( :get<data>,                      :default<[]> );
my %cached_samples              :ATTR( :default<{}> );
my %new_logger                  :ATTR( :default<undef> );

sub BUILD {
  my ($self, $ident, $args) = @_;
  $self->SUPER::BUILD();
  $new_logger{ident $self} = new ModENCODE::ErrorHandler_QC();
  ModENCODE::ErrorHandler::set_logger($new_logger{ident $self});
}

sub cache_used_samples {
  my ($self) = @_;
}

sub cached_samples {
  my $self = shift;
  return $cached_samples{ident $self};
}

sub clear_data {
  my $self = shift;
  $data{ident $self} = [];
  $self->rewind();
}

sub get_tries {
  my $self = shift;
  return $new_logger{ident $self}->get_tries();
}

1;
