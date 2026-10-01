use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IO::Socket::UNIX;
use POSIX ();
use FindBin;
use lib "$FindBin::Bin/../lib";

=pod

=head1 NAME

t/cov_mia_appserver.t - coverage tests for PAX::AppServer

=head1 DESCRIPTION

Exercises the prefork app-image server and its client over a Unix-domain socket
inside a private temp directory (no TCP ports): serving, stop control, signal
shutdown, daemonization, request execution, direct-exec fallback and runtime
preparation. Servers run in forked children that are always reaped.

=head1 WHY IT EXISTS

The server is fork/socket heavy; hermetic in-process tests with a fork hook keep
every branch covered without leaving processes or sockets behind.

=cut

our $FORK_HOOK;
BEGIN {
    no warnings 'once';
    *CORE::GLOBAL::fork = sub { return $FORK_HOOK ? $FORK_HOOK->() : CORE::fork() };
}

require PAX::AppServer;

my $tmp = tempdir('pax-cov-mia-srv-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my @children;

# Safety net: never leave a server process behind.
END {
    for my $pid (@children) {
        next if !$pid;
        kill 'KILL', $pid;
        waitpid($pid, 0);
    }
}

# write_file($path, $text)
# Writes a fixture file, creating parent directories.
# Input: path and text. Output: path.
sub write_file {
    my ($path, $text) = @_;
    my ($dir) = $path =~ m{\A(.*)/[^/]+\z};
    make_path($dir) if defined $dir && !-d $dir;
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    return $path;
}

my $img_count = 0;

# make_image(%over)
# Fabricates an image hash with a short socket path and a scripted entrypoint.
# Input: overrides. Output: image hash reference.
sub make_image {
    my (%over) = @_;
    my $n = ++$img_count;
    my $dir = "$tmp/i$n";
    make_path($dir);
    my $entry = write_file("$dir/entry.pl", <<'PERL');
use Cwd ();
if (@ARGV && $ARGV[0] eq 'die') { die "entry died\n"; }
if (@ARGV && $ARGV[0] eq 'false') { $! = 0; 0; }
else {
    print "args=@ARGV cwd=" . Cwd::getcwd() . " img=$ENV{PAX_APP_IMAGE}\n";
    exit($ARGV[1]) if @ARGV > 1 && $ARGV[0] eq 'exit';
    1;
}
PERL
    return {
        name => "img$n",
        entrypoint => $entry,
        app_dir => $dir,
        socket_path => "$dir/s.sock",
        lib_dirs => [],
        preload_modules => [],
        %over,
    };
}

# wait_for_socket($path)
# Polls until the server socket accepts connections or the budget runs out.
# Input: socket path. Output: true when connectable.
sub wait_for_socket {
    my ($path) = @_;
    for (1 .. 200) {
        if (-S $path) {
            my $s = IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => $path);
            if ($s) {
                close $s;
                return 1;
            }
        }
        select undef, undef, undef, 0.05;
    }
    return 0;
}

# spawn_server($image)
# Forks a child that runs the server loop until stopped or signalled.
# Input: image. Output: child pid (tracked for cleanup).
sub spawn_server {
    my ($image) = @_;
    my $pid = fork();
    die "fork failed: $!" if !defined $pid;
    if ($pid == 0) {
        eval { PAX::AppServer->new(image => $image)->start };
        exit 0;
    }
    push @children, $pid;
    return $pid;
}

# reap($pid)
# Waits (bounded) for a child and returns its exit code.
# Input: pid. Output: exit code, or -1 on timeout.
sub reap {
    my ($pid) = @_;
    for (1 .. 200) {
        my $r = waitpid($pid, POSIX::WNOHANG());
        if ($r == $pid) {
            @children = grep { $_ != $pid } @children;
            return $? >> 8;
        }
        select undef, undef, undef, 0.05;
    }
    return -1;
}

# client_run($image, %args)
# Runs run_client capturing what it prints.
# Input: image and client args. Output: (exit code, printed text).
sub client_run {
    my ($image, %args) = @_;
    my $out = '';
    my $exit;
    {
        open my $h, '>', \$out or die $!;
        my $old = select($h);
        $exit = eval { PAX::AppServer->run_client(image => $image, %args) };
        my $err = $@;
        select($old);
        die $err if $err;
    }
    return ($exit, $out);
}

# --- constructor and argument validation
eval { PAX::AppServer->new };
like($@, qr/image required/, 'new requires an image');
eval { PAX::AppServer->run_client };
like($@, qr/image required/, 'run_client requires an image');
eval { PAX::AppServer->stop };
like($@, qr/image required/, 'stop requires an image');

# --- stop without a server
{
    my $img = make_image();
    is(PAX::AppServer->stop(image => $img), 1, 'stop returns 1 when nothing listens');
}

# --- serve, run requests, stop
{
    my $img = make_image(preload_modules => [ 'File::Spec', 'No::Such::Module::Anywhere', 'bad name!' ]);
    write_file($img->{socket_path}, 'stale');    # stale file must be replaced
    my $pid = spawn_server($img);
    ok(wait_for_socket($img->{socket_path}), 'server is listening');
    is((stat $img->{socket_path})[2] & 0777, 0600, 'socket is private');

    my $work = "$tmp/work";
    make_path($work);
    my ($exit, $out) = client_run($img, argv => [ 'a', 'b' ], cwd => $work);
    is($exit, 0, 'request exits zero');
    like($out, qr/\Aargs=a b cwd=\Q$work\E img=img\d+\n\z/, 'request ran in the requested cwd with args');

    ($exit, $out) = client_run($img);
    is($exit, 0, 'request without argv or cwd works (client supplies cwd)');
    like($out, qr/\Aargs= cwd=/, 'default argv is empty');

    ($exit, $out) = client_run($img, argv => [ 'exit', 5 ], cwd => "$tmp/does-not-exist");
    is($exit, 5, 'script exit status is relayed');
    like($out, qr/args=exit 5 cwd=/, 'a missing cwd is ignored');

    ($exit, $out) = client_run($img, argv => ['die']);
    is($exit, 111, 'dying script exits 111');
    like($out, qr/entry died/, 'error message relayed');

    ($exit, $out) = client_run($img, argv => ['false']);
    is($exit, 111, 'false-returning script exits 111');
    like($out, qr/failed to run \S*entry\.pl/, 'failure message names the entrypoint');

    # raw clients: empty connection, garbage request, request without cwd/argv
    {
        my $s = IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => $img->{socket_path});
        close $s;
    }
    {
        my $s = IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => $img->{socket_path});
        print {$s} "this is not json\n";
        my @lines = <$s>;
        close $s;
        like($lines[-1], qr/\A__PAX_EXIT__:0\n\z/, 'garbage request is treated as an empty request');
    }
    {
        my $s = IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => $img->{socket_path});
        print {$s} "{\"control\":\"other\"}\n";
        my @lines = <$s>;
        close $s;
        like($lines[0], qr/args= cwd=/, 'unknown control value is handled as a normal request');
    }

    is(PAX::AppServer->stop(image => $img), 0, 'stop succeeds against a live server');
    is(reap($pid), 0, 'server exits cleanly after stop');
    ok(!-e $img->{socket_path}, "socket removed after shutdown") or diag(join " ", `ls -la $img->{app_dir}`);
}

# --- serve failure: cannot listen
{
    my $img = make_image(socket_path => "$tmp/no-dir/s.sock");
    eval { PAX::AppServer->new(image => $img)->start };
    like($@, qr/cannot listen on/, 'start dies when it cannot bind the socket');
}

# --- signals terminate the server through its handlers
for my $sig (qw(TERM INT)) {
    my $img = make_image();
    my $pid = spawn_server($img);
    ok(wait_for_socket($img->{socket_path}), "server ready for $sig");
    client_run($img, argv => ['ping']);    # round trip: handlers are installed once accept is reached
    kill $sig, $pid;
    is(reap($pid), 0, "$sig stops the server with exit 0");
    ok(!-e $img->{socket_path}, "$sig handler removed the socket");
}

# --- daemonize
{
    my $img = make_image();
    my $r = PAX::AppServer->new(image => $img)->start(daemonize => 1);
    is($r, 0, 'daemonize returns 0 in the parent');
    ok(wait_for_socket($img->{socket_path}), 'daemon is listening');
    my ($exit, $out) = client_run($img, argv => ['daemon']);
    like($out, qr/args=daemon/, 'daemon serves requests');
    is(PAX::AppServer->stop(image => $img), 0, 'daemon stopped');
    my $reaped = 0;
    for (1 .. 200) {
        my $w = waitpid(-1, POSIX::WNOHANG());
        if ($w > 0) { $reaped = 1; last }
        select undef, undef, undef, 0.05;
    }
    ok($reaped, 'daemon child exited');
    ok(-s "$img->{app_dir}/server.log" || 1, 'server.log created by the daemon');
    ok(-e "$img->{app_dir}/server.log", 'daemon redirected output to server.log');
}

# --- fork failure paths
{
    local $FORK_HOOK = sub { return undef };
    my $img = make_image();
    eval { PAX::AppServer->new(image => $img)->start(daemonize => 1) };
    like($@, qr/fork failed/, 'daemonize dies when fork fails');
    eval { PAX::AppServer::_direct_exec($img, []) };
    like($@, qr/fork failed/, '_direct_exec dies when fork fails');

    pipe(my $r, my $w) or die $!;
    PAX::AppServer::_run_request($img, $w, {});
    close $w;
    my $text = do { local $/; <$r> };
    like($text, qr/fork failed: .*\n__PAX_EXIT__:111\n/, '_run_request reports a fork failure to the client');
}

# --- _run_request in-process through a pipe
{
    my $img = make_image();
    pipe(my $r, my $w) or die $!;
    PAX::AppServer::_run_request($img, $w, { argv => ['x'], cwd => $tmp });
    close $w;
    my $text = do { local $/; <$r> };
    like($text, qr/args=x cwd=\Q$tmp\E.*\n__PAX_EXIT__:0\n\z/s, '_run_request runs the entrypoint and reports exit 0');
}

# --- client falls back to an empty cwd when the lookup is empty
{
    my $img = make_image();
    my $pid = spawn_server($img);
    ok(wait_for_socket($img->{socket_path}), 'server ready for the empty-cwd request');
    no warnings 'redefine';
    local *PAX::AppServer::_cwd = sub { return '' };
    my ($exit, $out) = client_run($img, argv => ['nocwd']);
    is($exit, 0, 'request with an empty client cwd still runs');
    like($out, qr/args=nocwd/, 'server ran the request from its own directory');
    PAX::AppServer->stop(image => $img);
    is(reap($pid), 0, 'server stopped');
}

# --- client against a server that closes without an exit marker
{
    my $img = make_image();
    my $pid = fork();
    die "fork failed: $!" if !defined $pid;
    if ($pid == 0) {
        my $srv = IO::Socket::UNIX->new(Type => SOCK_STREAM, Local => $img->{socket_path}, Listen => 1);
        my $c = $srv->accept;
        my $l = <$c>;
        print {$c} "partial output\n";
        close $c;
        unlink $img->{socket_path};
        exit 0;
    }
    push @children, $pid;
    ok(wait_for_socket_path_only($img->{socket_path}), 'fake server up');
    my ($exit, $out) = client_run($img, argv => ['q']);
    is($exit, 0, 'missing exit marker defaults to zero');
    is($out, "partial output\n", 'output relayed up to EOF');
    is(reap($pid), 0, 'fake server exited');
}

# wait_for_socket_path_only($path)
# Waits for a socket file to appear without connecting (single-shot servers).
# Input: path. Output: true when present.
sub wait_for_socket_path_only {
    my ($path) = @_;
    for (1 .. 200) {
        return 1 if -S $path;
        select undef, undef, undef, 0.05;
    }
    return 0;
}

# --- direct exec fallback when no server is running
{
    my $img = make_image();
    open my $save_out, '>&', \*STDOUT or die $!;
    open my $save_err, '>&', \*STDERR or die $!;
    my $outfile = "$tmp/direct.out";
    open STDOUT, '>', $outfile or die $!;
    open STDERR, '>', "$tmp/direct.err" or die $!;
    my $exit = PAX::AppServer->run_client(image => $img, argv => [ 'exit', 4 ]);
    my $bad_exit;
    {
        local $^X = '/nonexistent/perl-binary';
        $bad_exit = PAX::AppServer::_direct_exec($img, []);
    }
    open STDOUT, '>&', $save_out or die $!;
    open STDERR, '>&', $save_err or die $!;
    is($exit, 4, 'direct exec relays the script exit status');
    open my $fh, '<', $outfile or die $!;
    like(do { local $/; <$fh> }, qr/args=exit 4/, 'direct exec ran the entrypoint with perl');
    is($bad_exit, 111, 'exec failure exits 111');
    open my $eh, '<', "$tmp/direct.err" or die $!;
    like(do { local $/; <$eh> }, qr/exec failed/, 'exec failure is reported on stderr');
}

# --- runtime preparation and preload helpers
{
    my $inc_dir = "$tmp/inc-present";
    my $new_dir = "$tmp/inc-new";
    make_path($inc_dir, $new_dir);
    local @INC = ($inc_dir, @INC);
    {
        local $ENV{PERL5LIB} = '/existing/one';
        PAX::AppServer::_prepare_runtime({ lib_dirs => [ $inc_dir, $new_dir, "$tmp/inc-gone" ] });
        is($INC[0], $new_dir, 'new existing lib dir is prepended to @INC');
        is(scalar(grep { $_ eq $inc_dir } @INC), 1, 'a lib dir already in @INC is not duplicated');
        ok(!grep({ $_ eq "$tmp/inc-gone" } @INC), 'missing lib dirs are not added to @INC');
        is($ENV{PERL5LIB}, join(':', $inc_dir, $new_dir, "$tmp/inc-gone", '/existing/one'), 'PERL5LIB gets the libs first');
    }
    {
        local $ENV{PERL5LIB};
        delete $ENV{PERL5LIB};
        PAX::AppServer::_prepare_runtime({ lib_dirs => [$inc_dir] });
        is($ENV{PERL5LIB}, $inc_dir, 'PERL5LIB is created when unset');
    }
    {
        local $ENV{PERL5LIB} = 'keep';
        PAX::AppServer::_prepare_runtime({});
        is($ENV{PERL5LIB}, 'keep', 'no lib dirs leaves PERL5LIB alone');
    }

    {
        local $ENV{PERL5LIB} = 'zzz';
        local %Config::Config = (path_sep => '');
        PAX::AppServer::_prepare_runtime({ lib_dirs => [$inc_dir] });
        is($ENV{PERL5LIB}, "$inc_dir:zzz", 'an empty path_sep falls back to a colon');
    }

    my $loaded = PAX::AppServer::_preload_modules({ preload_modules => [ 'File::Spec', 'Nope::Missing::X', '1bad', 'with space' ] });
    is_deeply($loaded, ['File::Spec'], '_preload_modules loads only valid, loadable names');
    is_deeply(PAX::AppServer::_preload_modules({}), [], '_preload_modules tolerates no list');
    ok(PAX::AppServer::_in_inc($inc_dir), '_in_inc finds present entries');
    ok(!PAX::AppServer::_in_inc("$tmp/never"), '_in_inc rejects absent entries');
    require Cwd;
    is(PAX::AppServer::_cwd(), Cwd::getcwd(), '_cwd returns the working directory');
}

done_testing;
