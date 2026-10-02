use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use FindBin;
use IO::Socket::INET;

=pod

=head1 NAME

t/dashboard_service_parity.t - web service and login flow of a standalone binary versus stock Perl

=head1 WHY IT EXISTS

The command-line parity test never starts the long-running service, so handlers used only by
C<restart>, C<stop> and the web routes (process control, request handling, login, sessions)
ran unverified. This test starts the real service twice, once under the interpreter and once
from the PAX-built binary, drives the same HTTP conversation against both and compares what a
client can observe.

=head1 DESCRIPTION

For each launcher: create a helper user, C<restart>, request a set of routes anonymously (helper
tier via a non-loopback Host header), log in with a good, a wrong, an unknown and an empty
password, use the session cookie, log out, then C<stop>. Status codes, redirect targets and the
presence of a session cookie are compared. The service is stopped (and any survivor killed) even
when a check fails. Skips without the application checkout, its dependencies or a free port 7890.

=head1 HOW TO RUN

  prove -l t/dashboard_service_parity.t

=cut

my $app = $ENV{PAX_PARITY_APP} // abs_path("$FindBin::Bin/../../developer-dashboard") // '';
plan skip_all => 'no Developer Dashboard checkout found (set PAX_PARITY_APP)' if !$app || !-f "$app/bin/dashboard";
my $port = 7890;
plan skip_all => "port $port is already in use" if IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 1);

my $pax = abs_path("$FindBin::Bin/../bin/pax");
my $tmp = tempdir('pax-svc-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $home = "$tmp/home";
my $binary = "$tmp/svc-app";
my $rc = system("cd '$app' && PAX_PROGRESS=0 '$^X' '$pax' build --compact -o '$binary' bin/dashboard >'$tmp/build.json' 2>'$tmp/build.err'");
plan skip_all => 'could not build the application with PAX' if $rc != 0 || !-x $binary;

my $host = 'example.test:7890';
my $base = "http://127.0.0.1:$port";

# command(@launcher, @args) runs one CLI command in the test HOME, output discarded.
sub command {
    my ($launcher, @args) = @_;
    local $ENV{HOME} = $home;
    local $ENV{PAX_PROGRESS} = 0;
    return system(join(' ', map { "'$_'" } @$launcher, @args) . " >/dev/null 2>&1 </dev/null");
}

# wait_for_port($up) polls until the port accepts (or stops accepting) connections.
sub wait_for_port {
    my ($up) = @_;
    for (1 .. 60) {
        my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 1);
        return 1 if $up && $sock || !$up && !$sock;
        select(undef, undef, undef, 0.5);
    }
    return 0;
}

# http($method, $path, %headers) sends one HTTP/1.0 request with the non-loopback Host header
# (a raw socket, because HTTP::Tiny refuses a caller-supplied Host) and returns status,
# redirect location and session cookie.
sub http {
    my ($method, $path, %extra) = @_;
    my $body = delete $extra{body};
    my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 20) or return { status => 599 };
    my $head = "$method $path HTTP/1.0\r\nHost: $host\r\n" . join('', map { "$_: $extra{$_}\r\n" } sort keys %extra);
    $head .= 'Content-Type: application/x-www-form-urlencoded' . "\r\n" . 'Content-Length: ' . length($body) . "\r\n" if defined $body;
    print {$sock} $head . "\r\n" . ($body // '');
    my $raw = do { local $/; <$sock> } // '';
    close $sock;
    my ($status) = $raw =~ m{\AHTTP/\d\.\d (\d+)};
    my ($location) = $raw =~ /^Location: *([^\r\n]*)/mi;
    my ($cookie) = $raw =~ /^Set-Cookie: *([^\r\n]*)/mi;
    return { status => $status // 599, location => $location, cookie => $cookie };
}

# observe(\@launcher) returns one comparable line per request of the HTTP conversation.
sub observe {
    my ($launcher) = @_;
    remove_tree($home);
    make_path($home);
    my @seen;
    my @seen;
    my $note = sub {
        my ($label, $res) = @_;
        my $loc = $res->{location} // '';
        $loc =~ s/\Q$base\E//;
        push @seen, "$label $res->{status} loc=$loc " . ($res->{cookie} ? 'cookie' : 'no-cookie');
    };
    my $get = sub {
        my ($label, $path, %extra) = @_;
        $note->($label, http('GET', $path, %extra));
    };
    command($launcher, 'auth', 'add-user', 'bob', 'password123');
    command($launcher, 'restart');
    if (wait_for_port(1)) {
        $get->("anon $_", $_) for '/', '/apps', '/app/index', '/nosuch';
        my $session;
        for my $creds ('username=bob&password=password123', 'username=bob&password=wrong', 'username=nobody&password=password123', 'username=bob&password=') {
            my $res = http('POST', '/login', Origin => "http://$host", body => $creds);
            $note->("login $creds", $res);
            ($session) = $res->{cookie} =~ /\A(dashboard_session=[^;]*)/ if !$session && $res->{cookie};
        }
        if (defined $session) {
            $get->("session $_", $_, Cookie => $session) for '/', '/apps', '/nosuch';
            $get->('logout', '/logout', Cookie => $session);
            $get->('after logout', '/', Cookie => $session);
        }
        else {
            push @seen, 'no session cookie issued';
        }
    }
    else {
        push @seen, 'service did not start';
    }
    command($launcher, 'stop');
    wait_for_port(0);
    return @seen;
}

my @stock;
my @bin;
END {
    # Never leave a service behind, whatever the checks did.
    for my $launcher ([ $^X, "-I$app/lib", "$app/bin/dashboard" ], [ $binary ]) {
        command($launcher, 'stop') if $home && -d $home && -x ($launcher->[0]);
    }
}
@stock = observe([ $^X, "-I$app/lib", "$app/bin/dashboard" ]);
@bin = observe([ $binary ]);

isnt($stock[0], 'service did not start', 'the interpreter serves the application');
ok((grep { /^login username=bob&password=password123 302 .* cookie$/ } @stock), 'the interpreter accepts a good login');
is_deeply(\@bin, \@stock, 'the standalone binary answers the same HTTP conversation as the interpreter');
ok(!IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 1), 'no service is left running');

done_testing();
