use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use FindBin;
use IO::Socket::INET;
use POSIX qw(setsid :sys_wait_h);
use Time::HiRes qw(sleep);

=pod

=head1 NAME

t/dashboard_ssl_parity.t - the HTTPS front proxy of a standalone binary versus stock Perl

=head1 WHY IT EXISTS

C<dashboard serve --ssl> runs a public frontend that proxies real TLS to an internal Starman backend,
answers plain HTTP with a redirect and reacts to TERM/INT/HUP. Those handler-compiled subs (TLS
detection, request-head reading, redirect building, signal chaining, certificate profile checks) are
not reached by the plain HTTP service parity test, so this test drives them as a client.

=head1 DESCRIPTION

For each launcher, in a fresh HOME: start C<serve --foreground --ssl> on 127.0.0.1:7891, send plain
HTTP requests (good, odd Host, hostile target, split writes, oversized head, garbage, empty), do real
TLS conversations (including a large body through the proxy and a junk TLS record), inspect the
generated certificate, restart over a legacy certificate to prove it is regenerated, and for each of
TERM, INT and HUP check how the process ends and that nothing is left behind. The observations of the
interpreter and the binary must be identical. Skips without the application checkout, IO::Socket::SSL,
openssl, or a free port 7891.

=head1 HOW TO RUN

  prove -l t/dashboard_ssl_parity.t

=cut

my $app = $ENV{PAX_PARITY_APP} // abs_path("$FindBin::Bin/../../developer-dashboard") // '';
plan skip_all => 'no Developer Dashboard checkout found (set PAX_PARITY_APP)' if !$app || !-f "$app/bin/dashboard";
plan skip_all => 'IO::Socket::SSL is not installed' if !eval { require IO::Socket::SSL; 1 };
plan skip_all => 'openssl is not installed' if system('openssl version >/dev/null 2>&1') != 0;
use Fcntl qw(:flock);
open my $port_lock, '>>', '/tmp/pax-port-7891.lock' or die "cannot open port lock: $!";
flock($port_lock, LOCK_EX);
my $port = 7891;
plan skip_all => "port $port is already in use" if IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 1);

my $pax = abs_path("$FindBin::Bin/../bin/pax");
my $tmp = tempdir('pax-ssl-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $home = "$tmp/home";
my $binary = "$tmp/ssl-app";
my $rc = $ENV{PAX_PARITY_BINARY} ? 0 : system("cd '$app' && PAX_PROGRESS=0 '$^X' '$pax' build --compact -o '$binary' bin/dashboard >'$tmp/build.json' 2>'$tmp/build.err'");
$binary = $ENV{PAX_PARITY_BINARY} if $ENV{PAX_PARITY_BINARY};   # reuse a prebuilt (e.g. tools/trace_build.sh) binary
plan skip_all => 'could not build the application with PAX' if $rc != 0 || !-x $binary;

my @live_groups;

sub port_up {
    my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 1);
    close $sock if $sock;
    return $sock ? 1 : 0;
}

sub wait_for_port {
    my ($up) = @_;
    for (1 .. 80) {
        return 1 if port_up() == ($up ? 1 : 0);
        sleep 0.25;
    }
    return 0;
}

# start_service(\@launcher) forks the foreground SSL service into its own process group.
sub start_service {
    my ($launcher) = @_;
    my $pid = fork();
    die "fork: $!" if !defined $pid;
    if (!$pid) {
        setsid();
        $ENV{HOME} = $home;
        $ENV{TMPDIR} = $tmp;
        $ENV{PAX_PROGRESS} = 0;
        open STDIN, '<', '/dev/null';
        open STDOUT, '>', "$tmp/service.out";
        open STDERR, '>&', \*STDOUT;
        exec @$launcher, 'serve', '--foreground', '--ssl', '--host', '127.0.0.1', '--port', $port;
        exit 127;
    }
    push @live_groups, $pid;
    return $pid;
}

# group_alive($pgid) is true while any process of the group still exists.
sub group_alive {
    my ($pgid) = @_;
    # A zombie that init has not reaped yet is gone for our purposes.
    my @live = grep { /\A\s*\Q$pgid\E\s+[^Z\s]/ } `ps -eo pgid=,stat= 2>/dev/null`;
    return @live ? 1 : 0;
}

# end_service($pid, $signal) signals the service and describes how it ended.
sub end_service {
    my ($pid, $signal) = @_;
    kill $signal, $pid if defined $signal;
    my $status;
    for (1 .. 60) {
        my $w = waitpid($pid, WNOHANG);
        if ($w == $pid) { $status = $?; last }
        sleep 0.25;
    }
    my $ended = !defined $status ? 'still running after 15s'
      : WIFSIGNALED($status) ? 'killed by signal ' . WTERMSIG($status)
      : 'exit ' . WEXITSTATUS($status);
    sleep 1;
    my $left = group_alive($pid) ? 'group survivors' : 'group gone';
    my $closed = wait_for_port(0) ? 'port closed' : 'port open';
    kill 9, -$pid if group_alive($pid);
    waitpid($pid, WNOHANG) if !defined $status;
    return "$ended, $left, $closed";
}

END {
    kill 9, -$_ for grep { kill 0, -$_ } @live_groups;
}

# plain($bytes, %opt) sends raw bytes to the public port and returns the raw response.
sub plain {
    my ($chunks, %opt) = @_;
    my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 10) or return 'connect failed';
    for my $chunk (@$chunks) {
        syswrite($sock, $chunk);
        sleep 0.2 if @$chunks > 1;
    }
    shutdown($sock, 1) if $opt{half_close};
    my $raw = '';
    my $sel = IO::Select->new($sock);
    while ($sel->can_read(3)) {
        my $n = sysread($sock, my $buf, 65536);
        last if !$n;
        $raw .= $buf;
    }
    close $sock;
    $raw =~ s/\r/<CR>/g;
    $raw =~ s/\n/<LF>/g;
    return $raw eq '' ? '(empty)' : $raw;
}

sub tls_get {
    my ($path, %opt) = @_;
    my $sock = IO::Socket::SSL->new(
        PeerAddr => '127.0.0.1', PeerPort => $port, SSL_verify_mode => 0, Timeout => 10,
        SSL_hostname => 'localhost',
    ) or return 'tls connect failed';
    my $head = "$opt{method}" . ($opt{method} ? '' : 'GET') . " $path HTTP/1.0\r\nHost: example.test:$port\r\n" . join('', map { "$_: $opt{headers}{$_}\r\n" } sort keys %{ $opt{headers} || {} });
    $head =~ s/\A/GET / if 0;
    if (defined $opt{body}) { $head .= 'Content-Type: application/x-www-form-urlencoded' . "\r\n" . 'Content-Length: ' . length($opt{body}) . "\r\n" }
    print {$sock} $head . "\r\n" . ($opt{body} // '');
    my $raw = '';
    while (1) { my $n = sysread($sock, my $buf, 65536); last if !$n; $raw .= $buf; }
    close $sock;
    my ($status) = $raw =~ m{\AHTTP/\d\.\d (\d+)};
    my ($location) = $raw =~ /^Location: *([^\r\n]*)/mi;
    my ($xfo) = $raw =~ /^X-Frame-Options: *([^\r\n]*)/mi;
    return join ' ', 'status=' . ($status // 'none'), 'loc=' . ($location // ''), 'xfo=' . ($xfo // ''), 'cipher=' . ($sock->can('get_cipher') ? 'ok' : '-');
}

sub cert_summary {
    my $out = `openssl x509 -in '$home/.developer-dashboard/certs/server.crt' -noout -text 2>&1`;
    my @san = sort($out =~ /(?:DNS:|IP Address:)([^\s,]+)/g);
    my ($ca) = $out =~ /(CA:\w+)/;
    my ($eku) = $out =~ /Extended Key Usage:[^\n]*\n\s*([^\n]+)/;
    my ($ku) = $out =~ /Key Usage:[^\n]*\n\s*([^\n]+)/;
    my @mode = map { sprintf '%04o', (stat "$home/.developer-dashboard/certs/$_")[2] & 07777 } qw(server.crt server.key);
    my $dir = sprintf '%04o', (stat "$home/.developer-dashboard/certs")[2] & 07777;
    my $left = join ',', sort map { s{.*/}{}r } glob("$home/.developer-dashboard/certs/*");
    return "san=@san ca=" . ($ca // '') . " eku=" . ($eku // '') . " ku=" . ($ku // '') . " modes=@mode dir=$dir files=$left";
}

sub cert_fingerprint {
    my $fp = `openssl x509 -in '$home/.developer-dashboard/certs/server.crt' -noout -fingerprint 2>&1`;
    chomp $fp;
    return $fp;
}

sub fresh_home {
    remove_tree($home);
    make_path("$home/.developer-dashboard");
}

sub observe {
    my ($launcher) = @_;
    fresh_home();
    my @seen;
    my $pid = start_service($launcher);
    if (!wait_for_port(1)) {
        push @seen, 'service did not start';
        push @seen, 'end: ' . end_service($pid, 'TERM');
        return @seen;
    }
    sleep 1;
    my $first_fp = cert_fingerprint();
    push @seen, 'cert: ' . cert_summary();

    my @cases = (
        [ 'plain basic',        [ "GET /a/b?c=1 HTTP/1.1\r\nHost: localhost:$port\r\n\r\n" ] ],
        [ 'plain loopback v6',  [ "GET /a HTTP/1.1\r\nHost: [::1]:$port\r\n\r\n" ] ],
        [ 'plain evil host',    [ "GET /a HTTP/1.1\r\nHost: evil.example.com\r\n\r\n" ] ],
        [ 'plain bad host',     [ "GET /a HTTP/1.1\r\nHost: bad host\r\n\r\n" ] ],
        [ 'plain no host',      [ "GET /a HTTP/1.1\r\n\r\n" ] ],
        [ 'plain empty host',   [ "GET /a HTTP/1.1\r\nHost: \r\n\r\n" ] ],
        [ 'plain host spaces',  [ "GET /a HTTP/1.1\r\nhost:   localhost  \r\n\r\n" ] ],
        [ 'plain authority',    [ "GET \@evil.com/ HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" ] ],
        [ 'plain double slash', [ "GET //evil.com/x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" ] ],
        [ 'plain backslash',    [ "GET /a\\b HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" ] ],
        [ 'plain LF only',      [ "GET /lf HTTP/1.1\nHost: localhost\n\n" ] ],
        [ 'plain HEAD',         [ "HEAD /h HTTP/1.1\r\nHost: localhost\r\n\r\n" ] ],
        [ 'plain POST',         [ "POST /p HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\nbody" ] ],
        [ 'plain split',        [ "GET /sp", "lit?x=1 HTTP/1.1\r\nHo", "st: localhost\r\n\r\n" ] ],
        [ 'plain garbage',      [ "not http at all\r\n\r\n" ] ],
        [ 'plain lowercase',    [ "get /x HTTP/1.1\r\nHost: localhost\r\n\r\n" ] ],
        [ 'plain http10',       [ "GET /old HTTP/1.0\r\n\r\n" ] ],
        [ 'plain huge target',  [ "GET /" . ('a' x 3000) . " HTTP/1.1\r\nHost: localhost\r\n\r\n" ] ],
        [ 'plain huge head',    [ "GET / HTTP/1.1\r\nHost: localhost\r\nX-Pad: " . ('p' x 20000) . "\r\n\r\n" ] ],
        [ 'plain unterminated', [ "GET /u HTTP/1.1\r\nHost: localhost\r\n" ], 1 ],
        [ 'plain empty',        [ ], 1 ],
    );
    for my $case (@cases) {
        my ($label, $chunks, $half) = @$case;
        push @seen, "$label: " . plain($chunks, half_close => $half);
    }
    push @seen, 'tls junk record: ' . plain([ "\x16\x03\x01\x00\x05junk!" ]);
    push @seen, 'tls root: ' . tls_get('/', method => 'GET');
    push @seen, 'tls nosuch: ' . tls_get('/nosuch', method => 'GET');
    push @seen, 'tls forwarded http: ' . tls_get('/', method => 'GET', headers => { 'X-Forwarded-Proto' => 'http' });
    push @seen, 'tls big body: ' . tls_get('/login', method => 'POST', body => 'username=bob&password=' . ('x' x 600000));
    push @seen, 'tls login: ' . tls_get('/login', method => 'POST', headers => { Origin => "https://example.test:$port" }, body => 'username=nobody&password=bad');
    push @seen, 'plain still ok: ' . plain([ "GET /again HTTP/1.1\r\nHost: localhost\r\n\r\n" ]);
    push @seen, 'end TERM: ' . end_service($pid, 'TERM');

    # A restart reuses a certificate that already has the right profile.
    $pid = start_service($launcher);
    push @seen, wait_for_port(1) ? 'restart up' : 'restart down';
    sleep 1;
    push @seen, 'cert reused: ' . (cert_fingerprint() eq $first_fp ? 'yes' : 'no');
    push @seen, 'end INT: ' . end_service($pid, 'INT');

    # A legacy certificate (no SAN, no server-auth profile) is replaced.
    make_path("$home/.developer-dashboard/certs");
    system("openssl req -new -x509 -days 2 -nodes -subj /CN=legacy -out '$home/.developer-dashboard/certs/server.crt' -keyout '$home/.developer-dashboard/certs/server.key' >/dev/null 2>&1");
    my $legacy_fp = cert_fingerprint();
    $pid = start_service($launcher);
    push @seen, wait_for_port(1) ? 'legacy restart up' : 'legacy restart down';
    sleep 1;
    push @seen, 'legacy replaced: ' . (cert_fingerprint() ne $legacy_fp ? 'yes' : 'no') . ' ' . cert_summary();
    push @seen, 'tls after regenerate: ' . tls_get('/', method => 'GET');
    push @seen, 'end HUP: ' . end_service($pid, 'HUP');

    # Signal sent while a client is connected mid-conversation.
    $pid = start_service($launcher);
    push @seen, wait_for_port(1) ? 'busy restart up' : 'busy restart down';
    my $held = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port);
    syswrite($held, "GET /held HTTP/1.1\r\nHost: localhost\r\n");
    sleep 0.5;
    push @seen, 'end TERM busy: ' . end_service($pid, 'TERM');
    close $held if $held;

    # Missing certificate directory permission/removal: stop with INT right after start.
    $pid = start_service($launcher);
    push @seen, wait_for_port(1) ? 'last restart up' : 'last restart down';
    push @seen, 'end INT immediate: ' . end_service($pid, 'INT');
    return @seen;
}

my @stock = observe([ $^X, "-I$app/lib", "$app/bin/dashboard" ]);
my @bin = observe([ $binary ]);

isnt($stock[0], 'service did not start', 'the interpreter serves HTTPS');
ok((grep { /^tls root: status=401/ } @stock), 'the interpreter answers a real TLS request through the proxy');
ok((grep { /^plain basic: .*307 Temporary Redirect.*Location: https:\/\/localhost:7891\/a\/b\?c=1/ } @stock), 'the interpreter redirects plain HTTP');
is_deeply(\@bin, \@stock, 'the standalone binary behaves like the interpreter on the SSL port')
  or diag join "\n", map { "stock: " . ($stock[$_] // '') . "\n  bin: " . ($bin[$_] // '') } grep { ($stock[$_] // '') ne ($bin[$_] // '') } 0 .. ($#stock > $#bin ? $#stock : $#bin);
ok(!port_up(), 'no service is left running');

done_testing();
