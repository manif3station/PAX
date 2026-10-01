use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/../lib";

use PAX::Capture;
use PAX::Benchmark;
use PAX::RuntimeDispatcher;
use PAX::Manifest;
use PAX::RegionSelector;
use PAX::HIR;
use PAX::GuardedSSA;
use PAX::GuardManager;
use PAX::Tier1;
use PAX::NativeRunner;

=pod

=head1 NAME

t/cov_mib_flow.t - coverage tests for capture, benchmark and runtime dispatch

=head1 WHY IT EXISTS

PAX::Capture, PAX::Benchmark and PAX::RuntimeDispatcher orchestrate the reference
probe, the compile pipeline and native execution. Their failure and fallback
branches need fabricated pipeline results to be reached deterministically.

=head1 DESCRIPTION

The probe subprocess, the compile pipeline stages and the native artifacts are
replaced with local overrides and small shell scripts so every branch and
condition of the three modules is driven in-process without relying on a
compiler or on timing.

=cut

my $root = tempdir('pax-cov-mib-flow-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($name, $text, $mode)
# Writes a fixture file into the temp root.
# Input: file name, text and optional chmod mode. Output: absolute path.
sub write_file {
    my ($name, $text, $mode) = @_;
    my $path = File::Spec->catfile($root, $name);
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    chmod $mode, $path if $mode;
    return $path;
}

# --- PAX::Capture -----------------------------------------------------------
{
    is(PAX::Capture->new->{mode}, 'live', 'default capture mode');
    my $cap = PAX::Capture->new(mode => 'static');

    my $missing = $cap->capture(File::Spec->catfile($root, 'no-such-dir', 'x.pl'));
    is($missing->{status}, 'error', 'unresolvable entrypoint errors');
    is($missing->{diagnostics}[0]{code}, 'entrypoint_not_found', 'missing diagnostic');
    is($cap->capture($root)->{status}, 'error', 'directory entrypoint errors');

    my $script = write_file('s.pl', "print 1;\n");
    my @probe_args;
    my @probe_result = (JSON::PP::encode_json({ diagnostics => [{ level => 'note', code => 'x', message => 'm' }], marker => 1 }), '', 0);
    no warnings 'redefine';
    local *PAX::Capture::_run_perl_probe = sub { @probe_args = @_; return @probe_result };

    my $ok = $cap->capture($script);
    is($ok->{status}, 'ok', 'clean probe is ok');
    is($ok->{marker}, 1, 'probe data kept');
    is($ok->{mode}, 'static', 'mode recorded');
    is($probe_args[2], 'static', 'mode passed to probe');
    is($ok->{source_entrypoint}, File::Spec->rel2abs($script), 'absolute entrypoint');
    is_deeply([ map { $_->{code} } @{ $ok->{diagnostics} } ], ['x'], 'probe diagnostics preserved');
    is(ref $ok->{source_features}, 'HASH', 'features attached');

    @probe_result = ('{"a":1}', "warned\n", 0);
    my $warn = $cap->capture($script);
    is($warn->{status}, 'ok', 'stderr alone keeps status');
    is_deeply([ map { "$_->{level}:$_->{code}" } @{ $warn->{diagnostics} } ], ['warning:perl_stderr'], 'stderr is a warning');

    @probe_result = ('{"a":1}', "boom\n", 3);
    my $fail = $cap->capture($script);
    is($fail->{status}, 'error', 'non-zero exit is an error');
    is_deeply([ map { "$_->{level}:$_->{code}" } @{ $fail->{diagnostics} } ], ['error:perl_stderr', 'error:capture_failed'], 'stderr and exit diagnostics');
    like($fail->{diagnostics}[1]{message}, qr/status 3/, 'exit status in message');

    @probe_result = ('[1,2]', '', 0);
    my $notahash = $cap->capture($script);
    is($notahash->{status}, 'ok', 'non-hash probe data tolerated');
    is_deeply($notahash->{diagnostics}, [], 'no diagnostics for non-hash data');

    @probe_result = ('not json', '', 0);
    my $bad = $cap->capture($script);
    is($bad->{diagnostics}[0]{code}, 'probe_json_decode_failed', 'invalid JSON is diagnosed');
    is($bad->{raw_probe_output}, 'not json', 'raw output kept');
}

# --- PAX::Capture helpers ---------------------------------------------------
{
    is_deeply(PAX::Capture::_scan_source_features(File::Spec->catfile($root, 'nope.pl')), {}, 'unreadable source has no features');
    my $dirfeatures = do { local $SIG{__WARN__} = sub { }; PAX::Capture::_scan_source_features($root) };
    is($dirfeatures->{string_eval}, 0, 'directory source reads as empty');

    my $none = write_file('plain.pl', "my \$x = 1;\n");
    is_deeply([ grep { PAX::Capture::_scan_source_features($none)->{$_} } qw(string_eval autoload tie overload typeglob xs_loader local_dynamic) ], [], 'plain source has no features');
    my $all = write_file('all.pl', join("\n", 'eval "1";', 'sub AUTOLOAD {}', 'tie my %h, "X";', 'use overload q{""} => sub {1};', '*foo = sub {};', 'use XSLoader;', 'local %h;') . "\n");
    my $f = PAX::Capture::_scan_source_features($all);
    is_deeply([ grep { !$f->{$_} } sort keys %$f ], [], 'every feature detected');

    my ($out, $err, $exit) = PAX::Capture::_run_perl_probe('print "out:@ARGV"; print STDERR "err"; exit 2;', 'entry', 'live');
    is($out, 'out:entry live', 'probe stdout');
    is($err, 'err', 'probe stderr');
    is($exit, 2, 'probe exit status');

    no warnings 'redefine';
    local *PAX::Capture::open3 = sub {
        my $pid = fork;
        die "fork failed: $!" if !defined $pid;
        if (!$pid) { exit 0 }
        for my $i (1, 2) {
            open my $closed, '<', \ 'x' or die $!;
            close $closed;
            $_[$i] = $closed;
        }
        open my $in, '>', File::Spec->devnull or die $!;
        $_[0] = $in;
        return $pid;
    };
    my @quiet = do { local $SIG{__WARN__} = sub { }; PAX::Capture::_run_perl_probe('', 'e', 'live') };
    is_deeply(\@quiet, ['', '', 0], 'closed pipes read as empty strings');
}

# --- PAX::Capture against the real probe ------------------------------------
{
    my $real = write_file('real.pl', "sub add { my (\$l, \$r) = \@_; return \$l + \$r; }\n1;\n");
    my $result = PAX::Capture->new(mode => 'live')->capture($real);
    is($result->{status}, 'ok', 'real probe succeeds');
    ok(scalar @{ $result->{capture}{sub_optrees} }, 'real probe reports subs');
}

# --- PAX::Benchmark ---------------------------------------------------------
{
    is(PAX::Benchmark->new->{iterations}, 3, 'default iterations');
    my $bench = PAX::Benchmark->new(iterations => 2, pax_bin => 'pax');
    is($bench->{pax_bin}, 'pax', 'pax_bin kept');

    is_deeply(PAX::Benchmark::_memory_impact(undef, 5)->{measured}, JSON::PP::false(), 'undefined before is unmeasured');
    is(PAX::Benchmark::_memory_impact(5, undef)->{delta_rss_kb}, undef, 'undefined after has no delta');
    my $mem = PAX::Benchmark::_memory_impact(5, 9);
    is($mem->{delta_rss_kb}, 4, 'memory delta');
    ok($mem->{measured}, 'memory measured');
    like(PAX::Benchmark::_current_rss_kb(), qr/^\d+$/, 'rss readable');

    my $empty = PAX::Benchmark::_summarise([]);
    is($empty->{mean_seconds}, 0, 'empty summary mean');
    is($empty->{warm_up_seconds}, 0, 'empty summary warm-up');
    my $full = PAX::Benchmark::_summarise([{ elapsed_seconds => 1 }, { elapsed_seconds => 3 }]);
    is($full->{mean_seconds}, 2, 'summary mean');
    is($full->{warm_up_seconds}, 1, 'summary warm-up');

    my $script = write_file('bench.pl', "exit 0;\n");
    my $timed = $bench->_time_command([$^X, '-e', 'exit 4']);
    is($timed->{samples}[0]{exit}, 4, 'command exit recorded');
    is(scalar @{ $timed->{samples} }, 2, 'one sample per iteration');

    no warnings 'redefine';
    my $capture_mode = 'ok';
    local *PAX::Capture::capture = sub {
        die "capture exploded\n" if $capture_mode eq 'die';
        return undef if $capture_mode eq 'undef';
        return { status => $capture_mode };
    };

    my $cb = $bench->run_capture_benchmark($script);
    is($cb->{benchmark_class}, 'capture_overhead', 'capture benchmark class');
    is_deeply([ map { $_->{exit} } @{ $cb->{samples} } ], [0, 0], 'ok capture exits zero');
    for my $mode (qw(die undef error)) {
        $capture_mode = $mode;
        my $r = $bench->run_capture_benchmark($script);
        is_deeply([ map { $_->{exit} } @{ $r->{samples} } ], [1, 1], "capture mode $mode exits one");
    }
    $capture_mode = 'ok';
    my $zero = PAX::Benchmark->new(iterations => 0)->run_capture_benchmark($script);
    is($zero->{mean_seconds}, 0, 'no samples mean');
    is($zero->{warm_up_seconds}, 0, 'no samples warm-up');

    # Native timing with a stubbed compile pipeline.
    my $adder = write_file('adder.sh', "#!/bin/sh\necho \$((\$1 + \$2))\n", 0755);
    my @artifacts;
    local *PAX::Manifest::to_hash = sub { { regions => 1 } };
    local *PAX::RegionSelector::select = sub { { selected => [] } };
    local *PAX::HIR::lower_all = sub { [] };
    local *PAX::GuardedSSA::build_all = sub { [ { region_id => 'a' }, { region_id => 'b' } ] };
    local *PAX::Tier1::compile = sub { shift @artifacts };

    @artifacts = ({ entry_kind => 'native_i64_loop', executable_path => $adder }, { entry_kind => undef });
    my $none = $bench->_time_native($script);
    ok(!$none->{available}, 'no leaf artifact is unavailable');
    ok(!defined $none->{mean_seconds}, 'unavailable has no mean');

    @artifacts = ({ entry_kind => 'native_i64_leaf' }, { entry_kind => 'native_i64_leaf', executable_path => $adder });
    my $native = $bench->_time_native($script);
    ok($native->{available}, 'leaf artifact is available');
    is($native->{result}{value}, 42, 'native result');
    is(scalar @{ $native->{samples} }, 2, 'native samples');

    @artifacts = ({ entry_kind => 'native_i64_leaf', executable_path => $adder }, { entry_kind => 'native_i64_leaf', executable_path => $adder });
    local *PAX::Benchmark::_time_command = sub { { mean_seconds => 0.5 } };
    @artifacts = ({ entry_kind => 'native_i64_leaf', executable_path => $adder }, undef);
    my $with = $bench->run_runtime_benchmark($script);
    is($with->{benchmark_class}, 'runtime', 'runtime benchmark class');
    is($with->{fallback_share}, 0, 'native available means no fallback share');
    is($with->{reference_mean_seconds}, 0.5, 'reference mean from stub');
    is($with->{native_result}{value}, 42, 'native result surfaced');

    @artifacts = (undef, undef);
    my $without = $bench->run_runtime_benchmark($script);
    is($without->{fallback_share}, 1, 'no native means full fallback share');
    ok(!$without->{native_available}, 'native unavailable');
}

# --- PAX::RuntimeDispatcher -------------------------------------------------
{
    my $adder = write_file('d-adder.sh', "#!/bin/sh\necho \$((\$1 + \$2))\n", 0755);
    my $failing = write_file('d-failing.sh', "#!/bin/sh\nexit 2\n", 0755);

    my %guard;
    my %artifact;
    my @ssa;
    my $baseline = 1;
    no warnings 'redefine';
    local *PAX::Capture::capture = sub { { status => 'ok' } };
    local *PAX::Manifest::to_hash = sub { { runtime => { baseline_match => $baseline }, runtime_epochs => {} } };
    local *PAX::RegionSelector::select = sub { { selected => [] } };
    local *PAX::HIR::lower_all = sub { [] };
    local *PAX::GuardedSSA::build_all = sub { \@ssa };
    local *PAX::GuardManager::validate_or_deopt = sub { $guard{ $_[1]{region_id} } };
    local *PAX::Tier1::compile = sub { $artifact{ $_[1]{region_id} } };

    my $native_guard = { status => 'native_allowed' };
    my $deopt_guard = { status => 'deopt', fallback => { reason => 'epoch changed' } };

    my $d = PAX::RuntimeDispatcher->new;
    is($d->{mode}, 'live', 'default mode');

    # Requested region not found.
    @ssa = ({ region_id => 'r1', region_name => 'main::one' }, { region_id => 'r0' });
    my $nf = $d->dispatch_i64(entrypoint => 'e.pl', region_name => 'ghost');
    is($nf->{status}, 'fallback', 'unknown region falls back');
    like($nf->{reason}, qr/requested region not found: ghost/, 'unknown region reason');
    is($nf->{args}[0], 0, 'operands default to zero');
    is($nf->{baseline_match}, 1, 'baseline reported');
    is($d->profile_report->{regions}[0]{region}, 'ghost', 'not-found dispatch recorded');
    is(ref $d->inline_cache_report, 'HASH', 'inline cache report');

    # All candidates deopt, with no region requested; unit has no region_name.
    my $d2 = PAX::RuntimeDispatcher->new(mode => 'static', threshold => 5);
    is($d2->{mode}, 'static', 'explicit mode');
    @ssa = ({ region_id => 'r1' });
    %guard = (r1 => $deopt_guard);
    my $none = $d2->dispatch_i64(entrypoint => 'e.pl');
    is($none->{status}, 'fallback', 'no candidate succeeded');
    is($none->{reason}, 'no native i64 dispatch candidate succeeded', 'no candidate reason');
    is($none->{attempts}[0]{status}, 'deopt', 'deopt attempt recorded');
    is($none->{attempts}[0]{osr}{reason}, 'epoch changed', 'retirement carries guard reason');
    is($d2->profile_report->{regions}[0]{region}, 'r1', 'deopt recorded by id');

    # Fallback artifacts: non-native kind, native kind without executable, undefined kind.
    @ssa = (
        { region_id => 'a', region_name => 'main::a' },
        { region_id => 'b', region_name => 'main::b' },
        { region_id => 'c', region_name => 'main::c' },
        { region_id => 'd', region_name => 'main::d' },
    );
    %guard = map { $_ => $native_guard } qw(a b c d);
    %artifact = (
        a => { entry_kind => 'native_probe_trampoline', reason => 'probe' },
        b => { entry_kind => 'native_i64_leaf', reason => 'no exe' },
        c => { reason => 'nothing' },
        d => { entry_kind => 'native_i64_loop', executable_path => $failing, reason => 'bad' },
    );
    my $d3 = PAX::RuntimeDispatcher->new(
        profile_store => PAX::ProfileStore->new(threshold => 1),
        inline_cache => PAX::InlineCache->new,
        hot_region_jit => PAX::HotRegionJIT->new(threshold => 1),
        osr => PAX::OSR->new(threshold => 1),
        aot => PAX::ProfileGuidedAOT->new(threshold => 1),
    );
    my $fb = $d3->dispatch_i64(entrypoint => 'e.pl', left => 3, right => 4, cache_site => 'site', region_name => 'd');
    is($fb->{status}, 'fallback', 'failing native binary falls back');
    is($fb->{result}{exit}, 2, 'native exit reported');
    is($fb->{requested_region}, 'd', 'requested region reported');
    is_deeply($fb->{args}, [3, 4], 'operands reported');

    my $multi = $d3->dispatch_i64(entrypoint => 'e.pl');
    is($multi->{status}, 'fallback', 'last candidate (d) still falls back');
    is(scalar @{ $multi->{attempts} }, 3, 'three non-native attempts before the failing binary');
    is_deeply([ map { $_->{reason} } @{ $multi->{attempts} } ], [qw(probe), 'no exe', 'nothing'], 'attempt reasons');

    # Successful native dispatch, matched via the bare and qualified region name.
    %artifact = (a => { entry_kind => 'native_i64_leaf', executable_path => $adder, reason => 'ok' });
    @ssa = ({ region_id => 'a', region_name => 'main::a' }, { region_id => 'z', region_name => 'other::z' });
    for my $name ('a', 'main::a') {
        my $ok = $d3->dispatch_i64(entrypoint => 'e.pl', region_name => $name, left => 20, right => 22);
        is($ok->{status}, 'native', "native dispatch via $name");
        is($ok->{result}{value}, 42, 'native value');
        ok($ok->{aot_plan}, 'aot plan attached');
    }
    my $ok_no_name = $d3->dispatch_i64(entrypoint => 'e.pl', left => 1, right => 1);
    is($ok_no_name->{status}, 'native', 'native dispatch without a requested region');
    is($ok_no_name->{result}{value}, 2, 'second native value');
    my $report = $d3->profile_report;
    my ($a) = grep { $_->{region} eq 'main::a' } @{ $report->{regions} };
    ok($a->{native} >= 3, 'native dispatches recorded');
    ok($a->{hot}, 'region became hot');

    # Unit without a name uses the requested region name and falls back to its id.
    %guard = (n => $native_guard);
    %artifact = (n => { entry_kind => 'native_i64_leaf', executable_path => $adder });
    @ssa = ({ region_id => 'n' });
    my $named = PAX::RuntimeDispatcher->new->dispatch_i64(entrypoint => 'e.pl');
    is($named->{status}, 'native', 'unnamed unit dispatches by id');
    is($named->{inline_cache}{update}{site} // 'main-dispatch', 'main-dispatch', 'default cache site');

    # Units lacking names: matched by an empty requested name, or identified by a false id.
    %guard = (q => $deopt_guard, 0 => $deopt_guard);
    @ssa = ({ region_id => 'q' });
    my $emptyname = PAX::RuntimeDispatcher->new->dispatch_i64(entrypoint => 'e.pl', region_name => '');
    is($emptyname->{attempts}[0]{region_id}, 'q', 'empty requested name matches a nameless unit');
    @ssa = ({ region_id => 0 });
    my $falseid = PAX::RuntimeDispatcher->new->dispatch_i64(entrypoint => 'e.pl');
    is($falseid->{attempts}[0]{region_id}, 0, 'false region id is used as the method');

    # Collaborator constructors returning false values.
    {
        local *PAX::ProfileStore::new = sub { 0 };
        local *PAX::InlineCache::new = sub { 0 };
        local *PAX::HotRegionJIT::new = sub { 0 };
        local *PAX::OSR::new = sub { 0 };
        local *PAX::ProfileGuidedAOT::new = sub { 0 };
        my $hollow = PAX::RuntimeDispatcher->new;
        is_deeply([ map { $hollow->{$_} } qw(profile_store inline_cache hot_region_jit osr aot) ], [0, 0, 0, 0, 0], 'false collaborators are kept');
    }

    is_deeply(PAX::RuntimeDispatcher::_profile_by_region({}), {}, 'empty report maps to empty profile');
}

done_testing;
