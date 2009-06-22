#!/usr/bin/perl

package Wiki::LoginResult;
use strict;
use Class::Std;
use SOAP::Lite;

# Attributes
my %result           :ATTR( :name<result> );
my %lgusername       :ATTR( :name<lgusername>,  :default<undef> );
my %lguserid         :ATTR( :name<lguserid>,    :default<undef> );
my %lgtoken          :ATTR( :name<lgtoken>,     :default<undef> );
my %wait             :ATTR( :name<wait>,        :default<undef> );
my %cookieprefix     :ATTR( :name<cookieprefix>,:default<undef> );
my %details          :ATTR( :name<details>,     :default<undef> );
my %sessionid        :ATTR( :name<sessionid>,   :default<undef> );

sub get_username {
  my ($self) = @_;
  return $self->get_lgusername();
}

sub get_userid {
  my ($self) = @_;
  return $self->get_lguserid();
}

sub get_token {
  my ($self) = @_;
  return $self->get_lgtoken();
}

sub is_logged_in {
  my ($self) = @_;
  return ($self->get_result() eq "Success");
}

sub to_string {
  my ($self) = @_;
  my $string = "'" . $self->get_lgusername() . "' is ";
  $string .= $self->is_logged_in() ? "logged in" : "not logged in";
  $string .= " with token '" . $self->get_lgtoken() . "'.";
  return $string;
}

sub get_soap_obj {
  my ($self) = @_;
  my $data = SOAP::Data->name('auth' =>
    SOAP::Data->value(
      SOAP::Data->name('result' => $self->get_result())->type('xsd:string'),
      SOAP::Data->name('lgusername' => $self->get_lgusername())->type('xsd:string'),
      SOAP::Data->name('lguserid' => $self->get_lguserid())->type('xsd:string'),
      SOAP::Data->name('lgtoken' => $self->get_lgtoken())->type('xsd:string'),
      SOAP::Data->name('wait' => $self->get_wait())->type('xsd:string'),
      SOAP::Data->name('cookieprefix' => $self->get_cookieprefix())->type('xsd:string'),
      SOAP::Data->name('details' => $self->get_details())->type('xsd:string'),
      SOAP::Data->name('sessionid' => $self->get_sessionid())->type('xsd:string')
    )->type('LoginResult')->uri('http://wiki.modencode.org/project/extensions/DBFields/namespaces/dbfields'));
  return $data;
}

#######################################
#######################################
############ WIKI HELPER ##############
#######################################
#######################################

package WikiHelper;
use strict;
use SOAP::Lite;
use Class::Std;
use HTML::Entities;

my %soap_client :ATTR( :name<soap_client>, :default<undef> );

sub BUILD {
  my ($self, $ident, $args) = @_;
  my $old_generate_stub = *SOAP::Schema::generate_stub;
  my $new_generate_stub = sub {
    my $stubtxt = $old_generate_stub->(@_);
    my $testexists = '# HACKY FIX TO MISSING "can(\'as_$typename\')"
    if (!($self->serializer->can($method))) {
    push @parameters, $param;
    next;
    }
    ';
    $stubtxt =~ s/# TODO - if can\('as_'.\$typename\) {\.\.\.}/$testexists/;
    return $stubtxt;
  };

  undef *SOAP::Schema::generate_stub;
  *SOAP::Schema::generate_stub = $new_generate_stub;
}

sub START {
  my ($self, $ident, $args) = @_;
  my $soap_client = SOAP::Lite->service("http://wiki.modencode.org/project/extensions/DBFields/DBFieldsService.wsdl");
  $soap_client->serializer->envprefix('SOAP-ENV');
  $soap_client->serializer->encprefix('SOAP-ENC');
  $soap_client->serializer->soapversion('1.1');

  $self->set_soap_client($soap_client);
}


sub getFormData {
  my ($self, $name) = @_;

  $name =~ s/_/ /g;

  my $soap_client = $self->get_soap_client();

  my $login = $soap_client->getLoginCookie('Validator_Robot', 'vdate_358', 'modencode_wiki');
  bless $login, 'HASH';
  $login = new Wiki::LoginResult($login);

  my $data = SOAP::Data->name('query' => \SOAP::Data->value(
      SOAP::Data->name('name' => HTML::Entities::encode($name))->type('xsd:string'),
      SOAP::Data->name('auth' => \$login->get_soap_obj())->type('LoginResult'),
    ))->type('FormDataQuery');
  my $res = $soap_client->getFormData($data);
  use Data::Dumper;
  if (!$res) {
    print STDERR "Unable to find wiki page for $name! Please check your IDF.\n";
    exit;
  }
  my $latest_revision = $res->{'latest_revision'};
  return $latest_revision;
}

#######################################
#######################################
############ MAIN  ####################
#######################################
#######################################

package main;
use strict;


if (!$ARGV[0]) {
  print STDERR "\nUsage:\n";
  print STDERR "  $0 idffile.idf\n\n";
  exit;
}

open FH, $ARGV[0] or die "Couldn't open " . $ARGV[0] . " for reading: $!";
my $idf;
{
  local $/ = undef;
  $idf = <FH>;
}
close FH;


my $wh = new WikiHelper();

my @lines = split(/([\r\n])/, $idf);

open FH, ">", ".".$ARGV[0] or die "Couldn't open backup file " . ".".$ARGV[0] . " for writing: $!";
print FH join('', @lines);
close FH;

# Update investigation title
for (my $j = 0; $j < scalar(@lines); $j++) {
  my $line = $lines[$j];
  my @fields = split(/(\t)/, $line);
  for (my $i = 0; $i < scalar(@fields); $i++) {
    my $field = $fields[$i];
    if ($i == 0 && $field =~ /Investigation\s*Title/i) {
      my ($prefix, $title, $suffix) = ($fields[$i+2] =~ m/^("?)(.*?)("?)$/);
      print "New submission/investigation title? [Press ENTER to keep \"$title\"] ";
      my $new_title = <STDIN>;
      chomp($new_title);
      $new_title = $title if ($new_title eq "");
      $fields[$i+2] = $prefix.$new_title.$suffix;
    }
  }
  $lines[$j] = join('', @fields);
}


# Update wiki oldids
my $update_all = 0;
for (my $j = 0; $j < scalar(@lines); $j++) {
  my $line = $lines[$j];
  my @fields = split(/(\t)/, $line);
  for (my $i = 0; $i < scalar(@fields); $i++) {
    my $field = $fields[$i];
    my $fullurl = 1;
    my ($prefix, $url, $page, $id, $suffix)  = ($field =~ m/^(.*)(http:\/\/.*)title=(.*)&oldid=(\d+)(.*)$/);
    if (!$page) {
      $fullurl = 0;
      $url = "http://wiki.modencode.org/project/index.php?";
      ($prefix, $page, $id, $suffix)  = ($field =~ m/^("?)(.*)&oldid=(\d+)(.*)$/);
    }

    if ($page && $id) {
      print "Checking protocol $page (revision $id)...\n";
      my $latest_revision = $wh->getFormData($page);
      if ($latest_revision > $id) {
        print "  There is a new version: $latest_revision.";
        if (!$update_all) {
         print " Update (Y/N/All) [Y]? ";
          my $yn = <STDIN>;
          if ($yn =~ /^n/i) {
            print "\n";
            next;
          } elsif ($yn =~ /^a/i) {
            $update_all = 1;
          }
        } else {
          print "\n";
        }
        
        if ($fullurl) {
          $fields[$i] = "$prefix${url}title=$page&oldid=$latest_revision$suffix";
        } else {
          $fields[$i] = "$prefix$page&oldid=$latest_revision$suffix";
        }
        print "  Updated...\n\n";
      } else {
        print "  This is the most up-to-date version.\n\n";
      }
    }
  }
  $lines[$j] = join('', @fields);
}

open FH, ">", $ARGV[0] or die "Couldn't open " . $ARGV[0] . " for writing: $!";
print FH join('', @lines);
close FH;
