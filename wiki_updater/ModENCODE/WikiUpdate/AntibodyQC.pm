package ModENCODE::WikiUpdate::AntibodyQC;

use strict;
use Class::Std;

my %ip                          :ATTR( :get<ip>,        :init_arg<ip>,          :default<{ 'fly', 'untested', 'worm', 'untested', 'human', 'untested', 'notes', ''}> );
my %western                     :ATTR( :get<western>,   :init_arg<western>,     :default<{ 'fly', 'untested', 'worm', 'untested', 'human', 'untested', 'notes', ''}> );
my %chip_qpcr                   :ATTR( :get<chip_qpcr>, :init_arg<chip_qpcr>,   :default<{ 'fly', 'untested', 'worm', 'untested', 'human', 'untested', 'notes', ''}> );
my %if                          :ATTR( :get<if>,        :init_arg<if>,          :default<{ 'fly', 'untested', 'worm', 'untested', 'human', 'untested', 'notes', ''}> );
my %other                       :ATTR( :get<other>,     :init_arg<other>,       :default<{ 'fly', 'untested', 'worm', 'untested', 'human', 'untested', 'notes', ''}> );
my %overall                     :ATTR( :get<overall>,   :init_arg<overall>,     :default<{ 'fly', 'incomplete', 'worm', 'incomplete', 'human', 'incomplete', 'notes', ''}> );

my @okay_keys = ( "fly", "worm", "human", "notes" );
my @okay_values = ( "VERY GOOD", "GOOD", "OK", "WEAK", "VERY WEAK", "BAD", "untested" );
my @okay_values_overall = ( "VERY GOOD", "GOOD", "OK", "WEAK", "VERY WEAK", "BAD", "incomplete" );
my @okay_types = ("ip", "western", "chip_qpcr", "if", "other", "overall");

sub START {
  my ($self, $ident, $args) = @_;
  foreach my $key (keys(%$args)) {
    if (!scalar(grep { $key eq $_ } @okay_types)) {
      die "$key is not a valid QC type; it must be one of \"" . join("\", \"", @okay_types) . "\"";
    }
  }
  $self->check_values();
}

sub check_values {
  my $self = shift;
  my $ident = ident $self;
  foreach my $qc ($ip{$ident}, $western{$ident}, $chip_qpcr{$ident}, $if{$ident}, $other{$ident}, $overall{$ident}) {
    die "There must be " . scalar(@okay_keys) . " keys for each QC category: \"" . join("\", \"", @okay_keys) . "\", but there are " . scalar(keys(%$qc)) unless scalar(keys(%$qc)) == scalar(@okay_keys);
    foreach my $key (keys(%$qc)) {
      die "$key is not a valid QC key; it must be one of \"" . join("\", \"", @okay_keys) . "\"" unless scalar(grep { $key eq $_ } @okay_keys);
      next if $key eq "notes";
      my $value = $qc->{$key};
      if ($qc == $overall{$ident}) {
        die "$value is not a valid QC value; it must be one of \"" . join("\", \"", @okay_values_overall) . "\"" unless scalar(grep { $value eq $_ } @okay_values_overall);
      } else {
        die "$value is not a valid QC value; it must be one of \"" . join("\", \"", @okay_values) . "\"" unless scalar(grep { $value eq $_ } @okay_values);
      }
    }
  }
}

sub set_ip {
  my ($self, $new) = @_;
  $ip{ident $self} = $new;
  $self->check_values();
}

sub set_western {
  my ($self, $new) = @_;
  $western{ident $self} = $new;
  $self->check_values();
}

sub set_chip_qpcr {
  my ($self, $new) = @_;
  $chip_qpcr{ident $self} = $new;
  $self->check_values();
}

sub set_if {
  my ($self, $new) = @_;
  $if{ident $self} = $new;
  $self->check_values();
}

sub set_other {
  my ($self, $new) = @_;
  $other{ident $self} = $new;
  $self->check_values();
}

sub set_overall {
  my ($self, $new) = @_;
  $overall{ident $self} = $new;
  $self->check_values();
}

1;

