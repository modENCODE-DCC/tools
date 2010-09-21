#!/usr/bin/perl

BEGIN {
  my $root_dir = $0;
  $root_dir =~ s/[^\/]*$//;
  push @INC, $root_dir;
}
use URI;
use Socket;
use ModENCODE::Fetcher;
use POSIX qw();
use File::Path qw();
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
# elsif <command> was "exists"
#   read <response>
#   if <response> is "failed" then
#     # FAILURE
#   else
#     <size> = (<response> =~ /exists\t(.*)/)
#     if <size> is "no" then
#       # it doesn't exist
#     else
#       <size> is the size of the file


my $command = $ARGV[0];

my $s = new IO::Select(\*STDIN);
my ($address, $command_id, $project_id);
my ($ready) = $s->can_read(2);
if ($ready) { $address = <$ready>; chomp($address); } else { die "Timed out waiting for URI"; }
$s->can_read(2);
if ($ready) { $command_id = <$ready>; chomp($command_id); } else { die "Timed out waiting for URI"; }
$s->can_read(2);
if ($ready) { $project_id = <$ready>; chomp($project_id); } else { die "Timed out waiting for URI"; }

my $uri = URI->new($address);
my $destination_root = "/tmp/data/$project_id/extracted";

if ($command eq "upload") {
  my $res = check_host_reachable($uri->host, $uri->port);
  if ($res) {
    respond "failed", $res;
    exit;
  } else {
    respond("okay");
  }

  if (!-d $destination_root) { File::Path::mkpath($destination_root); }
  my $fetcher = ModENCODE::Fetcher->new($uri, $command_id, $destination_root);
  if (!$fetcher) {
    respond "failed", "Couldn't create fetcher for " . $uri->scheme;
  } else {
    # Daemonize fetch
#    my $pid = fork();
#    if ($pid) {
      # In parent; detach and exit
#      $SIG{CHLD} = 'IGNORE';
#      exit 0;
#    } else {
      $fetcher->start_getting_url();
      if ($fetcher->failed) {
        respond "failed", $fetcher->failed;
        respond "log";
        respond $fetcher->log;
      } else {
        respond "started", $fetcher->destination;
      }
      sleep 1;
      system("disown", $$);
      POSIX::setsid();
      open STDIN, "/dev/null" or die "Can't reopen STDIN";
      open STDOUT, "/dev/null" or die "Can't reopen STDOUT";
      open STDERR, '>&STDOUT' or die "Can't reopen STDERR";
      exit;
#    }
  }
} elsif ($command eq "check") {
  my $fetcher = ModENCODE::Fetcher->connect($uri, $command_id, $destination_root);
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
  my $fetcher = ModENCODE::Fetcher->connect($uri, $command_id, $destination_root);
  if (!$fetcher) {
    respond "failed", "Couldn't connect to existing fetcher";
  } else {
    respond "done", $fetcher->cancel();
  }
} elsif ($command eq "exists") {
  my $fetcher = ModENCODE::Fetcher->new($uri, $command_id, $destination_root);
  respond "exists", $fetcher->exists();
} else {
  respond "failed", "bad command";
  exit;
}
