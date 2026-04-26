use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec;
use File::Path qw(make_path remove_tree);
use JSON::PP qw(decode_json);

my $pax = "$FindBin::Bin/../bin/pax";
my $fixture = "$FindBin::Bin/fixtures/compile_phase.pl";

my $json = `$^X $pax capture --compact $fixture`;
is($? >> 8, 0, 'pax capture exits successfully');

my $manifest = decode_json($json);
is($manifest->{capture}{status}, 'ok', 'manifest reports ok capture');
is($manifest->{runtime}{perl_family_target}, '5.42.x', 'manifest reports target baseline');
ok(exists $manifest->{runtime}{baseline_match}, 'manifest reports baseline match status');

my $inspect = `$^X $pax inspect $fixture`;
is($? >> 8, 0, 'pax inspect exits successfully');
like($inspect, qr/^entrypoint:/m, 'inspect prints entrypoint');
like($inspect, qr/^compatibility_level:/m, 'inspect prints compatibility level');
like($inspect, qr/^selected_regions:/m, 'inspect prints selected regions');

my $hir_json = `$^X $pax hir --compact $fixture`;
is($? >> 8, 0, 'pax hir exits successfully');
my $hir = decode_json($hir_json);
ok(@{ $hir->{regions}{selected} } >= 1, 'hir command reports selected regions');
ok(@{ $hir->{hir_units} } >= 1, 'hir command reports HIR units');

my $compile_json = `$^X $pax compile --compact $fixture`;
is($? >> 8, 0, 'pax compile exits successfully');
my $compile = decode_json($compile_json);
ok(@{ $compile->{ssa_units} } >= 1, 'compile command reports SSA units');
ok(@{ $compile->{artifacts} } >= 1, 'compile command reports artifacts');

my $sow03_root = "$FindBin::Bin/tmp-sow03";
remove_tree($sow03_root) if -d $sow03_root;
my $build_json = `$^X $pax build --compact --paxfile t/fixtures/paxfile.yml`;
is($? >> 8, 0, 'pax build exits successfully using paxfile defaults');
my $build = decode_json($build_json);
my $paxfile_binary = File::Spec->rel2abs('t/tmp-sow03/fixture-dashboard');
is($build->{status}, 'built', 'build command creates standalone binary');
is($build->{standalone}{output_path}, $paxfile_binary, 'build command honors paxfile output');
ok(-x $build->{standalone}{output_path}, 'build output binary is executable');

my $diff_json = `$^X $pax diff --compact $fixture`;
is($? >> 8, 0, 'pax diff exits successfully');
my $diff = decode_json($diff_json);
ok($diff->{pass}, 'diff command reports pass');

my $bench_json = `$^X $pax bench --compact --iterations 1 $fixture`;
is($? >> 8, 0, 'pax bench exits successfully');
my $bench = decode_json($bench_json);
is($bench->{iterations}, 1, 'bench command respects iteration count');
is($bench->{benchmark_class}, 'runtime', 'bench command reports runtime benchmark');
ok(exists $bench->{native_available}, 'bench command reports native availability');
ok(ref $bench->{memory_impact} eq 'HASH', 'bench command reports measured memory impact structure');

my $bench_matrix_json = `$^X $pax bench-matrix --compact --iterations 1 t/benchmark_matrix.json`;
is($? >> 8, 0, 'pax bench-matrix exits successfully');
my $bench_matrix = decode_json($bench_matrix_json);
ok($bench_matrix->{passed}, 'bench-matrix reports pass');
ok(@{ $bench_matrix->{classes} } >= 1, 'bench-matrix reports classes');

my $native_json = `$^X $pax run-native --compact --left 10 --right 32 $fixture`;
my $native_exit = $? >> 8;
my $native = decode_json($native_json);
if ($native->{status} && $native->{status} eq 'ok') {
    is($native_exit, 0, 'run-native exits successfully when native artifact is available');
    is($native->{result}{value}, 42, 'run-native returns native result');
} else {
    is($native_exit, 1, 'run-native reports fallback when native artifact is unavailable');
    is($native->{status}, 'fallback', 'run-native fallback status reported');
}

my $corpus_json = `$^X $pax corpus --compact t/corpus.json`;
is($? >> 8, 0, 'pax corpus exits successfully');
my $corpus = decode_json($corpus_json);
ok($corpus->{passed}, 'corpus command reports pass');
is($corpus->{total}, 5, 'corpus command reports total');

my $core_suite_json = `$^X $pax core-suite --compact t/perl_core_suite.json`;
is($? >> 8, 0, 'pax core-suite exits successfully');
my $core_suite = decode_json($core_suite_json);
ok($core_suite->{passed}, 'core-suite command reports pass');
ok($core_suite->{total} >= 1, 'core-suite reports total');

my $cpan_matrix_json = `$^X $pax cpan-matrix --compact t/cpan_matrix.json`;
is($? >> 8, 0, 'pax cpan-matrix exits successfully');
my $cpan_matrix = decode_json($cpan_matrix_json);
ok($cpan_matrix->{passed}, 'cpan-matrix command reports pass');
ok($cpan_matrix->{total} >= 1, 'cpan-matrix reports total');

my $dispatch_json = `$^X $pax dispatch --compact --left 10 --right 32 t/fixtures/simple.pl`;
my $dispatch_exit = $? >> 8;
my $dispatch = decode_json($dispatch_json);
ok($dispatch->{status}, 'dispatch command reports status');
if ($dispatch->{status} eq 'native') {
    is($dispatch_exit, 0, 'dispatch exits successfully for native execution');
    is($dispatch->{result}{value}, 42, 'dispatch reports native value');
} else {
    is($dispatch_exit, 1, 'dispatch exits fallback when native unavailable');
}

my $selected_dispatch_json = `$^X $pax dispatch --compact --region multiply --left 6 --right 7 t/fixtures/native_leafs.pl`;
my $selected_dispatch_exit = $? >> 8;
my $selected_dispatch = decode_json($selected_dispatch_json);
if ($selected_dispatch->{status} eq 'native') {
    is($selected_dispatch_exit, 0, 'selected dispatch exits successfully for native execution');
    is($selected_dispatch->{result}{value}, 42, 'selected dispatch reports native value');
} else {
    is($selected_dispatch_exit, 1, 'selected dispatch exits fallback when native unavailable');
}

my $profile_json = `$^X $pax profile --compact --iterations 2 --threshold 2 --region add t/fixtures/native_leafs.pl`;
is($? >> 8, 0, 'pax profile exits successfully');
my $profile = decode_json($profile_json);
is($profile->{threshold}, 2, 'profile threshold reported');
ok(@{ $profile->{regions} } >= 1, 'profile reports regions');

my $run_output = `$^X $pax run --paxfile t/fixtures/paxfile.yml -- status`;
is($? >> 8, 0, 'pax run exits successfully using paxfile defaults');
is($run_output, "slowload-ready\n", 'run command executes the built standalone binary');

my $override_binary = File::Spec->rel2abs("$sow03_root/override-binary");
my $override_build_json = `$^X $pax build --compact --paxfile t/fixtures/paxfile.yml -o $override_binary`;
is($? >> 8, 0, 'pax build accepts -o output override');
my $override_build = decode_json($override_build_json);
is($override_build->{standalone}{output_path}, $override_binary, 'build command records overridden output path');
ok(-x $override_binary, 'overridden build output is executable');

my $override_run_output = `$^X $pax run --paxfile t/fixtures/paxfile.yml --output $override_binary -- asset`;
is($? >> 8, 0, 'pax run accepts --output override');
is($override_run_output, "embedded-dashboard-asset\n", 'run command executes binary with embedded asset');

my $workdir = "$sow03_root/work";
make_path($workdir);
my $no_arg_binary = "$sow03_root/no-arg-binary";
open my $pfh, '>', "$workdir/paxfile.yml" or die "cannot write test paxfile: $!";
print {$pfh} join("\n",
    "name: no-arg-fixture",
    "entrypoint: $FindBin::Bin/fixtures/app_entry.pl",
    "output: $no_arg_binary",
    "libs:",
    "  - $FindBin::Bin/fixtures/app_lib",
    "assets:",
    "  - $FindBin::Bin/fixtures/app_assets/banner.txt",
    "",
);
close $pfh or die "cannot close test paxfile: $!";
my $no_arg_build_json = `cd $workdir && $^X $pax build --compact`;
is($? >> 8, 0, 'pax build with no arguments reads local paxfile.yml');
my $no_arg_build = decode_json($no_arg_build_json);
is($no_arg_build->{standalone}{output_path}, $no_arg_binary, 'no-argument build honors paxfile output');
ok(-x $no_arg_binary, 'no-argument build output is executable');
my $no_arg_run_output = `cd $workdir && $^X $pax run -- status`;
is($? >> 8, 0, 'pax run with no build arguments reads local paxfile.yml');
is($no_arg_run_output, "slowload-ready\n", 'no-argument run executes built standalone binary');

my $why_not_json = `$^X $pax why-not --compact --region add t/fixtures/native_leafs.pl`;
is($? >> 8, 0, 'pax why-not exits successfully');
my $why_not = decode_json($why_not_json);
is($why_not->{command}, 'why-not', 'why-not reports command name');
ok($why_not->{summary}, 'why-not reports summary');
ok(exists $why_not->{compatibility}, 'why-not reports compatibility');

my $trace_json = `$^X $pax trace-guards --compact --region add t/fixtures/native_leafs.pl`;
is($? >> 8, 0, 'pax trace-guards exits successfully');
my $trace = decode_json($trace_json);
is($trace->{command}, 'trace-guards', 'trace-guards reports command name');
ok(@{ $trace->{traces} } >= 1, 'trace-guards reports guard traces');

my $gatekeeper_json = `$^X $pax gatekeeper --compact`;
is($? >> 8, 0, 'pax gatekeeper exits successfully when SOW checks pass');
my $gatekeeper = decode_json($gatekeeper_json);
is($gatekeeper->{sow}, 'SOW-01', 'gatekeeper reports SOW-01');
is($gatekeeper->{status}, 'passed', 'gatekeeper reports passed when real implementation checks are closed');
is($gatekeeper->{blocked}, 0, 'gatekeeper reports no blocked real-implementation checks');

done_testing;
