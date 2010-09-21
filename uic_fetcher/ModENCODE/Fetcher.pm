package ModENCODE::Fetcher;
use URI;
use IPC::Open3;
use IO::Select;
use IO::Pipe;
use IO::File;
use File::Spec qw();
use File::Basename qw();
use POSIX qw(mkfifo);

use ModENCODE::Fetcher::Wget;
use ModENCODE::Fetcher::Rsync;

use strict;

sub new {
  my ($class, $uri, $command_id, $destination_root) = @_;
  my $scheme = $uri->scheme;
  my $url = $uri->as_string;
  $destination_root ||= ".";
  my $self = { 'log' => [], 'url' => $url };
  if ($scheme eq "http" || $scheme eq "https" || $scheme eq "ftp") {
    bless $self, 'ModENCODE::Fetcher::Wget';
  } elsif ($scheme eq "rsync") {
    bless $self, 'ModENCODE::Fetcher::Rsync';
  } else {
    return 0;
  }

  $self->{'destination'} = File::Spec->canonpath(File::Spec->catfile($destination_root, File::Basename::basename($uri->path)));
  $self->{'fifo_path_in'} = "/tmp/$command_id.in.fifo";
  $self->{'fifo_path_out'} = "/tmp/$command_id.out.fifo";

  return $self;
}

sub connect {
  my $self = new(@_);
  if ($self->_connect()) {
    return $self;
  } else {
    return 0;
  }
}

sub _connect {
  my $self = shift;
  if (!$self->{'sin'}) {
    if (-p $self->{'fifo_path_out'} && -p $self->{'fifo_path_in'}) {
      my $success = 1;
      $SIG{ALRM} = sub { $success = 0; };
      alarm(1); # In case the FIFO blocks because it isn't open on the other end
      $self->{'sout'} = new IO::File($self->{'fifo_path_out'}, '<') if $success;
      $self->{'sin'} = new IO::File($self->{'fifo_path_in'}, '>') if $success;
      $self->{'sin'}->autoflush(1) if $success;
      alarm(0);
      $SIG{ALRM} = 'DEFAULT';
      return $success;
    }
  }
  return 0;
}

sub log {
  my $self = shift;
  my $fh = $self->{'sin'};
  print $fh "log\n";
  $fh = $self->{'sout'};
  my $log = "";
  while (my $line = <$fh>) {
    last if $line =~ /^EOF$/;
    $log .= $line;
  }
  chomp($log);
  return $log;
}

sub failed {
  my $self = shift;
  my $fh = $self->{'sin'};
  print $fh "failed\n";
  $fh = $self->{'sout'};
  my $res = <$fh>;
  chomp($res);
  return $res;
}

sub cancel {
  my $self = shift;
  my $fh = $self->{'sin'};
  print $fh "cancel\n";
  $fh = $self->{'sout'};
  my $res = <$fh>;
  chomp($res);
  return $res;
}

sub done {
  my $self = shift;
  my $fh = $self->{'sin'};
  print $fh "done\n";
  $fh = $self->{'sout'};
  my $res = <$fh>;
  chomp($res);
  return $res;
}

sub destination {
  my $self = shift;
  return $self->{'destination'};
}

sub destination_size {
  my $self = shift;
  if (-e $self->{'destination'}) {
    return -s $self->{'destination'};
  } else {
    return -1;
  }
}

sub exists {
  my $self = shift;
  my $size = $self->destination_size;
  if ($size >= 0) {
    return $size;
  } else {
    return -1;
  }
}

sub DESTROY {
  my $self = shift;
  if ($self->{'ppid'}) {
    my $ppid = $self->{'ppid'};
    waitpid($ppid, 0) if $ppid;
    unlink($self->{'fifo_path_in'}) if (-e $self->{'fifo_path_in'});
    unlink($self->{'fifo_path_out'}) if (-e $self->{'fifo_path_out'});
  }
}

sub finish {
  my $self = shift;
  my $fh = $self->{'sin'};
  print $fh "finish\n";
  $fh = $self->{'sout'};
  my $res = <$fh>;
  chomp($res);
  return $res;
}

sub start_getting_url {
  my $self = shift;
  my $url = $self->{'url'};
  $self->{'log'} = [];
  $self->{'cancel'} = 0;
  $self->{'failed'} = 0;
  $self->{'done'} = 0;
  my $uri = URI->new($url);

  if (-e $self->{'fifo_path_in'}) {
  } else {
    mkfifo($self->{'fifo_path_in'}, 0700);
  }
  if (-e $self->{'fifo_path_out'}) {
  } else {
    mkfifo($self->{'fifo_path_out'}, 0700);
  }

  # Fork and return a pipe to the caller
  my $ppid = fork();
  if ($ppid) {
    # Controller (read from child's stdout, write to stdin)
    $self->_connect();
    $0 = "daemon - get $uri";
    $self->{'ppid'} = $ppid;

    return;
  } else {
    $0 = "fetcher - get $uri";
    # Fetcher/getter
    # Controller (read from child's stdout, write to stdin)
    $self->{'sout'} = new IO::File($self->{'fifo_path_out'}, '>');
    $self->{'sin'} = new IO::File($self->{'fifo_path_in'}, '<');
    $self->{'sout'}->autoflush(1);

    $self->start_getter($uri);
    exit;
  }
}

sub start_getter {
  my ($self, $uri) = @_;

  # Spawn off a subprocess here, so the fetch proper can be cancelled/killed
  my $pipe_sout = new IO::Pipe();
  my $pipe_serr = new IO::Pipe();
  my $pipe_sin = new IO::Pipe();


  my $ppipe_sout = $self->{'sout'};
  my $ppipe_sin = $self->{'sin'};

  my $pid = fork(); # Fork!
  if ($pid) {
    $pipe_sout->reader();
    $pipe_serr->reader();
    $pipe_sin->writer();
    my $s = new IO::Select($pipe_sout, $pipe_serr, $ppipe_sin);
    my $buf;

    while (1) {
      if (!$s->exists($pipe_sout) && !$s->exists($pipe_serr)) {
        # Done processing
        $self->{'done'} = 1;
      }
      if (!$s->exists($pipe_sout) && !$s->exists($pipe_serr) && !$s->exists($ppipe_sin)) {
        last;
      }
      my @ready = $s->can_read(1);
      foreach my $h (@ready) {
        $buf = <$h>;
        if (!$buf) {
          # EOF
          $s->remove($h);
          close $h;
        }
        if ($self->{'cancel'}) {
          kill -9, $pid;
          $self->{'done'} = 1;
          $self->{'failed'} = "cancelled";
        }
        if ($h == $pipe_sout || $h == $pipe_serr) {
          if ($buf =~ /^failed$/) {
            $buf = <$h>;
            chomp($buf);
            $self->{'failed'} = $buf;
          } else {
            push @{$self->{'log'}}, $buf;
          }
        } else {
          # Command from outside
          chomp($buf);
          if ($buf eq "cancel") {
            $self->{'cancel'} = 1;
            print $ppipe_sout "canceling" . "\n";
          } elsif ($buf eq "done") {
            print $ppipe_sout $self->{'done'} . "\n";
          } elsif ($buf eq "failed") {
            print $ppipe_sout $self->{'failed'} . "\n";
          } elsif ($buf eq "log") {
            my $log = join("", @{$self->{'log'}});
            print $ppipe_sout $log;
            print $ppipe_sout "\nEOF\n";
          } elsif ($buf eq "lastlog") {
            my $i = scalar(@{$self->{'log'}});
            print $ppipe_sout $self->{'log'}->[$i-1];
          } elsif ($buf eq "finish") {
            $s->remove($h);
            print $ppipe_sout "finishing" . "\n";
            last;
          } elsif ($buf) {
            # Unknown command, ignore it
            print $ppipe_sout "unknown command\n";
          } else {
            # Parent closed connection
            $s->remove($h);
          }
        }
      }
    }
    waitpid($pid, 0); # Clean up child
  } else {
    # In child
    $pipe_sout->writer();
    $pipe_serr->writer();
    $pipe_sin->reader();
    $pipe_sout->autoflush(1);
    open STDOUT, ">&", $pipe_sout;
    open STDERR, ">&", $pipe_serr;
    open STDIN, "<&", $pipe_sin;

    print "Getting URI $uri\n";
    my $ret = $self->_get_uri($uri);
    if ($ret) {
      print "failed\n";
      print $ret . "\n";
    } else {
      print "okay\n";
    }
  }
}

1;
