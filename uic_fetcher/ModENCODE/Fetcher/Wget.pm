package ModENCODE::Fetcher::Wget;
use URI;
use Switch;
use File::Basename qw();
use POSIX qw(setsid);
use base ModENCODE::Fetcher;
use strict;

sub _get_uri {
  my ($self, $uri) = @_;
  my $wget_bin = `which wget` || "/usr/bin/wget";
  chomp($wget_bin);
  setsid();
  my $ret = system($wget_bin, '--progress=dot', $uri, "-O", $self->{'destination'});
  my $err = $!;
  if ($ret >= 256) { $ret = $ret >> 8; }
  $ret = $self->_err_code_to_msg($ret);
  if ($ret && -e $self->{'destination'}) {
    # Failed to get, so delete the file created by -O
    unlink($self->{'destination'});
  }
  if ($ret) { print STDERR $err; }
  return $ret;
}

sub _err_code_to_msg {
  my ($self, $errcode) = @_;
  switch($errcode) {
    case 1 { $errcode = "Generic error code."; }
    case 2 { $errcode = "Parse error---for instance, when parsing command-line options, the .wgetrc or .netrc..."; }
    case 3 { $errcode = "File I/O error."; }
    case 4 { $errcode = "Network failure."; }
    case 5 { $errcode = "SSL verification failure."; }
    case 6 { $errcode = "Username/password authentication failure."; }
    case 7 { $errcode = "Protocol errors."; }
    case 8 { $errcode = "Server issued an error response."; }
  }
  return $errcode;
}

1;
