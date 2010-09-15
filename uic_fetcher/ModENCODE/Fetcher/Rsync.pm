package ModENCODE::Fetcher::Rsync;
use URI;
use base ModENCODE::Fetcher;

sub _get_uri {
  my ($self, $uri) = @_;
  print STDERR "WGETTING $uri\n";
}


1;
