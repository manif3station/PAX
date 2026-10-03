# Differential fixture: Web::Server pure/frontend helpers run identically under stock Perl and the PAX binary.
# Contract: print deterministic text only.
use strict; use warnings;
$| = 1; $SIG{PIPE} = "IGNORE";
use Socket;
use File::Temp qw(tempdir);
use Developer::Dashboard::Web::Server;
use Developer::Dashboard::Web::Server::Daemon;
my $P = 'Developer::Dashboard::Web::Server';
sub show { my ($label, @v) = @_; print "$label: ", join('|', map { defined $_ ? "<$_>" : 'undef' } @v), "\n"; }
sub fn { no strict 'refs'; return \&{"${P}::$_[0]"}; }

# Daemon accessors
for my $args ([], [host=>'h', port=>1], [host=>'h', port=>1, internal_host=>'ih', internal_port=>2]) {
    my $d = Developer::Dashboard::Web::Server::Daemon->new(@$args);
    show('daemon', $d->sockhost, $d->sockport, $d->internal_sockhost, $d->internal_sockport);
}

# SAN helpers
for my $n (undef, '', '  ', ' Foo.Example.COM ', '[::1]:7890', '[fe80::1]', 'host:7890', 'a:b', '::1', 'LOCALHOST:80', '10.0.0.1:99', '[x]:y', "\tz\n") {
    show('norm', fn('_normalize_ssl_subject_alt_name')->($n));
}
for my $n (undef, '', '*', '0.0.0.0', '::', '0:0:0:0:0:0:0:0', 'localhost', '127.0.0.1') {
    show('wild', fn('_ssl_subject_alt_name_is_wildcard')->($n));
}
for my $n (undef, '', '1.2.3.4', '1234.1.1.1', '1.2.3', '::1', 'fe80::1', 'host', '1.2.3.4.5', "1.2.3.4\n") {
    show('isip', fn('_ssl_subject_alt_name_is_ip')->($n));
}
show('san1', fn('_ssl_expected_subject_alt_names')->());
show('san2', fn('_ssl_expected_subject_alt_names')->(host => '0.0.0.0'));
show('san3', fn('_ssl_expected_subject_alt_names')->(host => 'Dev.Local:7890', hosts => ['dev.local', ' 10.1.1.1 ', '*', '[::2]:99', undef, '', 'LOCALHOST']));
show('san4', fn('_ssl_expected_subject_alt_names')->(hosts => 'notarray', host => '::'));
show('san5', scalar(() = fn('_ssl_expected_subject_alt_names')->(hosts => [])));

# TLS detection
for my $b (undef, '', "\x16", "\x15", 'G', "\x16\x03", 'A') { show('tls', fn('_socket_looks_like_tls')->($b)); }

# redirect response
for my $a ([], [host=>'h.example'], [target=>'/x?y=1'], [host=>'h:7890', target=>''], [host=>'', target=>undef], [host=>0, target=>0]) {
    my $r = fn('_http_redirect_response')->(@$a);
    $r =~ s/\r/<CR>/g; $r =~ s/\n/<LF>/g;
    show('redir', $r);
}

# https detection
my @envs = (undef, 'x', [], {}, { 'psgi.url_scheme' => 'https' }, { 'psgi.url_scheme' => 'HTTPS' }, { 'psgi.url_scheme' => 'http' },
  { 'psgi.url_scheme' => 'http', HTTP_X_FORWARDED_PROTO => 'https' }, { HTTP_X_FORWARDED_PROTO => 'HTTPS' }, { HTTP_X_FORWARDED_PROTO => 'http' },
  { 'psgi.url_scheme' => undef, HTTP_X_FORWARDED_PROTO => undef }, { HTTP_X_FORWARDED_PROTO => 'https, http' });
for my $e (@envs) { show('isHTTPS', fn('_request_is_https')->($e)); }

# ssl redirect response (needs $self, uses allowlist)
my $srv = bless { host => '0.0.0.0', ssl_subject_alt_names => ['dev.local'], ssl => 1 }, $P;
for my $e (
  { HTTP_HOST => 'localhost:7890', SCRIPT_NAME => '', PATH_INFO => '/a b', QUERY_STRING => 'q=1' },
  { HTTP_HOST => 'evil.com', SERVER_NAME => 'dev.local', SERVER_PORT => 7890, PATH_INFO => '/x' },
  { HTTP_HOST => 'dev.local:99', PATH_INFO => '/' },
  { SERVER_NAME => 'srv', SERVER_PORT => 443, PATH_INFO => '/p', QUERY_STRING => '' },
  { SERVER_PORT => '', PATH_INFO => '//evil' },
  { HTTP_HOST => '127.0.0.1:1', PATH_INFO => '@evil.com/' },
  { }, { SCRIPT_NAME => '/app', PATH_INFO => '/z', HTTP_HOST => '[::1]:80' },
) {
  my $r = $srv->_ssl_redirect_response($e);
  show('sslredir', $r->[0], @{$r->[1]}, @{$r->[2]});
}

# cert profile
my $dir = tempdir(CLEANUP => 1);
my $cnf = "$dir/c.cnf";
open my $fh, '>', $cnf or die; print {$fh} "[ req ]\nprompt = no\ndistinguished_name = dn\nx509_extensions = v3\n[ dn ]\nCN = localhost\n[ v3 ]\nsubjectAltName = \@alt\nbasicConstraints = critical,CA:FALSE\nkeyUsage = critical,digitalSignature,keyEncipherment\nextendedKeyUsage = serverAuth\n[ alt ]\nDNS.1 = localhost\nIP.1 = 127.0.0.1\nIP.2 = ::1\nDNS.2 = dev.local\n"; close $fh;
system("openssl req -new -x509 -days 2 -nodes -config $cnf -out $dir/good.crt -keyout $dir/good.key >/dev/null 2>&1");
open $fh, '>', "$dir/plain.cnf" or die; print {$fh} "[ req ]\nprompt = no\ndistinguished_name = dn\n[ dn ]\nCN = localhost\n"; close $fh;
system("openssl req -new -x509 -days 2 -nodes -config $dir/plain.cnf -out $dir/plain.crt -keyout $dir/plain.key >/dev/null 2>&1");
open $fh, '>', "$dir/junk.crt" or die; print {$fh} "garbage\n"; close $fh;
show('prof', fn('_ssl_cert_has_expected_profile')->(undef));
show('prof', fn('_ssl_cert_has_expected_profile')->(''));
show('prof', fn('_ssl_cert_has_expected_profile')->("$dir/missing"));
show('prof good', fn('_ssl_cert_has_expected_profile')->("$dir/good.crt"));
show('prof good dev', fn('_ssl_cert_has_expected_profile')->("$dir/good.crt", hosts => ['dev.local']));
show('prof good other', fn('_ssl_cert_has_expected_profile')->("$dir/good.crt", hosts => ['other.local']));
show('prof good ip', fn('_ssl_cert_has_expected_profile')->("$dir/good.crt", hosts => ['127.0.0.1', '::1']));
show('prof good ip2', fn('_ssl_cert_has_expected_profile')->("$dir/good.crt", hosts => ['10.9.9.9']));
show('prof plain', fn('_ssl_cert_has_expected_profile')->("$dir/plain.crt"));
my $ok = eval { fn('_ssl_cert_has_expected_profile')->("$dir/junk.crt"); 1 };
my $err = $@ // ''; $err =~ s/\Q$dir\E/DIR/g; $err =~ s/\s+/ /g; $err =~ s/ at \S+ line \d+\..*//;
show('prof junk', $ok ? 'lived' : 'died', substr($err, 0, 40));

# request head reading over socketpair
sub head_of {
    my ($data, $close) = @_;
    socketpair(my $a, my $b, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die;
    my $pid = fork();
    if (!$pid) { close $a; syswrite($b, $data) if length $data; close $b; exit 0 if $close; sleep 5; exit 0; }
    close $b;
    waitpid($pid,0) if $close;
    my $h = fn('_read_http_request_head')->($a);
    kill 9, $pid if !$close;
    waitpid($pid,0) if !$close;
    return $h;
}
sub vis { my $s = shift; $s =~ s/\r/<CR>/g; $s =~ s/\n/<LF>/g; return length($s) > 120 ? length($s).':'.substr($s,0,60).'...'.substr($s,-30) : $s; }
show('head', vis(head_of("GET / HTTP/1.1\r\nHost: x\r\n\r\nBODY", 1)));
show('head', vis(head_of("GET / HTTP/1.1\nHost: x\n\nBODY", 1)));
show('head', vis(head_of("GET / HTTP/1.1\r\nHost: x\r\n", 1)));
show('head', vis(head_of("", 1)));
show('head', vis(head_of("GET /" . ('a' x 20000) . " HTTP/1.1\r\nHost: x\r\n\r\n", 1)));
show('head', vis(head_of("A" x 30000, 1)));
show('head', vis(head_of("GET / HTTP/1.1\r\n\r\n\r\n\r\n", 1)));

# frontend client: plain HTTP redirect through socketpair
sub frontend {
    my ($data, $daemon, $srv_) = @_;
    socketpair(my $c, my $s, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die;
    my $pid = fork();
    if (!$pid) { close $s; syswrite($c, $data); shutdown($c, 1); local $/; my $r = <$c>; print STDOUT ''; my $o = defined $r ? $r : ''; open my $w, '>', "/dev/null"; exit 0; }
    close $c;
    my $ok = eval { $srv_->_handle_ssl_frontend_client(client => $s, daemon => $daemon); 1 };
    my $e = $@ // '';
    $e =~ s/ at \S+ line \d+\.?.*//s;
    shutdown($s, 1);
    waitpid($pid, 0);
    return ($ok ? 'ok' : "died:$e");
}
# read response directly: parent reads from own end after handler writes
sub frontend2 {
    my ($data, $daemon, $srv_) = @_;
    socketpair(my $c, my $s, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die;
    syswrite($c, $data) if length $data;
    shutdown($c, 1);
    my $ok = eval { $srv_->_handle_ssl_frontend_client(client => $s, daemon => $daemon); 1 };
    my $e = $@ // ''; $e =~ s/ at \S+ line \d+\.?.*//s;
    close $s;
    my $resp = ''; { local $/; my $r = <$c>; $resp = $r if defined $r; }
    return ($ok ? 'ok' : "died:$e", vis($resp));
}
my $d1 = Developer::Dashboard::Web::Server::Daemon->new(host => '127.0.0.1', port => 7890, internal_host => '127.0.0.1', internal_port => 1);
my $d2 = Developer::Dashboard::Web::Server::Daemon->new(host => '0.0.0.0', port => 443);
for my $req (
  "GET /a/b?c=1 HTTP/1.1\r\nHost: localhost:7890\r\n\r\n",
  "GET /a HTTP/1.1\r\nHost: evil.example.com\r\n\r\n",
  "GET /a HTTP/1.1\r\nHost: dev.local\r\n\r\n",
  "GET /a HTTP/1.1\r\nhost:   dev.local:99   \r\n\r\n",
  "GET /a HTTP/1.1\r\n\r\n",
  "GET \@evil.com/ HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n",
  "GET //evil.com HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n",
  "POST /p\\q HTTP/1.1\r\nHost: [::1]:7890\r\n\r\n",
  "garbage\r\n\r\n",
  "GET / HTTP/1.0\r\nHost: \r\n\r\n",
  "GET / HTTP/1.1\r\nHost: bad host\r\n\r\n",
) {
  for my $d ($d1, $d2) { show('frontend', frontend2($req, $d, $srv)); }
}
show('frontend empty', frontend2('', $d1, $srv));
{
  my $ok = eval { $srv->_handle_ssl_frontend_client(daemon => $d1); 1 }; my $e = $@; $e =~ s/ at .*//s; show('fe nocl', $ok ? 'ok' : $e);
  $ok = eval { $srv->_handle_ssl_frontend_client(client => \*STDIN); 1 }; $e = $@; $e =~ s/ at .*//s; show('fe nodm', $ok ? 'ok' : $e);
}

# TLS path: proxy through to a fake backend on an ephemeral port
{
  use IO::Socket::INET;
  my $lst = IO::Socket::INET->new(Listen => 5, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp', ReuseAddr => 1) or die;
  my $bport = $lst->sockport;
  my $bpid = fork();
  if (!$bpid) {
    my $c = $lst->accept; my $buf = '';
    while (sysread($c, my $chunk, 4096)) { $buf .= $chunk; last if length($buf) >= 20000; }
    syswrite($c, "ECHO:" . length($buf)); close $c; exit 0;
  }
  close $lst;
  my $dd = Developer::Dashboard::Web::Server::Daemon->new(host=>'127.0.0.1', port=>1, internal_host=>'127.0.0.1', internal_port=>$bport);
  socketpair(my $c, my $s, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die;
  my $payload = "\x16\x03\x01" . ('z' x 19997);
  my $wp = fork();
  if (!$wp) { close $s; syswrite($c, $payload); my $got = ''; while (sysread($c, my $x, 4096)) { $got .= $x; last if $got =~ /ECHO:\d+/ } print STDERR ''; exit($got eq 'ECHO:20000' ? 0 : 3); }
  close $c;
  my $ok = eval { $srv->_handle_ssl_frontend_client(client => $s, daemon => $dd); 1 };
  close $s;
  waitpid($wp, 0); my $st = $? >> 8;
  waitpid($bpid, 0);
  show('tls proxy', $ok ? 'ok' : 'died', $st);
  # backend unreachable
  my $dead = Developer::Dashboard::Web::Server::Daemon->new(host=>'127.0.0.1', port=>1, internal_host=>'127.0.0.1', internal_port=>1);
  socketpair(my $c2, my $s2, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die;
  syswrite($c2, "\x16abc");
  $ok = eval { $srv->_handle_ssl_frontend_client(client => $s2, daemon => $dead); 1 };
  my $e = $@; $e =~ s/: .*//s; show('tls dead', $ok ? 'ok' : $e);
}

# proxy streams directly
{
  socketpair(my $a1, my $a2, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die;
  socketpair(my $b1, my $b2, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die;
  syswrite($a1, "hello-from-client"); syswrite($b1, "hello-from-backend"); 
  close $a1; close $b1;
  my $r = eval { fn('_proxy_streams')->($a2, $b2) };
  show('proxy', $r, $@ ? 'died' : 'lived');
  my ($x, $y) = ('', '');
  sysread($a2, $x, 100); sysread($b2, $y, 100);
  show('proxied', $x, $y);
}

# signal helpers
{
  no strict 'refs';
  local $SIG{TERM} = 'IGNORE';
  my @log;
  my $sp = fork(); if (!$sp) { sleep 30; exit 0; }
  ${"${P}::SSL_BACKEND_PID"} = $sp;
  ${"${P}::SSL_SHUTDOWN_REQUESTED"} = 0;
  %{"${P}::SSL_PREVIOUS_SIGNAL"} = (TERM => sub { push @log, 'term-prev' }, INT => 'IGNORE', HUP => undef);
  show('term', fn('_ssl_term_handler')->(), "flag=" . ${"${P}::SSL_SHUTDOWN_REQUESTED"}, "log=@log", "reaped=" . (waitpid($sp, 1) == -1 ? 'already' : 'no'));
  ${"${P}::SSL_SHUTDOWN_REQUESTED"} = 0;
  show('int', fn('_ssl_int_handler')->(), "flag=" . ${"${P}::SSL_SHUTDOWN_REQUESTED"});
  ${"${P}::SSL_SHUTDOWN_REQUESTED"} = 0;
  show('hup', fn('_ssl_hup_handler')->(), "flag=" . ${"${P}::SSL_SHUTDOWN_REQUESTED"});
  ${"${P}::SSL_SHUTDOWN_REQUESTED"} = 0;
  show('handle', fn('_handle_ssl_signal')->('NOPE'), "flag=" . ${"${P}::SSL_SHUTDOWN_REQUESTED"});
  # run_previous
  show('prev undef', fn('_run_previous_signal')->(undef));
  show('prev code', fn('_run_previous_signal')->(sub { push @log, 'c'; 99 }), "@log");
  show('prev IGNORE', fn('_run_previous_signal')->('IGNORE'));
  show('prev name', fn('_run_previous_signal')->('main::handler'));
  show('prev empty', fn('_run_previous_signal')->(''));
  local $SIG{TERM} = sub { push @log, 'got-term' };
  show('prev DEFAULT', fn('_run_previous_signal')->('DEFAULT'), "@log");
  show('default term', fn('_signal_default_term')->(), "@log");
}

# run / listening_url
{
  no strict "refs";
  my $ssl = bless { ssl => 1 }, $P; my $plain = bless { ssl => 0 }, $P;
  my $dm = Developer::Dashboard::Web::Server::Daemon->new(host => 'h', port => 5);
  my $dn = Developer::Dashboard::Web::Server::Daemon->new();
  show('url', $ssl->listening_url($dm), $plain->listening_url($dm), $ssl->listening_url($dn), $plain->listening_url($dn));
  my @r = $plain->listening_url(undef); show('url undef', scalar(@r));
  my $r = $plain->listening_url(); show('url none', defined $r ? $r : 'undef');
  no warnings 'redefine';
  my @calls;
  local *{"${P}::start_daemon"} = sub { push @calls, 'start'; return $dm };
  local *{"${P}::serve_daemon"} = sub { push @calls, 'serve'; return 'served' };
  my $rv = $plain->run;
  show('run', $rv, "@calls");
}
