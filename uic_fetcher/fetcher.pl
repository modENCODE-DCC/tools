#!/usr/bin/perl

use URI;
use Socket;
use ModENCODE::Fetcher;
use strict;

sub respond {
  my @parts = @_;
  for (my $i = 0; $i < scalar(@parts); $i++) {
    my $part = $parts[$i];
    if ($part =~ /\n/) {
      $part =~ s/\n/\n  /g;
      $parts[$i] = "  $part";
    }
  }

  my $message = join("\t", @parts);
  print $message . "\n";
}

sub check_host_reachable {
  my ($host, $port) = @_;
  my $iaddr = inet_aton($host);
  my $paddr = sockaddr_in($port, $iaddr);
  my $res = socket(SOCK, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
  if (!$res) { 
    return "Couldn't open socket to $host:$port";
  }
  $res = connect(SOCK, $paddr);
  if (!$res) {
    return "Couldn't connect to $host:$port";
  }

  close(SOCK);

  return 0;
}

# <command> = $ARGV[0]
# read <address>
# read <command_id>

# Flow of calling app should be:
# if <command> was "upload"
#   if <response> is "okay" then
#     # Host is reachable
#     read <response>
#     if <response> is "started\t.*" then
#       <destination> = (<response> =~ /started\t(.*)/
#     else
#       # FAILURE
#       read "log"
#       read <log> while <log> =~ /^  /
#   else
#      # Have to fetch the URL to OICR
# elsif <command> was "check"
#   read <reponse>
#   if <response> is "failed" then
#     # FAILURE
#   elsif <response> is "done"
#     <done> = (<response> =~ /done\t(.*)/)
#     read <response>
#     <failed> = (<response> =~ /failed\t(.*)/)
#     read <response>
#     <destination> = (<response> =~ /destination\t(.*)/)
#     read <response>
#     <destination_size> = (<response> =~ /destination_size\t(.*)/)
#     read "log"
#     read <log> while <log> =~ /^  /
#     # If <done> is true, stop checking and deal with result
#     # If <failed> is true, then failure, else success
# elsif <command> was "cancel"
#   read <response>
#   if <response> is "failed" then
#     # FAILURE
#   elsif <response> is "done" then
#     <cancelled> = (<response> =~ /done\t(.*)/)


#my $command = <>;
my $command = $ARGV[0];

my $s = new IO::Select(\*STDIN);
my ($address, $command_id);
my ($ready) = $s->can_read(2);
if ($ready) { $address = <$ready>; chomp($address); } else { die "Timed out waiting for URI"; }
($ready) = $s->can_read(2);
if ($ready) { $command_id = <$ready>; chomp($command_id); } else { die "Timed out waiting for command_id"; }

print "Got address: $address\n";
print "Got command_id: $command_id\n";

my $uri = URI->new($address);

if ($command eq "upload") {
  my $res = check_host_reachable($uri->host, $uri->port);
  if ($res) {
    respond "failed", $res;
    exit;
  } else {
    respond("okay");
  }

  my $fetcher = ModENCODE::Fetcher->new($uri->scheme, $command_id);
  if (!$fetcher) {
    respond "failed", "Couldn't create fetcher for " . $uri->scheme;
  } else {
    # Daemonize fetch
    my $pid = fork();
    if ($pid) {
      # In parent; detach and exit
      $SIG{CHLD} = 'IGNORE';
      exit 0;
    } else {
      $fetcher->start_getting_url($uri->as_string);
      if ($fetcher->failed) {
        respond "failed", $fetcher->failed;
        respond "log";
        respond $fetcher->log;
      } else {
        respond "started", $fetcher->destination;
      }
    }
  }
} elsif ($command eq "check") {
  my $fetcher = ModENCODE::Fetcher->connect($uri->scheme, $command_id);
  if (!$fetcher) {
    respond "failed", "Couldn't connect to existing fetcher";
  } else {
    respond "done", $fetcher->done();
    respond "failed", $fetcher->failed();
    respond "destination", $fetcher->destination();
    respond "destination_size", $fetcher->destination_size();

    my $log = $fetcher->log();
    respond "log";
    respond $log;

    if ($fetcher->done) {
      $fetcher->finish();
    }
  }
} elsif ($command eq "cancel") {
  my $fetcher = ModENCODE::Fetcher->connect($uri->scheme, $command_id);
  if (!$fetcher) {
    respond "failed", "Couldn't connect to existing fetcher";
  } else {
    respond "done", $fetcher->cancel();
  }
} else {
  print STDERR "Valid commands are: upload, check, cancel\n";
  exit;
}
