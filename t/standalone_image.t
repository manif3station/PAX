use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use File::Path qw(remove_tree make_path);
use File::Spec;
use FindBin;
use HTTP::Tiny;
use IO::Socket::INET;
use JSON::PP ();
use POSIX qw(WNOHANG);
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneImage;
use PAX::StandaloneDispatch;
use PAX::Paxfile;

=pod

=head1 NAME

t/standalone_image.t - standalone binary packaging acceptance tests

=head1 DESCRIPTION

This file validates the standalone image subsystem behind SOW-03 C<pax build>
and C<pax run>. Public command assertions use only C<build>; lower-level
inspection, extraction, and native dispatch behavior is covered through the
generated executable or internal Perl APIs.

=cut

my $suffix = $$;
my $tmp_base = File::Spec->catdir(File::Spec->tmpdir, "pax-standalone-test-$suffix");
my $root = File::Spec->catdir($tmp_base, 'root');
remove_tree($root) if -d $root;
local $ENV{PAX_STANDALONE_ROOT} = $root;

my $builder = PAX::StandaloneImage->new(root => $root);

sub _free_tcp_port {
    my $sock = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Proto => 'tcp',
        Listen => 1,
        ReuseAddr => 1,
    ) or die "cannot allocate test port: $!";
    my $port = $sock->sockport;
    close $sock;
    return $port;
}

my $built = $builder->build(
    name => 'fixture-standalone',
    entrypoint => "$FindBin::Bin/fixtures/app_entry.pl",
    lib_dirs => ["$FindBin::Bin/fixtures/app_lib"],
    cpanfiles => ["$FindBin::Bin/fixtures/standalone_policy.cpanfile"],
    assets => ["$FindBin::Bin/fixtures/app_assets/banner.txt"],
);

is($built->{status}, 'built', 'standalone image built');
ok(-f $built->{manifest_path}, 'manifest written');
ok(-x $built->{standalone}{output_path}, 'standalone executable built');
is($built->{standalone}{runtime}{app_server_required}, JSON::PP::false, 'standalone does not require app server');
is($built->{standalone}{runtime}{mode}, 'bundled_perl', 'bundled runtime is the default standalone mode');
ok(($built->{standalone}{runtime_payload_count} // 0) > 0, 'bundled runtime payloads are packaged');
is($built->{standalone}{asset_count}, 1, 'asset metadata recorded');
ok(@{ $built->{standalone}{code_units} } >= 2, 'entrypoint and lib code units packaged');
ok(($built->{standalone}{dependency_summary}{packaged_app} // 0) >= 2, 'dependency summary records packaged app modules');
ok(($built->{standalone}{dependency_summary}{bundled_xs} // 0) >= 1, 'dependency summary records bundled XS dependency');
ok((grep { ($_->{packaging} // '') eq 'compiled_dispatch_script_pcu_v1' && ($_->{unit_kind} // '') eq 'entrypoint' } @{ $built->{standalone}{code_units} }) >= 1, 'fixture entrypoint is packaged as dispatch script PCU');
ok((grep { (($_->{packaging} // '') eq 'compiled_pcu_v1' || ($_->{packaging} // '') eq 'hybrid_compiled_pcu_v1') && ($_->{package} // '') eq 'SlowLoad' } @{ $built->{standalone}{code_units} }) >= 1, 'supported library module is packaged as compiled PCU');
ok((grep { ($_->{packaging} // '') eq 'hybrid_compiled_pcu_v1' && ($_->{package} // '') eq 'HybridLoad' } @{ $built->{standalone}{code_units} }) >= 1, 'hybrid library module is packaged as hybrid PCU');
ok((grep { ($_->{packaging} // '') eq 'compiled_pcu_v1' && ($_->{package} // '') eq 'ResidualOnly' } @{ $built->{standalone}{code_units} }) >= 1, 'residual-only library module is packaged as compiled PCU');

my $binary = abs_path($built->{standalone}{output_path});
my $status = `env -i PATH=/nonexistent TMPDIR=/tmp $binary status`;
is($? >> 8, 0, 'standalone executable runs status command');
is($status, "slowload-ready\n", 'standalone executable runs without app server');

my $asset = `env -i PATH=/nonexistent TMPDIR=/tmp $binary asset`;
is($? >> 8, 0, 'standalone executable exposes embedded asset');
is($asset, "embedded-fixture-asset\n", 'embedded asset content matches source');

my $fake_runtime_root = File::Spec->catdir($tmp_base, 'fake-runtime-core');
my $fake_core_dir = File::Spec->catdir($fake_runtime_root, 'x86_64-linux-gnu', 'CORE');
make_path($fake_core_dir);
my $fake_libperl = File::Spec->catfile($fake_core_dir, 'libperl.so.999');
open my $libfh, '>:raw', $fake_libperl or die "cannot create fake libperl: $!";
print {$libfh} 'fake-libperl';
close $libfh;
my @fake_runtime_libs = PAX::StandaloneImage::_runtime_core_libs_from_inc_dirs([$fake_runtime_root]);
is(scalar(@fake_runtime_libs), 1, 'runtime lib discovery finds libperl in a synthetic CORE directory');
is($fake_runtime_libs[0], $fake_libperl, 'runtime lib discovery returns exact fake lib path');
{
    local @INC = ($fake_runtime_root, @INC);
    my $manifest = PAX::StandaloneImage::_runtime_manifest(
        mode => 'bundled_perl',
        dependencies => [],
        lib_dirs => [],
        code_units => [],
        exclude_dirs => [],
        app_namespace => '',
        app_legacy_namespace => '',
    );
    my @runtime_lib_payloads = grep { ($_->{unit_kind} // '') eq 'runtime_lib' } @{ $manifest->{payloads} // [] };
    ok((grep { ($_->{logical_path} // '') eq 'lib/libperl.so.999' } @runtime_lib_payloads), 'runtime_lib payload includes discovered libperl from runtime inc');
}

my $hybrid_fast = `env -i PATH=/nonexistent TMPDIR=/tmp $binary hybrid-fast`;
is($? >> 8, 0, 'standalone executable runs compiled hybrid sub without residual fallback');
is($hybrid_fast, "hybrid-fast\n", 'compiled hybrid sub returns expected result');

my $hybrid_slow = `env -i PATH=/nonexistent TMPDIR=/tmp $binary hybrid-slow`;
is($? >> 8, 0, 'standalone executable lazily loads residual hybrid source on unsupported sub');
is($hybrid_slow, "beta:alpha\n", 'residual hybrid sub returns expected result');

my $residual_only = `env -i PATH=/nonexistent TMPDIR=/tmp $binary residual-only`;
is($? >> 8, 0, 'standalone executable can run compiled residual-only module');
is($residual_only, "three two one\n", 'compiled split/reverse/join sub returns expected result');

my $inspect = `$binary --pax-standalone-inspect`;
is($? >> 8, 0, 'standalone executable exposes embedded manifest');
my $inspect_data = JSON::PP->new->decode($inspect);
is($inspect_data->{name}, 'fixture-standalone', 'inspect reports standalone name');
is($inspect_data->{runtime}{mode}, 'bundled_perl', 'inspect reports bundled runtime mode');
ok(exists $inspect_data->{dependency_summary}, 'inspect reports dependency summary');

my $native_built = $builder->build(
    name => 'fixture-native-standalone',
    entrypoint => "$FindBin::Bin/fixtures/native_leafs.pl",
    runtime_mode => 'host_perl',
);
is($native_built->{status}, 'built', 'native-capable standalone image built');
ok(($native_built->{standalone}{native_artifact_summary}{native_ready} // 0) >= 1, 'native-capable standalone packages native-ready artifact metadata');
ok(($native_built->{standalone}{native_payload_count} // 0) >= 1, 'native-capable standalone packages native payloads');
ok(@{ $native_built->{standalone}{native_dispatch} // [] } >= 1, 'native-capable standalone records native dispatch metadata');

my $auto_native = $builder->build(
    name => 'fixture-auto-native',
    entrypoint => "$FindBin::Bin/fixtures/auto_native_app.pl",
    lib_dirs => ["$FindBin::Bin/fixtures/app_lib"],
    runtime_mode => 'bundled_perl',
);
is($auto_native->{status}, 'built', 'auto-native standalone image built');
ok(($auto_native->{standalone}{native_artifact_summary}{native_ready} // 0) >= 1, 'auto-native standalone packages native-ready region');
ok((grep { ($_->{packaging} // '') eq 'compiled_pcu_v1' && ($_->{package} // '') eq 'AutoNativeMath' } @{ $auto_native->{standalone}{code_units} }) >= 1, 'auto-native standalone packages compiled PCU for module');

my $extract_dir = File::Spec->catdir($tmp_base, 'extract');
remove_tree($extract_dir) if -d $extract_dir;
system { $binary } $binary, '--pax-standalone-extract', $extract_dir;
is($? >> 8, 0, 'standalone-extract succeeds');
ok(-f "$extract_dir/code/entrypoint/app_entry.dispatch.json", 'standalone-extract writes packaged entrypoint dispatch unit');
ok(-f "$extract_dir/code/lib/app_lib/SlowLoad.pcu.json", 'standalone-extract writes compiled PCU payload');
ok(-f "$extract_dir/code/lib/app_lib/HybridLoad.pcu.json", 'standalone-extract writes hybrid PCU payload');
ok(-f "$extract_dir/runtime/bin/perl", 'standalone-extract writes bundled perl');
ok(-f "$extract_dir/assets/banner.txt", 'standalone-extract writes asset payload');

my $namespace_build = $builder->build(
    name => 'fixture-namespace-runtime',
    entrypoint => "$FindBin::Bin/fixtures/app_entry.pl",
    lib_dirs => ["$FindBin::Bin/fixtures/app_lib"],
    app_namespace => 'Acme::DashboardLike',
);
is($namespace_build->{status}, 'built', 'namespace-aware standalone image built');
my $namespace_binary = abs_path($namespace_build->{standalone}{output_path});
my $namespace_extract_dir = File::Spec->catdir($tmp_base, 'namespace-extract');
remove_tree($namespace_extract_dir) if -d $namespace_extract_dir;
system { $namespace_binary } $namespace_binary, '--pax-standalone-extract', $namespace_extract_dir;
is($? >> 8, 0, 'namespace-aware standalone-extract succeeds');
my @namespace_runtime_files = glob(File::Spec->catfile($namespace_extract_dir, 'runtime', 'inc', '*', 'PAX', 'StandaloneRuntime.pm'));
ok(@namespace_runtime_files == 1, 'namespace-aware extract contains helper StandaloneRuntime.pm');
if (@namespace_runtime_files) {
    open my $nsfh, '<:raw', $namespace_runtime_files[0] or die "cannot read namespace runtime helper: $!";
    local $/;
    my $namespace_runtime_source = <$nsfh> // '';
    close $nsfh;
    unlike($namespace_runtime_source, qr/Developer::Dashboard/, 'namespace-aware runtime helper no longer contains legacy namespace');
    unlike($namespace_runtime_source, qr/dashboard_entry_command|dashboard_file_|dashboard_subcommand_candidates|dashboard_complete/, 'namespace-aware runtime helper uses neutral app operation names');
    unlike($namespace_runtime_source, qr/DEVELOPER_DASHBOARD_(?:COMMAND|FILE_|RESULT_INLINE_MAX)/, 'namespace-aware runtime helper uses app-derived env names for command, file, and result helpers');
    like($namespace_runtime_source, qr/Acme::DashboardLike/, 'namespace-aware runtime helper is remapped to configured namespace');
}

my $paxfile = PAX::Paxfile->load("$FindBin::Bin/fixtures/paxfile.yml");
is($paxfile->{name}, 'fixture-app', 'existing paxfile fixture still parses');

remove_tree($root) if -d $root;
my $paxfile_output = `cd $FindBin::Bin/.. && PAX_STANDALONE_ROOT=$root $^X bin/pax build --compact --paxfile t/fixtures/paxfile.yml`;
is($? >> 8, 0, 'pax build reads defaults from paxfile');
my $paxfile_build = JSON::PP->new->decode($paxfile_output);
is($paxfile_build->{standalone}{name}, 'fixture-app', 'standalone build uses paxfile name');
is($paxfile_build->{standalone}{asset_count}, 1, 'standalone build uses paxfile assets');
is(($paxfile_build->{standalone}{app}{command} // ''), 'app_entry', 'standalone manifest records derived app command');
is(($paxfile_build->{standalone}{app}{entrypoint_fallback} // ''), 'app_entry', 'standalone manifest records app entrypoint fallback');

my $override_output = `cd $FindBin::Bin/.. && PAX_STANDALONE_ROOT=$root $^X bin/pax build --compact --paxfile t/fixtures/paxfile.yml --name override-standalone --runtime-mode bundled_perl --app-command pax-test-command --app-entrypoint-env TEST_PAX_ENTRYPOINT --app-entrypoint-fallback test-fallback t/fixtures/app_entry.pl`;
is($? >> 8, 0, 'pax build accepts CLI overrides');
my $override_build = JSON::PP->new->decode($override_output);
is($override_build->{standalone}{name}, 'override-standalone', 'CLI name overrides paxfile');
is($override_build->{standalone}{runtime}{mode}, 'bundled_perl', 'CLI runtime mode overrides paxfile');
is(($override_build->{standalone}{app}{command} // ''), 'pax-test-command', 'CLI app command override is captured');
is(($override_build->{standalone}{app}{entrypoint_env} // ''), 'TEST_PAX_ENTRYPOINT', 'CLI app entrypoint env is captured');
is(($override_build->{standalone}{app}{entrypoint_fallback} // ''), 'test-fallback', 'CLI app entrypoint fallback is captured');
my $custom_output = File::Spec->catfile($tmp_base, 'custom-output', 'standalone-custom.bin');
my $custom_output_build = `cd $FindBin::Bin/.. && PAX_STANDALONE_ROOT=$root $^X bin/pax build --compact --paxfile t/fixtures/paxfile.yml --name override-output -o $custom_output t/fixtures/app_entry.pl`;
is($? >> 8, 0, 'pax build accepts -o output override');
my $custom_output_build_data = JSON::PP->new->decode($custom_output_build);
is($custom_output_build_data->{standalone}{output_path} // '', $custom_output, 'pax build writes output_path as requested');
ok(-x $custom_output, 'custom output binary is executable');

my $inspect_cli_data = PAX::StandaloneImage->new(root => $root)->load(name => 'override-standalone');
is($inspect_cli_data->{name}, 'override-standalone', 'standalone-inspect manifest matches build');

my $why_not_data = PAX::StandaloneImage->new(root => $root)->load(name => 'override-standalone');
is($why_not_data->{name}, 'override-standalone', 'standalone-why-not identifies target image');

my $run_cli = `$override_build->{standalone}{output_path} status`;
is($? >> 8, 0, 'standalone executable runs directly');
is($run_cli, "slowload-ready\n", 'standalone-run output matches direct execution');

my $native_rebuilt = $builder->build(
    name => 'fixture-native-standalone',
    entrypoint => "$FindBin::Bin/fixtures/native_leafs.pl",
    runtime_mode => 'host_perl',
);
is($native_rebuilt->{status}, 'built', 'native standalone rebuilt after paxfile root reset');

my $auto_native_rebuilt = $builder->build(
    name => 'fixture-auto-native',
    entrypoint => "$FindBin::Bin/fixtures/auto_native_app.pl",
    lib_dirs => ["$FindBin::Bin/fixtures/app_lib"],
    runtime_mode => 'bundled_perl',
);
is($auto_native_rebuilt->{status}, 'built', 'auto-native standalone rebuilt after paxfile root reset');

my $native_run_data = PAX::StandaloneDispatch->new->run_i64(
    name => 'fixture-native-standalone',
    region_name => 'multiply',
    left => 6,
    right => 7,
);
is($native_run_data->{status}, 'native', 'standalone-native-run uses packaged native execution');
is($native_run_data->{result}{value}, 42, 'standalone-native-run returns native result');

my $deopt_data = PAX::StandaloneDispatch->new->run_i64(
    name => 'fixture-native-standalone',
    region_name => 'multiply',
    left => 6,
    right => 7,
    invalidate => ['package_symbols'],
);
is($deopt_data->{status}, 'deopt', 'standalone-native-run reports deopt when guard is invalidated');
is($deopt_data->{result}{value}, 42, 'standalone-native-run falls back through bundled perl and preserves result');

my $native_hit_log = File::Spec->catfile($tmp_base, 'native-hit.log');
unlink $native_hit_log if -f $native_hit_log;
my $auto_native_bin = abs_path($auto_native_rebuilt->{standalone}{output_path});
chmod 0700, $auto_native_bin if defined $auto_native_bin && -f $auto_native_bin;
my $auto_native_output = `env -i PATH=/nonexistent TMPDIR=/tmp PAX_STANDALONE_NATIVE_HIT_LOG=$native_hit_log $auto_native_bin`;
is($? >> 8, 0, 'standalone executable auto-native app runs');
is($auto_native_output, "42\n", 'auto-native standalone output matches expected result');
ok(-f $native_hit_log, 'auto-native standalone records native hit log');
my $native_hit_text = do {
    open my $fh, '<', $native_hit_log or die "cannot read $native_hit_log: $!";
    local $/;
    <$fh>;
};
like($native_hit_text, qr/AutoNativeMath::multiply/, 'auto-native standalone executes packaged native wrapper during normal run');

my $main_wrapped_root = File::Spec->catdir($tmp_base, 'main-wrapped-root');
remove_tree($main_wrapped_root) if -d $main_wrapped_root;
local $ENV{PAX_STANDALONE_ROOT} = $main_wrapped_root;
my $main_wrapped_builder = PAX::StandaloneImage->new(root => $main_wrapped_root);
my $main_wrapped = $main_wrapped_builder->build(
    name => 'main-wrapped',
    entrypoint => "$FindBin::Bin/fixtures/main_wrapped_app.pl",
    runtime_mode => 'bundled_perl',
);
is($main_wrapped->{status}, 'built', 'main-wrapped standalone image built');
my $main_wrapped_bin = abs_path($main_wrapped->{standalone}{output_path});
chmod 0700, $main_wrapped_bin if defined $main_wrapped_bin && -f $main_wrapped_bin;
my $main_wrapped_output = `$main_wrapped_bin version`;
is($? >> 8, 0, 'main-wrapped standalone executable runs');
is($main_wrapped_output, "0.2.0\n", 'main-wrapped standalone executes main(\@ARGV) entrypoint');

my $have_web_stack = eval {
    require Dancer2;
    require Starman::Server;
    require Template;
    1;
};
SKIP: {
    skip 'web stack modules not installed', 8 if !$have_web_stack;
    my $web_root = File::Spec->catdir($tmp_base, 'web-root');
    remove_tree($web_root) if -d $web_root;
    local $ENV{PAX_STANDALONE_ROOT} = $web_root;
    my $web_builder = PAX::StandaloneImage->new(root => $web_root);
    my $web_built = $web_builder->build(
        name => 'pax-webapp',
        entrypoint => "$FindBin::Bin/../examples/webapp/bin/pax-webapp",
        lib_dirs => ["$FindBin::Bin/../examples/webapp/lib"],
        cpanfiles => ["$FindBin::Bin/../examples/webapp/cpanfile"],
        asset_dirs => ["$FindBin::Bin/../examples/webapp/share"],
        runtime_mode => 'bundled_perl',
    );
    is($web_built->{status}, 'built', 'webapp standalone image built');
    my %web_deps = map { $_->{module} => $_ } @{ $web_built->{standalone}{dependencies} // [] };
    ok(($web_deps{'Dancer2'}{class} // '') =~ /^(?:bundled_pure_perl|compiled_dependency)$/, 'Dancer2 is packaged for standalone runtime');
    ok(($web_deps{'Starman::Server'}{class} // '') =~ /^(?:bundled_pure_perl|compiled_dependency)$/, 'Starman::Server is packaged for standalone runtime');
    ok(($web_deps{'Template'}{class} // '') =~ /^(?:bundled_pure_perl|compiled_dependency)$/, 'Template is packaged for standalone runtime');
    ok((($web_built->{standalone}{dependency_summary}{compiled_dependency} // 0) + ($web_built->{standalone}{dependency_summary}{bundled_pure_perl} // 0)) >= 3, 'webapp summary counts packaged framework dependencies');
    ok((grep { ($_->{unit_kind} // '') eq 'entrypoint' && ($_->{packaging} // '') eq 'compiled_service_dispatch_pcu_v1' } @{ $web_built->{standalone}{code_units} }) >= 1, 'webapp entrypoint packages as generic service dispatch unit');
    ok((grep { ($_->{package} // '') eq 'Example::PaxWeb' && ($_->{packaging} // '') eq 'compiled_pcu_v1' } @{ $web_built->{standalone}{code_units} }) >= 1, 'webapp module packages as compiled PCU');
    ok((grep { ($_->{logical_path} // '') =~ m{Dancer2/ConfigReader/Config/Any\.pm$} } @{ $web_built->{standalone}{runtime_payloads} // [] }) >= 1, 'runtime payload includes transitive bundled framework dependency');
    ok((grep { ($_->{logical_path} // '') eq 'views/index.tt' } @{ $web_built->{standalone}{assets} // [] }) >= 1, 'webapp template asset embedded');

    my $web_bin = abs_path($web_built->{standalone}{output_path});
    chmod 0700, $web_bin if defined $web_bin && -f $web_bin;
    my $port = _free_tcp_port();
    my $pid = fork();
    die 'fork failed for webapp smoke' if !defined $pid;
    if ($pid == 0) {
        open STDOUT, '>', File::Spec->catfile($tmp_base, 'webapp-standalone.log') or die $!;
        open STDERR, '>&STDOUT' or die $!;
        local %ENV = (
            HOME => '/tmp',
            PATH => '/nonexistent',
            TMPDIR => '/tmp',
        );
        exec $web_bin, 'serve', '--host', '127.0.0.1', '--port', $port;
        die "exec failed: $!";
    }

    my $http = HTTP::Tiny->new(timeout => 2);
    my $health;
    for (1 .. 20) {
        select undef, undef, undef, 0.5;
        my $res = $http->get("http://127.0.0.1:$port/healthz");
        if ($res->{success}) {
            $health = $res;
            last;
        }
    }
    ok($health && $health->{success}, 'webapp standalone serves healthz');
    if ($health && $health->{success}) {
        my $json = JSON::PP->new->decode($health->{content});
        is($json->{framework}, 'Dancer2', 'webapp healthz reports Dancer2');
        is($json->{server}, 'Starman', 'webapp healthz reports Starman');
        is($json->{template}, 'TemplateToolkit', 'webapp healthz reports TemplateToolkit');

        my $root_res = $http->get("http://127.0.0.1:$port/");
        ok($root_res->{success}, 'webapp standalone serves root document');
        ok($root_res->{content} =~ /Standalone Perl Web Application/, 'webapp root document renders HTML body');

        my $css_res = $http->get("http://127.0.0.1:$port/css/app.css");
        ok($css_res->{success} && $css_res->{content} =~ /font-family:/, 'webapp standalone serves embedded css');

        my $js_res = $http->get("http://127.0.0.1:$port/js/app.js");
        ok($js_res->{success} && $js_res->{content} =~ /fetch\('\/healthz'\)/, 'webapp standalone serves embedded js');
    }

    kill 'TERM', $pid;
    my $reaped = waitpid($pid, WNOHANG);
    if ($reaped == 0) {
        for (1 .. 20) {
            select undef, undef, undef, 0.25;
            $reaped = waitpid($pid, WNOHANG);
            last if $reaped == $pid;
        }
    }
    if ($reaped == 0) {
        kill 'KILL', $pid;
        waitpid($pid, 0);
    }
}

remove_tree($root) if -d $root;
remove_tree($extract_dir) if -d $extract_dir;
remove_tree($tmp_base) if -d $tmp_base;
unlink $native_hit_log if -f $native_hit_log;
done_testing;
