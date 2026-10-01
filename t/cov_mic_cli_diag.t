use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP qw(decode_json);
use lib "$FindBin::Bin/../lib";

use PAX::CLI;

=pod

=head1 NAME

t/cov_mic_cli_diag.t - in-process tests for the internal CLI diagnostic commands

=head1 DESCRIPTION

Calls the internal diagnostic subcommands of PAX::CLI (capture, inspect, hir,
compile, bench, corpus, dispatch, profile, why-not, trace-guards, gatekeeper
and friends) directly with the capture, region and backend layers stubbed, and
checks option parsing, error returns, output and exit codes.

=head1 WHY IT EXISTS

The existing CLI tests only spawn bin/pax as a subprocess, which Devel::Cover
does not see, so none of these subcommands were ever measured.

=cut

my $tmp = tempdir('pax-cov-mic-cli-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# ----------------------------------------------------------------------- stubs
my %S;

# reset_state()
# Restores the default stub behaviour. Input: none. Output: none.
sub reset_state {
    %S = (
        capture => {
            status => 'ok', mode => 'live', source_entrypoint => 'e.pl',
            runtime => { config_version => '5.42.0', perl_version => 'v5.42.0', archname => 'x', config => {} },
            capture => { loaded_files => ['A.pm'], compile_phase_events => ['e'] },
            source_features => {},
        },
        selected => [
            { id => 'r1', name => 'main::add', source => { native_shape => 'leaf' }, required_epochs => ['package_symbols'] },
            { id => 'r2', name => 'main::other', source => {}, required_epochs => ['package_symbols', 'nonexistent_epoch'] },
            { id => 'r3', name => 'blocked_fn', lowering_status => 'blocked', reason => 'why', required_epochs => ['package_symbols'] },
            { id => 'r4', source => {} },
        ],
        dispatch_status => 'native',
        native_status => 'ok',
        diff_pass => 1,
        suite_passed => 1,
    );
    return;
}
reset_state();

{
    no warnings 'redefine';
    *PAX::Capture::capture = sub { return { %{ $S{capture} } } };
    *PAX::RegionSelector::select = sub { return $S{no_selected} ? {} : { selected => $S{selected}, rejected => ['rej'] } };
    *PAX::Tier1::compile = sub {
        my ($self, $unit) = @_;
        return { region_id => $unit->{region_id}, entry_kind => 'native_i64_leaf', status => 'native_artifact', executable_path => '/bin/true', reason => 'ok' }
            if ($unit->{region_name} // '') eq 'main::add';
        return { region_id => $unit->{region_id}, status => 'fallback', reason => 'unnamed' } if !defined $unit->{region_name};
        return { region_id => $unit->{region_id}, entry_kind => 'reference', status => 'fallback', reason => 'because' };
    };
    *PAX::GuardedSSA::build_all = sub {
        my ($self) = @_;
        return [{ region_id => 'u1', region_name => 'main::add', guards => [], deopt => {} }] if $S{statusless_ssa};
        return [map { $self->build_unit($_) } @{ $self->{hir_units} }];
    };
    *PAX::NativeRunner::run_i64_binary = sub { return { status => $S{native_status} } };
    *PAX::RuntimeDispatcher::dispatch_i64 = sub { return { status => $S{dispatch_status}, saw => { @_[1 .. $#_] } } };
    *PAX::Differential::compare_capture = sub { return { pass => $S{diff_pass} } };
    *PAX::Benchmark::run_runtime_benchmark = sub { return { benchmark => 1 } };
    *PAX::BenchmarkMatrix::run = sub { return { passed => $S{suite_passed} } };
    *PAX::Corpus::run = sub { return { passed => $S{suite_passed} } };
    *PAX::CoreSuite::run = sub { return { passed => $S{suite_passed} } };
    *PAX::CPANMatrix::run = sub { return { passed => $S{suite_passed} } };
    *PAX::Gatekeeper::sow01_report = sub { return { status => $S{suite_passed} ? 'passed' : 'not_passed' } };
}

# call($code)
# Runs code with STDOUT and STDERR captured. Input: code ref.
# Output: (return value, stdout, stderr).
sub call {
    my ($code) = @_;
    my ($out, $err) = ('', '');
    my $rc;
    {
        local *STDOUT;
        local *STDERR;
        open STDOUT, '>', \$out or die $!;
        open STDERR, '>', \$err or die $!;
        $rc = $code->();
    }
    return ($rc, $out, $err);
}

# cli($method, @args)
# Calls a PAX::CLI class method with captured output. Input: method and args.
# Output: (return value, stdout, stderr).
sub cli {
    my ($method, @args) = @_;
    return call(sub { PAX::CLI->$method(@args) });
}

# ----------------------------------------------------------- parsing contract
# Each spec: method, command word for messages, value options, whether a
# positional is accepted, and the "missing positional" message (if any).
my @specs = (
    { m => '_run_dispatch', val => [qw(--left --right --region)], pos => 1, none => 'run requires a Perl entrypoint' },
    { m => '_capture', val => [qw(--mode)], pos => 1, none => 'capture requires a Perl entrypoint' },
    { m => '_inspect', val => [qw(--mode)], pos => 1, none => 'inspect requires a Perl entrypoint' },
    { m => '_hir', val => [qw(--mode)], pos => 1, none => 'hir requires a Perl entrypoint' },
    { m => '_compile', val => [qw(--mode)], pos => 1, none => 'compile requires a Perl entrypoint' },
    { m => '_build_artifacts', val => [qw(--mode --operation-mode --cache-root)], pos => 1, none => 'build requires a Perl entrypoint' },
    { m => '_diff', val => [], pos => 1, none => 'diff requires a Perl entrypoint' },
    { m => '_bench', val => [qw(--iterations)], pos => 1, none => 'bench requires a Perl entrypoint' },
    { m => '_bench_matrix', val => [qw(--iterations)], pos => 1, none => 'bench-matrix requires a manifest path' },
    { m => '_run_native', val => [qw(--left --right --region)], pos => 1, none => 'run-native requires a Perl entrypoint' },
    { m => '_corpus', val => [], pos => 1, none => 'corpus requires a manifest path' },
    { m => '_core_suite', val => [], pos => 1, none => 'core-suite requires a manifest path' },
    { m => '_cpan_matrix', val => [], pos => 1, none => 'cpan-matrix requires a manifest path' },
    { m => '_dispatch', val => [qw(--left --right --region)], pos => 1, none => 'dispatch requires a Perl entrypoint' },
    { m => '_profile', val => [qw(--iterations --threshold --region)], pos => 1, none => 'profile requires a Perl entrypoint' },
    { m => '_why_not', val => [qw(--region)], pos => 1, none => 'why-not requires a Perl entrypoint' },
    { m => '_trace_guards', val => [qw(--region)], pos => 1, none => 'trace-guards requires a Perl entrypoint' },
    { m => '_gatekeeper', val => [], pos => 0 },
    { m => '_app_start', val => [qw(--name)], pos => 0, none => 'app-start requires --name' },
    { m => '_app_stop', val => [qw(--name)], pos => 0, none => 'app-stop requires --name' },
    { m => '_standalone_run', val => [qw(--name)], pos => 0, none => 'standalone-run requires --name', loose => 1 },
    { m => '_standalone_inspect', val => [qw(--name)], pos => 0, none => 'standalone-inspect requires --name' },
    { m => '_standalone_why_not', val => [qw(--name)], pos => 0, none => 'standalone-why-not requires --name' },
    { m => '_standalone_extract', val => [qw(--name --output)], pos => 0, none => 'standalone-extract requires --name' },
    { m => '_standalone_native_run', val => [qw(--name --region --left --right --invalidate)], pos => 0, none => 'standalone-native-run requires --name' },
    { m => '_app_build', val => [qw(--name --paxfile --lib --asset --asset-dir)], pos => 1, none => 'app-build requires a Perl entrypoint or paxfile.yml entrypoint', args => ['--no-paxfile'] },
);

for my $spec (@specs) {
    my $m = $spec->{m};
    for my $opt (@{ $spec->{val} }) {
        my ($rc, $out, $err) = cli($m, $opt);
        is($rc, 2, "$m $opt without value returns 2");
        is($err, "$opt requires a value\n", "$m $opt without value explains");
    }
    if (!$spec->{loose}) {
        my @first = $spec->{pos} ? ('first') : ();
        my ($rc, $out, $err) = cli($m, @first, 'surplus');
        is($rc, 2, "$m surplus argument returns 2");
        is($err, "unexpected argument: surplus\n", "$m surplus argument explained");
    }
    if ($spec->{none}) {
        my ($rc, $out, $err) = cli($m, @{ $spec->{args} // [] });
        is($rc, 2, "$m without its required input returns 2");
        like($err, qr/\A\Q$spec->{none}\E\n/, "$m names the missing input");
    }
}

# ------------------------------------------------------------------ run / help
{
    my ($rc, $out) = call(sub { PAX::CLI->run });
    is($rc, 0, 'no command shows help');
    like($out, qr/usage:\n  pax build/, 'help text');
    for my $word (qw(help --help -h)) {
        my ($r, $o) = call(sub { PAX::CLI->run($word) });
        is($r, 0, "$word shows help");
    }
    my ($r, $o, $e) = call(sub { PAX::CLI->run('bogus-command') });
    is($r, 2, 'unknown command');
    like($e, qr/unknown command: bogus-command/, 'unknown command message');
    ($r, $o, $e) = call(sub { PAX::CLI->run('-x') });
    is($r, 2, 'dash option is not a script');

    no warnings 'redefine';
    local *PAX::CLI::_run = sub { return 'ran:' . join(',', @_[1 .. $#_]) };
    local *PAX::CLI::_build = sub { return 'built:' . join(',', @_[1 .. $#_]) };
    is(PAX::CLI->run('run', 'a', 'b'), 'ran:a,b', 'run is routed');
    is(PAX::CLI->run('build', 'c'), 'built:c', 'build is routed');
}

# ---------------------------------------------------------- interpreter script
{
    is(PAX::CLI->_looks_like_interpreter_script(undef), 0, 'undef is not a script');
    is(PAX::CLI->_looks_like_interpreter_script(''), 0, 'empty is not a script');
    is(PAX::CLI->_looks_like_interpreter_script('-e'), 0, 'switch is not a script');
    is(PAX::CLI->_looks_like_interpreter_script(File::Spec->catfile($tmp, 'absent.pl')), 0, 'absent file is not a script');

    my $good = File::Spec->catfile($tmp, 'good.pl');
    open my $fh, '>', $good or die $!;
    print {$fh} "our \@seen = \@ARGV; 1;\n";
    close $fh;
    is(PAX::CLI->_looks_like_interpreter_script($good), 1, 'existing file is a script');
    my ($rc, $out, $err) = call(sub { PAX::CLI->run($good, 'one', 'two') });
    is($rc, 0, 'script runs through run');
    no warnings 'once';
    is_deeply(\@main::seen, ['one', 'two'], 'script saw its arguments');

    my $dies = File::Spec->catfile($tmp, 'dies.pl');
    open $fh, '>', $dies or die $!;
    print {$fh} "die qq{script exploded\\n};\n";
    close $fh;
    ($rc, $out, $err) = cli('_run_interpreter_script', $dies);
    is($rc, 255, 'failing script returns 255');
    like($err, qr/pax interpreter failed for .*dies\.pl: script exploded/, 'script error reported');

    my $quiet = File::Spec->catfile($tmp, 'quiet.pl');
    open $fh, '>', $quiet or die $!;
    print {$fh} "\$! = 0; \$@ = ''; undef;\n";
    close $fh;
    ($rc, $out, $err) = cli('_run_interpreter_script', $quiet);
    is($rc, 255, 'script returning undef returns 255');
    like($err, qr/pax interpreter failed for .*quiet\.pl: unknown interpreter failure/, 'undef-returning script reported');

    my $errno = File::Spec->catfile($tmp, 'errno.pl');
    open $fh, '>', $errno or die $!;
    print {$fh} "\$@ = ''; \$! = 2; undef;\n";
    close $fh;
    ($rc, $out, $err) = cli('_run_interpreter_script', $errno);
    is($rc, 255, 'script leaving errno returns 255');
    like($err, qr/errno\.pl: No such file or directory/, 'errno text reported');
}

# --------------------------------------------------------------- run-dispatch
{
    my ($rc, $out) = cli('_run_dispatch', '--left', '1', '--right', '2', '--region', 'r', '--compact', 'e.pl');
    is($rc, 0, 'run dispatch succeeds');
    my $d = decode_json($out);
    is($d->{command}, 'run', 'command recorded');
    is($d->{execution_model}, 'native', 'native model');
    unlike($out, qr/\n  /, 'compact output');
    $S{dispatch_status} = 'fallback';
    ($rc, $out) = cli('_run_dispatch', 'e.pl');
    is(decode_json($out)->{execution_model}, 'reference_fallback', 'fallback model');
    like($out, qr/\n  /, 'pretty output by default');
}

# ----------------------------------------------------- capture family
{
    my ($rc, $out) = cli('_capture', '--mode', 'hermetic', '--compact', 'e.pl');
    is($rc, 0, 'capture ok');
    is(decode_json($out)->{source_entrypoint}, 'e.pl', 'manifest printed');
    $S{capture}{status} = 'failed';
    ($rc) = cli('_capture', 'e.pl');
    is($rc, 1, 'capture failure exit code');
    $S{capture}{status} = 'ok';

    ($rc, $out) = cli('_inspect', '--mode', 'live', 'e.pl');
    is($rc, 0, 'inspect ok');
    like($out, qr/^baseline_match: true$/m, 'baseline matched');
    like($out, qr/^selected_regions: 4$/m, 'regions counted');
    $S{capture}{runtime}{config_version} = '5.38.0';
    $S{capture}{status} = 'failed';
    ($rc, $out) = cli('_inspect', 'e.pl');
    is($rc, 1, 'inspect failure exit code');
    like($out, qr/^baseline_match: false$/m, 'baseline mismatch');
    reset_state();

    ($rc, $out) = cli('_hir', '--mode', 'live', '--compact', 'e.pl');
    is($rc, 0, 'hir ok');
    is(scalar @{ decode_json($out)->{hir_units} }, 4, 'hir units printed');
    $S{capture}{status} = 'failed';
    is((cli('_hir', 'e.pl'))[0], 1, 'hir failure exit code');
    reset_state();

    ($rc, $out) = cli('_compile', '--mode', 'live', '--compact', 'e.pl');
    is($rc, 0, 'compile ok');
    is(scalar @{ decode_json($out)->{artifacts} }, 4, 'artifacts printed');
    $S{capture}{status} = 'failed';
    is((cli('_compile', 'e.pl'))[0], 1, 'compile failure exit code');
    reset_state();

    my $cache = File::Spec->catdir($tmp, 'cli-cache');
    ($rc, $out) = cli('_build_artifacts', '--mode', 'live', '--operation-mode', 'ci', '--cache-root', $cache, '--compact', 'e.pl');
    is($rc, 0, 'artifact build ok');
    my $built = decode_json($out);
    is($built->{operation_mode}, 'ci', 'operation mode recorded');
    is(scalar @{ $built->{written_artifacts} }, 4, 'artifacts written');
    ok(-f $built->{written_artifacts}[0]{path}, 'artifact file exists');
    $S{capture}{status} = 'failed';
    is((cli('_build_artifacts', '--cache-root', $cache, 'e.pl'))[0], 1, 'artifact build failure exit code');
    reset_state();
}

# --------------------------------------------------- diff, bench and suites
{
    my ($rc, $out) = cli('_diff', '--compact', 'e.pl');
    is($rc, 0, 'diff passes');
    $S{diff_pass} = 0;
    is((cli('_diff', 'e.pl'))[0], 1, 'diff failure');
    reset_state();

    ($rc, $out) = cli('_bench', '--iterations', '2', '--compact', 'e.pl');
    is($rc, 0, 'bench ok');
    is(decode_json($out)->{benchmark}, 1, 'bench output');

    for my $m (qw(_bench_matrix _corpus _core_suite _cpan_matrix)) {
        my @pre = $m eq '_bench_matrix' ? ('--iterations', '2') : ();
        ($rc, $out) = cli($m, @pre, '--compact', 'manifest.json');
        is($rc, 0, "$m passes");
        $S{suite_passed} = 0;
        is((cli($m, 'manifest.json'))[0], 1, "$m fails");
        reset_state();
    }

    ($rc, $out) = cli('_gatekeeper', '--compact');
    is($rc, 0, 'gatekeeper passes');
    like($out, qr/"status":"passed"/, 'gatekeeper report');
    $S{suite_passed} = 0;
    is((cli('_gatekeeper'))[0], 1, 'gatekeeper fails');
    reset_state();
}

# --------------------------------------------------- native run and dispatch
{
    my ($rc, $out) = cli('_run_native', '--left', '4', '--right', '5', '--region', 'main::add', '--compact', 'e.pl');
    is($rc, 0, 'run-native ok');
    is_deeply(decode_json($out)->{args}, [4, 5], 'args echoed');
    $S{native_status} = 'error';
    is((cli('_run_native', 'e.pl'))[0], 1, 'run-native failure');
    reset_state();
    $S{selected} = [{ id => 'r2', name => 'main::other', source => {} }];
    ($rc, $out) = cli('_run_native', '--compact', 'e.pl');
    is($rc, 1, 'run-native without native artifact');
    is(decode_json($out)->{status}, 'fallback', 'fallback reported');
    reset_state();

    ($rc, $out) = cli('_dispatch', '--left', '1', '--right', '2', '--region', 'r', '--compact', 'e.pl');
    is($rc, 0, 'dispatch native');
    $S{dispatch_status} = 'fallback';
    is((cli('_dispatch', 'e.pl'))[0], 1, 'dispatch fallback');
    reset_state();

    ($rc, $out) = cli('_profile', '--iterations', '2', '--threshold', '1', '--region', 'r', '--compact', 'e.pl');
    is($rc, 0, 'profile ok');
    my $p = decode_json($out);
    is(scalar @{ $p->{events} }, 2, 'profile events recorded');
    ok(exists $p->{inline_cache}, 'inline cache reported');
}

# ------------------------------------------------------------ why-not / guards
{
    my ($rc, $out) = cli('_why_not', '--compact', 'e.pl');
    is($rc, 0, 'why-not ok');
    my $w = decode_json($out);
    is(scalar @{ $w->{native_reasons} }, 4, 'every region explained');
    is(scalar @{ $w->{selected_regions} }, 4, 'every region selected');
    is($w->{summary}, 'because', 'fallback reason is the summary');
    $S{no_selected} = 1;
    ($rc, $out) = cli('_why_not', '--compact', 'e.pl');
    is(scalar @{ decode_json($out)->{selected_regions} }, 0, 'missing selection tolerated');
    reset_state();

    ($rc, $out) = cli('_why_not', '--region', 'add', 'e.pl');
    $w = decode_json($out);
    is(scalar @{ $w->{native_reasons} }, 1, 'region filter by short name');
    is($w->{native_reasons}[0]{region_name}, 'main::add', 'filtered region');
    is($w->{summary}, 'region is native-capable in the current SOW-01 implementation', 'native summary');
    ($rc, $out) = cli('_why_not', '--region', 'main::other', 'e.pl');
    is(scalar @{ decode_json($out)->{native_reasons} }, 1, 'region filter by full name');

    ($rc, $out) = cli('_trace_guards', '--compact', 'e.pl');
    is($rc, 0, 'trace-guards ok');
    my $t = decode_json($out);
    is(scalar @{ $t->{traces} }, 4, 'all regions traced');
    my %status = map { ($_->{region_id} => $_->{status}) } @{ $t->{traces} };
    is($status{r1}, 'native_allowed', 'guarded region allowed');
    is($status{r2}, 'deopt', 'missing epoch deopts');
    is($status{r3}, 'deopt', 'fallback region deopts');
    ($rc, $out) = cli('_trace_guards', '--region', 'add', 'e.pl');
    is(scalar @{ decode_json($out)->{traces} }, 1, 'trace region filter by short name');
    ($rc, $out) = cli('_trace_guards', '--region', 'main::add', 'e.pl');
    is(scalar @{ decode_json($out)->{traces} }, 1, 'trace region filter by full name');

    $S{statusless_ssa} = 1;
    ($rc, $out) = cli('_trace_guards', '--compact', 'e.pl');
    is(decode_json($out)->{traces}[0]{status}, 'native_allowed', 'unit without status is not a fallback');
    reset_state();

    my @pipe = PAX::CLI::_pipeline('e.pl');
    is(scalar @pipe, 5, 'pipeline returns every stage');
}

# ----------------------------------------------------------------- summaries
{
    my $m = { runtime => { baseline_match => 1 }, compatibility => { barriers => [] } };
    is(PAX::CLI::_why_not_summary({ runtime => {}, compatibility => {} }, [1], []), 'runtime baseline mismatch blocks native acceleration', 'mismatch summary');
    is(PAX::CLI::_why_not_summary({ runtime => { baseline_match => 1 }, compatibility => { barriers => ['b'] } }, [1], []), 'compatibility barriers require guarded or fallback execution', 'barrier summary');
    is(PAX::CLI::_why_not_summary({ runtime => { baseline_match => 1 }, compatibility => {} }, [], []), 'requested region was not selected', 'unselected summary');
    is(PAX::CLI::_why_not_summary($m, [1], [{ entry_kind => 'reference', reason => 'r' }]), 'r', 'fallback summary');
    is(PAX::CLI::_why_not_summary($m, [1], [{ entry_kind => 'native_i64_loop' }]), 'region is native-capable in the current SOW-01 implementation', 'native summary');
    is(PAX::CLI::_why_not_summary($m, [1], [{ reason => 'no kind' }]), 'no kind', 'missing entry kind counts as fallback');
}

# ------------------------------------------------------------- small helpers
{
    my ($rc, $out, $err) = call(sub { PAX::CLI::_missing('--x') });
    is($rc, 2, '_missing returns 2');
    is($err, "--x requires a value\n", '_missing message');
    like(PAX::CLI::_json({ b => 1, a => "\x{e9}" }, 0), qr/^\{"a":"\\u00e9","b":1\}$/, 'compact canonical ascii json');
    like(PAX::CLI::_json({ a => 1 }, 1), qr/\n   "a"/, 'pretty json');
    like(PAX::CLI::_usage(), qr/pax run/, 'usage text');
    like(PAX::CLI::_pax_bin(), qr{/pax$}, 'pax bin path');
}

done_testing;
