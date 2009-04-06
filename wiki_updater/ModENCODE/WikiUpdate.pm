package ModENCODE::WikiUpdate;


use strict;
use Class::Std;
use Date::Format;
use LWP::UserAgent;
use URI::Escape ();
use HTTP::Cookies;
use ModENCODE::WikiUpdate::Antibody;

my %DEBUG                       :ATTR( :name<DEBUG>, :default<1> );
my %IGNORE_ERRORS               :ATTR( :name<IGNORE_ERRORS>, :default<0> );
my %PROMPT_OVERWRITE            :ATTR( :name<PROMPT_OVERWRITE>, :default<1> );
my %cookies                     :ATTR;
my %client                      :ATTR;
my %username                    :ATTR( :init_arg<username>, :get<username>, :default<'Validator_Robot'> );
my %password                    :ATTR( :init_arg<password>, :get<password>, :default<'vdate_358'> );
my %wiki_path                   :ATTR( :init_arg<wiki_path>, :get<wiki_path>, :default<'wiki.modencode.org/project'> );

sub update {
  my ($self, $wiki_name, $pi_code, $antibody) = @_;
  die "Can't use a " . ref($antibody) . " as an antibody, it must be a ModENCODE::WikiUpdate::Antibody" unless $antibody->isa('ModENCODE::WikiUpdate::Antibody');

  $self->debug("Updating antibody \"" . $antibody->get_official_name() . "\" at wiki page Ab:$wiki_name:$pi_code:1.");

  my $request = new HTTP::Request(
    'GET',
    "http://" . $self->get_wiki_path() . "/index.php?title=Ab:$wiki_name:$pi_code:1"
  );
  $self->debug("Checking if page exists.");
  my $res = $self->get_client()->request($request);
  if ($res->content =~ m/<div class="noarticletext">/) {
    $self->debug("No page found, creating new article.");
    $self->make_new_article($wiki_name, $pi_code);
    $self->debug("Checking to make sure page got created.");
    my $res = $self->get_client()->request($request);
    if ($res->content =~ m/<div class="noarticletext">/) {
      die "Tried to create page, but was unable to"
    }
  } elsif ($self->get_PROMPT_OVERWRITE()) {
    $| = 1;
    print STDERR "Found existing page, overwrite it (Y/n)? ";
    $| = 0;
    my $input = <>;
    chomp($input);
    if ($input =~ /^n/i) {
      print STDERR "Returning without updating...\n";
      return;
    }
  }
  $self->debug("Page found, updating it.");

  my $content = $res->content();

  # Updates notes and description section
  if ($antibody->get_notes() && length($antibody->get_notes()) > 0) {
    $content = $self->update_section($content, $wiki_name, $pi_code, "Notes", $antibody->get_notes());
  }
  if ($antibody->get_description() && length($antibody->get_description()) > 0) {
    $content = $self->update_section($content, $wiki_name, $pi_code, "Description", $antibody->get_description());
  }

  # Update DBFields form
  $self->debug("Updating reagent form.");
  $content = $self->update_dbfields($wiki_name, $pi_code, $antibody);

  # Update quality control form
  $self->debug("Updating QC form.");
  if ($antibody->get_quality_control()) {
    $self->update_qc($wiki_name, $pi_code, $antibody->get_quality_control());
  }
}

sub update_qc {
  my ($self, $wiki_name, $pi_code, $qc) = @_;
  my $title = 'Ab:' . $wiki_name . ':' . $pi_code . ':1';

  my @form_data = (
    [ 'IP-worm',       $qc->get_ip()->{'worm'} ],
    [ 'IP-fly',        $qc->get_ip()->{'fly'} ],
    [ 'IP-human',      $qc->get_ip()->{'human'} ],
    [ 'IP-notes',      $qc->get_ip()->{'notes'} ],

    [ 'WB-worm',       $qc->get_western()->{'worm'} ],
    [ 'WB-fly',        $qc->get_western()->{'fly'} ],
    [ 'WB-human',      $qc->get_western()->{'human'} ],
    [ 'WB-notes',      $qc->get_western()->{'notes'} ],

    [ 'ChIP-worm',     $qc->get_chip_qpcr()->{'worm'} ],
    [ 'ChIP-fly',      $qc->get_chip_qpcr()->{'fly'} ],
    [ 'ChIP-human',    $qc->get_chip_qpcr()->{'human'} ],
    [ 'ChIP-notes',    $qc->get_chip_qpcr()->{'notes'} ],

    [ 'IF-worm',       $qc->get_if()->{'worm'} ],
    [ 'IF-fly',        $qc->get_if()->{'fly'} ],
    [ 'IF-human',      $qc->get_if()->{'human'} ],
    [ 'IF-notes',      $qc->get_if()->{'notes'} ],

    [ 'Other-worm',    $qc->get_other()->{'worm'} ],
    [ 'Other-fly',     $qc->get_other()->{'fly'} ],
    [ 'Other-human',   $qc->get_other()->{'human'} ],
    [ 'Other-notes',   $qc->get_other()->{'notes'} ],

    [ 'Overall-worm',  $qc->get_overall()->{'worm'} ],
    [ 'Overall-fly',   $qc->get_overall()->{'fly'} ],
    [ 'Overall-human', $qc->get_overall()->{'human'} ],
    [ 'Overall-notes', $qc->get_overall()->{'notes'} ],
  );

  @form_data = map { 
    [ "modENCODE_dbfields[" . $_->[0] . "]", $_->[1] ]
  } @form_data;
  push @form_data, [ 'name_prefix', 'QC' ];

  my $headers = new HTTP::Headers();
  $headers->header('Content-Type' => 'application/x-www-form-urlencoded');
  my $request = new HTTP::Request(
    'POST',
    "http://" . $self->get_wiki_path() . "/index.php?title=$title&action=purge",
    $headers,
    join("&",
      map({ URI::Escape::uri_escape($_->[0]) . "=" . URI::Escape::uri_escape($_->[1])} @form_data)
    )
  );
  my $res = $self->get_client()->request($request);
  my $content = $res->content();
}


sub update_dbfields {
  my ($self, $wiki_name, $pi_code, $antibody) = @_;
  my $title = 'Ab:' . $wiki_name . ':' . $pi_code . ':1';

  my %mapping = (
     'official name'     => 'official_name',
     'aliases'           => 'short_name',
     'target name'       => 'target_name',
     'target id'         => 'target_gene_product',
     'species'           => 'species_target',
     'host'              => 'species_host',
     'antigen'           => 'antigenic_sequence',
     'purified'          => 'purified',
     'clonal'            => 'clonalness',
     'company'           => 'company',
     'catalog'           => 'catalog_number',
     'lot'               => 'lot_number',
     'short description' => 'short_description',
     'reference'         => 'reference',
     'lab'               => 'contributing_lab'
   );

  my @form_data = (
    [ 'official name'     => $antibody->get_official_name() ],
    [ 'aliases'           => $antibody->get_short_name() ],
    [ 'target name'       => $antibody->get_target_name() ],
    [ 'target id'         => $antibody->get_target_gene_product() ],
    [ 'species'           => $antibody->get_species_target() ],
    [ 'host'              => $antibody->get_species_host() ],
    [ 'antigen'           => $antibody->get_antigenic_sequence() ],
    [ 'purified'          => $antibody->get_purified() ],
    [ 'clonal'            => $antibody->get_clonalness() ],
    [ 'company'           => $antibody->get_company() ],
    [ 'catalog'           => $antibody->get_catalog_number() ],
    [ 'lot'               => $antibody->get_lot_number() ],
    [ 'short description' => $antibody->get_short_description() ],
    [ 'reference'         => $antibody->get_reference() ],
    [ 'lab'               => $antibody->get_contributing_lab() ]
  );
  @form_data = map { 
    [ "modENCODE_dbfields[" . $_->[0] . "]", $_->[1] ]
  } @form_data;

  my $headers = new HTTP::Headers();
  $headers->header('Content-Type' => 'application/x-www-form-urlencoded');
  my $request = new HTTP::Request(
    'POST',
    "http://" . $self->get_wiki_path() . "/index.php?title=$title&action=purge",
    $headers,
    join("&",
      map({ URI::Escape::uri_escape($_->[0]) . "=" . URI::Escape::uri_escape($_->[1])} @form_data)
    )
  );
  my $res = $self->get_client()->request($request);
  my $content = $res->content();
  my (@missing) = ($content =~ m/<div[^>]*id="([^"]*)_missing"[^>]*>required field missing</g);
  if (scalar(@missing)) {
    @missing = map { ($mapping{$_} ? $mapping{$_} : $_) } @missing;
    $self->error("You are missing the field(s): " . join(", ", @missing) . ".");
  }
  my (@missing) = ($content =~ m/<div[^>]*id="([^"]*)_missing"[^>]*>invalid controlled vocabulary term\(s\): ([^<]*)</g);
  if (scalar(@missing)) {
    my @new_missing;
    for (my $i = 0; $i < scalar(@missing); $i += 2) {
      push @new_missing, [ $missing[$i], $missing[$i+1] ];
    }
    @missing = map { ($mapping{$_->[0]} ? $mapping{$_->[0]} : $_->[0]) . " (" . $_->[1] . ")" } @new_missing;

    $self->error("You have invalid terms in the controlled vocabulary field(s): " . join(", ", @missing) . ".");
  }
  return $content;
}


sub update_section {
  my ($self, $content, $wiki_name, $pi_code, $section_name, $value) = @_;
  my $title = 'Ab:' . $wiki_name . ':' . $pi_code . ':1';
  my ($section_num) = ($content =~ m/(<a[^>]*title="Edit section: $section_name".*?>)/);
  ($section_num) = ($section_num =~ m/href="[^"]*section=(\d*)"/);
  die "Coulnd't find section $section_name" unless $section_num;
  $self->debug("Section $section_name is number $section_num.");
  my $request = new HTTP::Request(
    'GET',
    "http://" . $self->get_wiki_path() . "/index.php?title=$title&action=edit&section=$section_num"
  );
  my $res = $self->get_client()->request($request);
  my $content = $res->content();
  my ($editTime) = ($content =~ m/(<input[^>]*name="wpEdittime".*?>)/);
  my ($editTime) = ($editTime =~ m/value="([^"]*)"/);
  my ($startTime) = ($content =~ m/(<input[^>]*name="wpStarttime".*?>)/);
  my ($startTime) = ($startTime =~ m/value="([^"]*)"/);
  my ($editToken) = ($content =~ m/(<input[^>]*name="wpEditToken".*?>)/);
  my ($editToken) = ($editToken =~ m/value="([^"]*)"/);
  my ($summaryToken) = ($content =~ m/(<input[^>]*name="wpAutoSummary".*?>)/);
  my ($summaryToken) = ($summaryToken =~ m/value="([^"]*)"/);
  my $headers = new HTTP::Headers();
  $headers->header('Content-Type' => 'application/x-www-form-urlencoded');
  my $request = new HTTP::Request(
    'POST',
    "http://" . $self->get_wiki_path() . "/index.php?title=$title&action=submit",
    $headers,
    join("&",
      map({ URI::Escape::uri_escape($_->[0]) . "=" . URI::Escape::uri_escape($_->[1])}
        [ 'wpSection', $section_num ],
        [ 'wpStarttime', $startTime ],
        [ 'wpEdittime', $editTime ],
        [ 'wpScrolltop', '' ],
        [ 'wpTextbox1', "== $section_name ==\n" . $value . "\n<br/><br/>\n" ],
        [ 'wpSummary', 'Update section from WikiUpdate perl module.' ],
        [ 'wpSave', 'Save page' ],
        [ 'wpEditToken', $editToken ],
        [ 'wpAutoSummary', $summaryToken ]
      )
    )
  );
  my $res = $self->get_client()->request($request);
  return $res->content();
}

sub make_new_article {
  my ($self, $wiki_name, $pi_code) = @_;
  my $headers = new HTTP::Headers();
  $headers->header('Content-Type' => 'application/x-www-form-urlencoded');
  my $request = new HTTP::Request(
    'POST',
    "http://" . $self->get_wiki_path() . "/index.php",
    $headers,
    join("&",
      map({ URI::Escape::uri_escape($_->[0]) . "=" . URI::Escape::uri_escape($_->[1])}
        [ 'classifier', 'Ab' ],
        [ 'action', 'create' ],
        [ 'preload', 'Template:Reagent:Antibody:Blank' ],
        [ 'editintro', '' ],
        [ 'enforce_nomenclature', '1' ],
        [ 'title', 'Ab:' . $wiki_name . ':' . $pi_code . ':1'],
        [ 'lab', $pi_code ],
        [ 'version', '1' ],
        [ 'create', 'Go' ]
      )
    )
  );
  my $res = $self->get_client()->request($request);
}




sub BUILD {
  my ($self, $ident, $args) = @_;
  $client{$ident} = new LWP::UserAgent();
  push @{ $client{$ident}->requests_redirectable }, 'POST';
  $cookies{$ident} = new HTTP::Cookies();
  $client{$ident}->cookie_jar($cookies{ident $self});
}

sub START {
  my ($self, $ident, $args) = @_;

  my $headers = new HTTP::Headers();
  $headers->header('Content-Type' => 'application/x-www-form-urlencoded');
  # Log in and get a cookie
  my $request = new HTTP::Request(
    'POST',
    "http://" . $self->get_wiki_path() . "/index.php?title=Special:Userlogin&action=submitlogin&type=login",
    $headers,
    join("&",
      map({ URI::Escape::uri_escape($_->[0]) . "=" . URI::Escape::uri_escape($_->[1])}
        [ 'wpName', $self->get_username ],
        [ 'wpPassword', $self->get_password ],
        [ 'wpLoginattempt', 'Log+in' ]
      )
    )
  );
  my $res = $self->get_client()->request($request);
  if (!$res->is_success) {
    die "Couldn't connect to wiki to login: " . $res->status_line;
  }
  my $logged_in = 0;
  $cookies{$ident}->scan( sub { my ($version, $key, $val, $path, $domain) = @_; $logged_in = 1 if $key eq "modencode_wikiUserName"; } );
  if (!$logged_in) {
    my ($message) = ($res->content =~ m/<h2>Login error:<\/h2>\s*(\w[^<]*?)\s*<\/div>/m);
    die "Couldn't login with provided credentials: \"$message\"" unless $logged_in;
  }
}

sub get_client : PRIVATE {
  my ($self) = shift;
  return $client{ident $self};
}

sub get_cookies : PRIVATE {
  my ($self) = shift;
  return $cookies{ident $self};
}

sub debug {
  my ($self, $str) = @_;
  print STDERR $str . "\n" if $self->get_DEBUG();
}
sub error {
  my ($self, $str) = @_;
  print STDERR $str . "\n";
  exit unless $self->get_IGNORE_ERRORS();
}

1;
