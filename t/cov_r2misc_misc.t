use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use POSIX ();
use IO::Socket::UNIX;
use lib "$FindBin::Bin/../lib";

use PAX::AppImage;
use PAX::AppServer;
use PAX::Benchmark;
use PAX::Capture;
use PAX::CodeUnitCompiler;
use PAX::Mode;
use PAX::StandaloneAnalysis;
use PAX::StandaloneRuntime;

=pod

=head1 NAME

t/cov_r2misc_misc.t - round-two coverage and regression tests for small modules

=head1 DESCRIPTION

Exercises the helpers introduced or reshaped to close the last coverage gaps in
StandaloneAnalysis, AppImage, AppServer, Benchmark, Mode and friends, and pins
four regressions: AppServer stop() reading the server reply, the dynamic-scoping
source scan in Capture, the masked-mix smoke value, and Mode policy lookup.

=head1 WHY IT EXISTS

Each of these paths was unreachable or silently wrong before; the tests keep the
fixes honest without forking real servers longer than necessary.

=cut

my $tmp = tempdir('pax-cov-r2m-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($path, $text)
# Writes a fixture file.
# Input: path and text. Output: path.
sub write_file {
    my ($path, $text) = @_;
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    return $path;
}

# --- _real_path helpers fall back to the input when abs_path cannot resolve
{
    no warnings 'redefine';
    is(PAX::StandaloneAnalysis::_real_path($tmp), Cwd::abs_path($tmp), 'analysis _real_path resolves existing paths');
    is(PAX::AppImage::_real_path($tmp), Cwd::abs_path($tmp), 'appimage _real_path resolves existing paths');
    local *PAX::StandaloneAnalysis::abs_path = sub { return undef };
    local *PAX::AppImage::abs_path = sub { return undef };
    is(PAX::StandaloneAnalysis::_real_path('/no/where'), '/no/where', 'analysis _real_path keeps an unresolvable path');
    is(PAX::AppImage::_real_path('/no/where'), '/no/where', 'appimage _real_path keeps an unresolvable path');
}

# --- AppServer stop() reads the reply (regression: server got SIGPIPE)
{
    my $dir = "$tmp/stop";
    mkdir $dir or die $!;
    my $sock = "$dir/s.sock";
    my $pid = fork();
    die "fork failed: $!" if !defined $pid;
    if ($pid == 0) {
        $SIG{PIPE} = 'DEFAULT';
        my $srv = IO::Socket::UNIX->new(Type => SOCK_STREAM, Local => $sock, Listen => 1) or exit 2;
        my $c = $srv->accept;
        my $line = <$c>;
        select undef, undef, undef, 0.3;    # a client that hangs up early would now break the pipe
        print {$c} "__PAX_EXIT__:0\n";
        close $c;
        unlink $sock;
        exit 0;
    }
    for (1 .. 200) { last if -S $sock; select undef, undef, undef, 0.05 }
    is(PAX::AppServer->stop(image => { socket_path => $sock }), 0, 'stop succeeds against a slow server');
    waitpid($pid, 0);
    is($? & 127, 0, 'server was not killed by SIGPIPE');
    is($? >> 8, 0, 'server finished its reply and exited cleanly');
}

# --- AppServer exec failure path and PERL5LIB with empty entries
{
    no warnings 'redefine';
    local *PAX::AppServer::_exec_command = sub { return 0 };
    my $errfile = "$tmp/direct.err";
    open my $save, '>&', \*STDERR or die $!;
    open STDERR, '>', $errfile or die $!;
    my $exit = PAX::AppServer::_direct_exec({ lib_dirs => [], entrypoint => '/x.pl' }, []);
    open STDERR, '>&', $save or die $!;
    is($exit, 111, 'failed exec makes the child exit 111');
    open my $fh, '<', $errfile or die $!;
    like(do { local $/; <$fh> }, qr/exec failed: /, 'failed exec is reported on stderr');

    local @INC = @INC;
    local $ENV{PERL5LIB} = 'a::b:';
    PAX::AppServer::_prepare_runtime({ lib_dirs => ['/pax/r2m/lib'] });
    is($ENV{PERL5LIB}, '/pax/r2m/lib:a:b', 'empty PERL5LIB entries are dropped');
}

# --- Benchmark RSS reader is injectable
{
    local $PAX::Benchmark::STATUS_PATH = "$tmp/none/status";
    is(PAX::Benchmark::_current_rss_kb(), undef, 'missing status file yields undef');
    local $PAX::Benchmark::STATUS_PATH = write_file("$tmp/status-norss", "Name:\tx\nVmPeak:\t1 kB\n");
    is(PAX::Benchmark::_current_rss_kb(), undef, 'status file without VmRSS yields undef');
    local $PAX::Benchmark::STATUS_PATH = write_file("$tmp/status-rss", "Name:\tx\nVmRSS:\t  1234 kB\n");
    is(PAX::Benchmark::_current_rss_kb(), 1234, 'VmRSS is parsed');
}

# --- Mode policy lookup
{
    is(PAX::Mode->policy('ci')->{telemetry}, 'strict', 'known mode');
    is(PAX::Mode->policy('nonsense')->{telemetry}, 'verbose', 'unknown mode falls back to dev');
    is(PAX::Mode->policy->{telemetry}, 'verbose', 'default mode is dev');
}

# --- Capture source scan detects local on every sigil (regression)
{
    for my $case (['local $x = 1;', 1], ['local @x = (1);', 1], ['local %h;', 1], ['local *G;', 1], ['my $local = 1;', 0]) {
        my ($src, $want) = @$case;
        my $features = PAX::Capture::_scan_source_features(write_file("$tmp/scan.pl", "$src\n"));
        is($features->{local_dynamic}, $want, "local_dynamic for: $src");
    }
}

# --- masked-mix smoke value matches the loop it describes
{
    my $body = 'my ($n) = @_; my $acc = 0; for (my $i = 0; $i < $n; $i++) { $acc += (($i * 13) ^ ($i >> 3)) & 0xFFFF; } return $acc;';
    my $expected = 0;
    $expected += (($_ * 13) ^ ($_ >> 3)) & 0xFFFF for 0 .. 7;
    is($expected, 364, 'the loop sums to 364 for input 8');
    # the capture-side lowering lives inside the probe program text; compile just that sub
    my ($probe_sub) = PAX::Capture::_probe_source() =~ /^(sub _lower_i64_masked_mix_accum_loop \{.*?^\})/ms;
    ok($probe_sub, 'probe source carries the masked-mix lowering');
    my $probe_lower = eval "package R2Probe; no strict; $probe_sub \\&_lower_i64_masked_mix_accum_loop" or die $@;
    for my $shape ($probe_lower->($body), PAX::CodeUnitCompiler::_native_i64_masked_mix_accum_loop_shape($body)) {
        is($shape->{smoke_expected}, 364, "$shape->{source} smoke value");
        is(PAX::StandaloneRuntime::_interpret_native_shape($shape, [ $shape->{smoke_left} ]), $shape->{smoke_expected}, "$shape->{source} smoke value matches the runtime loop");
    }
}

done_testing;
