use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::Gatekeeper;

=pod

=head1 NAME

t/cov_mic_gatekeeper.t - branch coverage for the SOW gatekeeper checks

=head1 DESCRIPTION

Builds throw-away project roots that either satisfy or violate each
PAX::Gatekeeper check, with the heavy capture, benchmark and matrix runners
stubbed, and asserts the status and evidence of every check in both directions.

=head1 WHY IT EXISTS

PAX::Gatekeeper was never loaded under Devel::Cover; each check is a bundle of
file-presence and regex conditions that need both outcomes exercised.

=cut

my $tmp = tempdir('pax-cov-mic-gk-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $counter = 0;

# good_files()
# Describes a project tree that satisfies every check.
# Input: none. Output: hash of relative path to file content.
sub good_files {
    my $docs = 'projects/sow-01-project-pax';
    my $cpan = join '', map { qq({"distribution":"d$_","declared_xs":[],"note":"Level A installed-xs-backed-cpan"}\n) } 1 .. 25;
    return (
        'project/SOW-01.pdf' => 'pdf',
        'project/SOW-02.pdf' => 'pdf',
        'project/BACKLOG.md' => "| SOW-01 |\n| SOW-02 |\n",
        'Dockerfile' => "FROM perl:5.42.0\n",
        'lib/PAX/CLI.pm' => "if (\$command eq 'build') {}\nif (\$command eq 'run') {}\n--asset --asset-dir --paxfile --no-paxfile core-suite cpan-matrix bench-matrix\n",
        't/cli.t' => '1',
        't/corpus.json' => '{}',
        't/benchmark_matrix.json' => '{}',
        't/cpan_matrix.json' => $cpan,
        "$docs/epic-06-validation-benchmarking-delivery/perl-core-suite-report.md" => 'ok',
        "$docs/epic-06-validation-benchmarking-delivery/cpan-matrix-report.md" => 'ok',
        'lib/PAX/Manifest.pm' => "lexical_pads closure_descriptors method_resolution regex_metadata compile_phase_events\n",
        'lib/PAX/Capture.pm' => 'pad_layout closure_descriptor',
        'lib/PAX/HIR.pm' => '$x->{source}{native_shape}',
        'lib/PAX/RegionSelector.pm' => 'native_shape',
        'lib/PAX/Tier1.pm' => 'Cranelift lowering',
        'lib/PAX/Backend/Tier2LLVM.pm' => 'LLVM emit',
        'lib/PAX/HotRegionJIT.pm' => '1',
        'lib/PAX/ProfileGuidedAOT.pm' => '1',
        'lib/PAX/OSR.pm' => '1',
        'lib/PAX/InlineCache.pm' => '1',
        'lib/PAX/DeoptEngine.pm' => 'argv wantarray lexicals closure_environment exception_handlers exception_state caller debugger_stack',
        'lib/PAX/AppImage.pm' => 'pax_assets PAX_EMBEDDED_ASSET_ROOT',
        'lib/PAX/AppServer.pm' => '1',
        'lib/PAX/Paxfile.pm' => '1',
        'paxfile.yml' => 'x: 1',
        't/app_image.t' => '1',
        't/fixtures/app_assets/banner.txt' => 'banner',
        'DOCKER.md' => 'clean',
        "$docs/SOW.md" => 'clean',
        "$docs/implementation-status.md" => 'clean',
        "$docs/sow-alignment-report.md" => 'clean',
        "$docs/sow-gatekeeper-report.md" => 'clean',
    );
}

# mkroot(%override)
# Materialises the good tree in a fresh directory with overrides applied;
# an undef override removes the file. Input: overrides. Output: the new root.
sub mkroot {
    my (%override) = @_;
    my %files = (good_files(), %override);
    my $root = File::Spec->catdir($tmp, 'root' . ++$counter);
    make_path($root);
    for my $rel (sort keys %files) {
        next if !defined $files{$rel};
        my $path = File::Spec->catfile($root, split m{/}, $rel);
        my ($vol, $dir) = File::Spec->splitpath($path);
        make_path($dir);
        open my $fh, '>', $path or die "$path: $!";
        print {$fh} $files{$rel};
        close $fh;
    }
    return $root;
}

# gate($root, $method)
# Runs one gatekeeper check against a root. Input: root and method name.
# Output: the check hashref.
sub gate {
    my ($root, $method) = @_;
    return PAX::Gatekeeper->new(root => $root)->$method;
}

is(PAX::Gatekeeper->new->{root}, '.', 'root defaults to the current directory');

my $good = mkroot();
my $empty = mkroot(map { $_ => undef } keys %{ { good_files() } });

# ------------------------------------------------------------- file presence
{
    my $gk = PAX::Gatekeeper->new(root => $good);
    is($gk->_check_no_path('i', 'nothing/here', 'd')->{status}, 'passed', 'absent path passes');
    is($gk->_check_no_path('i', 'Dockerfile', 'd')->{status}, 'blocked', 'present path blocks');
    is($gk->_check_test_file('i', 'Dockerfile', 'd')->{status}, 'passed', 'present test file');
    is($gk->_check_test_file('i', 'nope', 'd')->{status}, 'blocked', 'absent test file');
}

# ------------------------------------------------------------ simple content checks
is(gate($good, '_check_backlog_approved_sows')->{status}, 'passed', 'backlog ok');
is(gate(mkroot('project/BACKLOG.md' => "| SOW-01 |\n"), '_check_backlog_approved_sows')->{status}, 'blocked', 'backlog missing SOW-02');
is(gate(mkroot('project/BACKLOG.md' => "| SOW-02 |\n"), '_check_backlog_approved_sows')->{status}, 'blocked', 'backlog missing SOW-01');
is(gate(mkroot('project/BACKLOG.md' => "| SOW-01 |\n| SOW-02 |\n| SOW-03 |\n"), '_check_backlog_approved_sows')->{status}, 'blocked', 'backlog has SOW-03');

is(gate($good, '_check_docker_pin')->{status}, 'passed', 'docker pinned');
is(gate(mkroot('Dockerfile' => "FROM perl:5.40\n"), '_check_docker_pin')->{status}, 'blocked', 'docker unpinned');

is(gate($good, '_check_cli_surface')->{status}, 'passed', 'cli surface ok');
my $nobuild = gate(mkroot('lib/PAX/CLI.pm' => "if (\$command eq 'run') {}\n"), '_check_cli_surface');
is($nobuild->{evidence}, 'missing: build', 'missing build reported');
my $extra = gate(mkroot('lib/PAX/CLI.pm' => "if (\$command eq 'build') {}\nif (\$command eq 'run') {}\nif (\$command eq 'capture') {}\n"), '_check_cli_surface');
is($extra->{evidence}, 'extra: capture', 'extra command reported');
is($extra->{status}, 'blocked', 'extra command blocks');

is(gate($good, '_check_benchmark_matrix_command')->{status}, 'passed', 'bench-matrix wired');
is(gate($empty, '_check_benchmark_matrix_command')->{status}, 'blocked', 'bench-matrix missing');

is(gate($good, '_check_core_suite')->{status}, 'passed', 'core suite recorded');
is(gate(mkroot('lib/PAX/CLI.pm' => 'x'), '_check_core_suite')->{status}, 'blocked', 'core suite not wired');
is(gate(mkroot('projects/sow-01-project-pax/epic-06-validation-benchmarking-delivery/perl-core-suite-report.md' => undef), '_check_core_suite')->{status}, 'blocked', 'core suite report missing');
is(gate($good, '_check_cpan_matrix')->{status}, 'passed', 'cpan matrix recorded');
is(gate(mkroot('lib/PAX/CLI.pm' => 'x'), '_check_cpan_matrix')->{status}, 'blocked', 'cpan matrix not wired');
is(gate(mkroot('projects/sow-01-project-pax/epic-06-validation-benchmarking-delivery/cpan-matrix-report.md' => undef), '_check_cpan_matrix')->{status}, 'blocked', 'cpan report missing');

is(gate($good, '_check_broad_cpan_xs_matrix')->{status}, 'passed', 'broad matrix ok');
is(gate(mkroot('t/cpan_matrix.json' => qq({"distribution":"a"}\n) x 7), '_check_broad_cpan_xs_matrix')->{status}, 'blocked', 'no xs marker');
is(gate(mkroot('t/cpan_matrix.json' => 'installed-xs-backed-cpan'), '_check_broad_cpan_xs_matrix')->{status}, 'blocked', 'too few distributions');

is(gate($good, '_check_deopt_frame_fields')->{status}, 'passed', 'deopt fields ok');
like(gate(mkroot('lib/PAX/DeoptEngine.pm' => 'argv'), '_check_deopt_frame_fields')->{evidence}, qr/^missing: wantarray/, 'deopt fields missing');

# ------------------------------------------------------------ backend and jit checks
is(gate($good, '_check_real_backend_integration')->{status}, 'passed', 'backend integration ok');
is(gate(mkroot('lib/PAX/Tier1.pm' => 'Cranelift rustc'), '_check_real_backend_integration')->{evidence}, 'missing: real_cranelift_backend', 'rustc tier1');
is(gate(mkroot('lib/PAX/Tier1.pm' => 'nothing'), '_check_real_backend_integration')->{status}, 'blocked', 'tier1 without cranelift');
is(gate(mkroot('lib/PAX/Backend/Tier2LLVM.pm' => 'emit'), '_check_real_backend_integration')->{evidence}, 'missing: real_llvm_codegen', 'tier2 without LLVM');
is(gate(mkroot('lib/PAX/Backend/Tier2LLVM.pm' => 'LLVM'), '_check_real_backend_integration')->{evidence}, 'missing: real_llvm_codegen', 'tier2 without codegen word');

is(gate($good, '_check_real_hot_region_jit_aot')->{status}, 'passed', 'jit/aot ok');
is(gate($empty, '_check_real_hot_region_jit_aot')->{evidence}, 'missing: hot_region_jit_runtime, profile_guided_aot_runtime, osr_runtime, inline_cache_runtime', 'jit/aot all missing');

is(gate($good, '_check_real_cpan_xs_coverage')->{status}, 'passed', 'cpan xs coverage ok');
is(gate($empty, '_check_real_cpan_xs_coverage')->{evidence}, 'missing: broad_distribution_count, declared_xs_metadata, level_a_to_d_coverage', 'cpan xs coverage all missing');

# ------------------------------------------------------------ app image
is(gate($good, '_check_whole_program_app_image')->{status}, 'passed', 'app image ok');
is(gate($empty, '_check_whole_program_app_image')->{evidence},
    'missing: app_image_builder, app_server_runtime, paxfile_loader, project_paxfile, app_image_test, embedded_asset_fixture, public_build_command, public_run_command, asset_build_flags, paxfile_cli_flags, asset_embedding_runtime',
    'app image all missing');
is(gate(mkroot('lib/PAX/CLI.pm' => "if (\$command eq 'build') {}\nif (\$command eq 'run') {}\n--asset --paxfile --no-paxfile"), '_check_whole_program_app_image')->{evidence}, 'missing: asset_build_flags', 'asset-dir flag missing');
is(gate(mkroot('lib/PAX/CLI.pm' => "if (\$command eq 'build') {}\nif (\$command eq 'run') {}\n--asset --asset-dir --paxfile"), '_check_whole_program_app_image')->{evidence}, 'missing: paxfile_cli_flags', 'no-paxfile flag missing');
is(gate(mkroot('lib/PAX/CLI.pm' => "if (\$command eq 'build') {}\nif (\$command eq 'run') {}\n--asset-dir --paxfile --no-paxfile"), '_check_whole_program_app_image')->{status}, 'passed', 'asset flag satisfied by asset-dir');
is(gate(mkroot('lib/PAX/CLI.pm' => "if (\$command eq 'build') {}\nif (\$command eq 'run') {}\n--asset --asset-dir --no-paxfile"), '_check_whole_program_app_image')->{evidence}, 'missing: paxfile_cli_flags', 'paxfile flag missing');
is(gate(mkroot('lib/PAX/AppImage.pm' => 'pax_assets'), '_check_whole_program_app_image')->{evidence}, 'missing: asset_embedding_runtime', 'embedded root missing');

# ------------------------------------------------------------ docs
is(gate($good, '_check_current_docs_no_gap_language')->{status}, 'passed', 'docs clean');
my $gap = gate(mkroot('DOCKER.md' => 'this is a Placeholder'), '_check_current_docs_no_gap_language');
is($gap->{evidence}, 'gap language in: DOCKER.md', 'gap language found');
is($gap->{status}, 'blocked', 'gap language blocks');

# ------------------------------------------------------------ slurp
{
    my $dir = File::Spec->catdir($tmp, 'adir');
    make_path($dir);
    is(PAX::Gatekeeper::_slurp($dir), '', 'unreadable (directory) path slurps as empty');
    is(PAX::Gatekeeper::_slurp(File::Spec->catfile($tmp, 'absent')), '', 'missing file slurps as empty');
    is(PAX::Gatekeeper::_slurp(File::Spec->catfile($good, 'Dockerfile')), "FROM perl:5.42.0\n", 'file slurps');
}

# ------------------------------------------------------------ stubbed pipeline checks
my %captured = (
    status => 'ok',
    runtime => { config_version => '5.42.0' },
    capture => {
        compile_phase_events => ['BEGIN'],
        method_resolution => { A => ['B'] },
        sub_optrees => [{ name => 'f', pad_layout => { a => 1 }, closure_descriptor => { c => 1 } }],
    },
);
my $capture_stub = \%captured;
my @selected = ({ id => 'r', name => 'n', source => { native_shape => 'loop', optree_ops => ['add'] } });
my $selector_stub = \@selected;
my $benchmark_stub = { memory_impact => { delta_rss_kb => 1 } };
my $benchmark_dies = 0;
my %run_results = (core => { passed => 1 }, corpus => { passed => 1 }, cpan => { passed => 1 }, bench => { passed => 1 });
my %run_dies;
my $profile_report;

{
    no warnings 'redefine';
    local *PAX::Capture::capture = sub { die "capture boom\n" if $capture_stub && $capture_stub->{die}; return $capture_stub };
    local *PAX::RegionSelector::select = sub { die "select boom\n" if !$selector_stub; return { selected => $selector_stub } };
    local *PAX::Benchmark::run_runtime_benchmark = sub { die "bench boom\n" if $benchmark_dies; return $benchmark_stub };
    local *PAX::CoreSuite::run = sub { die "core boom\n" if $run_dies{core}; return $run_results{core} };
    local *PAX::Corpus::run = sub { die "corpus boom\n" if $run_dies{corpus}; return $run_results{corpus} };
    local *PAX::CPANMatrix::run = sub { return $run_results{cpan} };
    local *PAX::BenchmarkMatrix::run = sub { return $run_results{bench} };

    # semantic snapshot capture
    is(gate($good, '_check_semantic_snapshot_capture')->{status}, 'passed', 'snapshot capture ok');
    $capture_stub = { die => 1 };
    my $dead = gate($good, '_check_semantic_snapshot_capture');
    like($dead->{evidence}, qr/executable_capture, compile_phase_events, lexical_pads, closure_descriptors, method_resolution/, 'dying capture fails everything');
    $capture_stub = { status => 'ok', runtime => {}, capture => {} };
    my $bare = gate($good, '_check_semantic_snapshot_capture');
    is($bare->{evidence}, 'missing: compile_phase_events, lexical_pads, closure_descriptors, method_resolution', 'empty capture lacks the details');
    $capture_stub = { status => 'failed', runtime => {}, capture => {} };
    like(gate($good, '_check_semantic_snapshot_capture')->{evidence}, qr/^missing: executable_capture/, 'failed capture status');
    $capture_stub = { status => 'ok', runtime => {}, capture => { compile_phase_events => ['x'], method_resolution => { a => 1 },
        sub_optrees => [{ name => 'f', pad_layout => 1, closure_descriptor => 1 }] } };
    is(gate($good, '_check_semantic_snapshot_capture')->{status}, 'passed', 'capture with details passes');
    {
        local *PAX::Manifest::to_hash = sub { return { capture => {} } };
        is(gate($good, '_check_semantic_snapshot_capture')->{evidence}, 'missing: executable_capture, compile_phase_events, lexical_pads, closure_descriptors, method_resolution', 'snapshot without any sections');
    }
    {
        local *PAX::Manifest::to_hash = sub { return {} };
        like(gate($good, '_check_semantic_snapshot_capture')->{evidence}, qr/^missing: executable_capture/, 'snapshot without capture section');
    }
    {
        local *PAX::Manifest::to_hash = sub { return undef };
        like(gate($good, '_check_semantic_snapshot_capture')->{evidence}, qr/^missing: executable_capture, compile_phase_events/, 'undefined snapshot');
    }
    $capture_stub = \%captured;
    is(gate(mkroot('lib/PAX/Manifest.pm' => 'x', 'lib/PAX/Capture.pm' => 'y'), '_check_semantic_snapshot_capture')->{evidence},
        'missing: lexical_pads, closure_descriptors, method_resolution, regex_metadata, compile_phase_events, pad_layout, closure_descriptor',
        'source lacks the snapshot fields');

    # HIR lowering
    is(gate($good, '_check_optree_derived_hir_lowering')->{status}, 'passed', 'hir lowering ok');
    is(gate(mkroot('lib/PAX/HIR.pm' => 'nothing'), '_check_optree_derived_hir_lowering')->{status}, 'blocked', 'hir without manifest shape');
    is(gate(mkroot('lib/PAX/RegionSelector.pm' => 'nothing'), '_check_optree_derived_hir_lowering')->{status}, 'blocked', 'selector without native shape');
    is(gate(mkroot('lib/PAX/HIR.pm' => '$x->{source}{native_shape} open my $fh'), '_check_optree_derived_hir_lowering')->{status}, 'blocked', 'hir reading source via open');
    is(gate(mkroot('lib/PAX/HIR.pm' => '$x->{source}{native_shape} _slurp'), '_check_optree_derived_hir_lowering')->{status}, 'blocked', 'hir reading source via slurp');
    $selector_stub = [{ id => 'r', name => 'n', source => { native_shape => 'loop' } }];
    is(gate($good, '_check_optree_derived_hir_lowering')->{status}, 'blocked', 'no optree ops');
    $selector_stub = [{ id => 'r', name => 'n', source => {} }];
    is(gate($good, '_check_optree_derived_hir_lowering')->{status}, 'blocked', 'no native shape');
    $selector_stub = undef;
    is(gate($good, '_check_optree_derived_hir_lowering')->{status}, 'blocked', 'selector dies');
    $selector_stub = \@selected;

    # performance observability
    is(gate($good, '_check_performance_observability_fields')->{status}, 'passed', 'observability ok');
    $benchmark_dies = 1;
    like(gate($good, '_check_performance_observability_fields')->{evidence}, qr/^missing: benchmark_memory_impact, benchmark_memory_delta/, 'bench dies');
    $benchmark_dies = 0;
    $benchmark_stub = undef;
    like(gate($good, '_check_performance_observability_fields')->{evidence}, qr/benchmark_memory_impact, benchmark_memory_delta/, 'no bench result');
    $benchmark_stub = {};
    is(gate($good, '_check_performance_observability_fields')->{evidence}, 'missing: benchmark_memory_impact, benchmark_memory_delta', 'bench without memory impact');
    $benchmark_stub = { memory_impact => {} };
    is(gate($good, '_check_performance_observability_fields')->{evidence}, 'missing: benchmark_memory_delta', 'no rss delta');
    $benchmark_stub = { memory_impact => { delta_rss_kb => 1 } };
    {
        local *PAX::ProfileStore::report = sub { return { regions => [] } };
        is(gate($good, '_check_performance_observability_fields')->{evidence}, 'missing: osr_promotion_events, osr_retirement_events', 'no profiled region');
    }
    {
        local *PAX::ProfileStore::report = sub { return { regions => [{}] } };
        is(gate($good, '_check_performance_observability_fields')->{evidence}, 'missing: osr_promotion_events, osr_retirement_events', 'region without osr counts');
    }
    {
        local *PAX::ProfileStore::report = sub { return { regions => [{ osr_promotions => 1, osr_retirements => 1 }] } };
        is(gate($good, '_check_performance_observability_fields')->{status}, 'passed', 'region with osr counts');
    }

    # tiered backends
    is(gate($good, '_check_tiered_backend_architecture')->{status}, 'passed', 'tiers ok');
    {
        local *PAX::Backend::Tier1CraneliftEquivalent::metadata = sub { die 'x' };
        local *PAX::Backend::Tier2LLVM::metadata = sub { die 'x' };
        is(gate($good, '_check_tiered_backend_architecture')->{evidence}, 'missing: tier1, tier2, tier1_name, tier2_enabled', 'dying backends');
    }
    {
        local *PAX::Backend::Tier1CraneliftEquivalent::metadata = sub { { tier => 2, name => 'prototype backend' } };
        local *PAX::Backend::Tier2LLVM::metadata = sub { { tier => 1, status => 'disabled' } };
        is(gate($good, '_check_tiered_backend_architecture')->{evidence}, 'missing: tier1, tier2, tier1_name, tier2_enabled', 'wrong backend metadata');
    }
    {
        local *PAX::Backend::Tier1CraneliftEquivalent::metadata = sub { {} };
        local *PAX::Backend::Tier2LLVM::metadata = sub { {} };
        is(gate($good, '_check_tiered_backend_architecture')->{evidence}, 'missing: tier1, tier2, tier2_enabled', 'metadata without tier numbers');
    }

    # validation matrix
    is(gate($good, '_check_validation_matrix')->{status}, 'passed', 'validation matrix ok');
    $run_dies{core} = 1;
    is(gate($good, '_check_validation_matrix')->{evidence}, "core-suite: core boom\n", 'dying suite reported with error');
    $run_dies{core} = 0;
    $run_results{corpus} = undef;
    is(gate($good, '_check_validation_matrix')->{evidence}, 'corpus', 'undef result reported by name');
    $run_results{corpus} = { passed => 1 };
    $run_results{cpan} = { passed => 0 };
    $run_results{bench} = { passed => 0 };
    is(gate($good, '_check_validation_matrix')->{evidence}, 'cpan-matrix; bench-matrix', 'failed suites listed');
    $run_results{cpan} = { passed => 1 };
    $run_results{bench} = { passed => 1 };

    # full report
    my $report = PAX::Gatekeeper->new(root => $good)->sow01_report;
    is($report->{status}, 'passed', 'good root passes the whole gate');
    is($report->{blocked}, 0, 'nothing blocked');
    is($report->{passed}, scalar @{ $report->{checks} }, 'all checks passed');
    my $bad = PAX::Gatekeeper->new(root => $empty)->sow01_report;
    is($bad->{status}, 'not_passed', 'empty root does not pass');
    ok($bad->{blocked} > 0, 'blocked checks counted');
}

done_testing;
