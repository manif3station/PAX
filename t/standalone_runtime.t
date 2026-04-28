use strict;
use warnings;
use Test::More;

use lib 'lib';
use PAX::StandaloneRuntime ();

my ($stdout, $stderr, $exit_code) = PAX::StandaloneRuntime::_capture_system_command($^X, '-e', 'print "ok\n";');
is($exit_code, 0, '_capture_system_command returns successful exit status');
is($stdout, "ok\n", '_capture_system_command captures stdout');
is($stderr, '', '_capture_system_command captures empty stderr for clean command');

my ($missing_stdout, $missing_stderr, $missing_exit) = PAX::StandaloneRuntime::_capture_system_command('pax-command-that-does-not-exist-xyz');
is($missing_stdout, '', '_capture_system_command keeps stdout empty for missing command');
ok(PAX::StandaloneRuntime::_system_command_missing($missing_stderr, $missing_exit), '_system_command_missing recognises missing host tools');

{
    local $ENV{PAX_STANDALONE_EXECUTABLE} = '/tmp/pax-demo';
    my $wrapper = PAX::StandaloneRuntime::_standalone_internal_cli_wrapper_content('shell');
    like($wrapper, qr{exec '/tmp/pax-demo' --pax-standalone-helper 'shell' "\$@"}, 'standalone helper wrapper targets the standalone executable path');
}

{
    my $bin_dir = 't/tmp-standalone-bin';
    mkdir $bin_dir if !-d $bin_dir;
    open my $fh, '>', "$bin_dir/pax-demo" or die "cannot write fake standalone executable: $!";
    print {$fh} "#!/bin/sh\nexit 0\n";
    close $fh;
    chmod 0755, "$bin_dir/pax-demo";
    require Cwd;
    my $expected = Cwd::abs_path("$bin_dir/pax-demo");
    local $ENV{PATH} = join(':', $bin_dir, ($ENV{PATH} // ''));
    local $ENV{PAX_STANDALONE_EXECUTABLE} = 'pax-demo';
    my $resolved = PAX::StandaloneRuntime::_standalone_executable_path();
    is($resolved, $expected, 'standalone executable path resolves argv[0] through PATH');
    unlink "$bin_dir/pax-demo";
    rmdir $bin_dir;
}

{
    no warnings 'redefine';
    local $ENV{PAX_STANDALONE_EXECUTABLE} = '/tmp/pax-demo';
    my $fake_state = {
        manifest => {
            code_units => [],
            native_dispatch => [],
            app => {},
        },
        root => 't/tmp-standalone-runtime-root',
        app_namespace => '',
        legacy_namespace => '',
        compiled_packages => {},
        app_env_prefix => undef,
        native_runner => bless({}, 'PAX::NativeRunner'),
        wrapped => {},
        namespace_aliases => {},
        by_region => {},
        compiled_units => {},
        require_hook_installed => 0,
        loading_require => {},
        residual_loaded => {},
        residual_bootstrap_loaded => {},
    };
    local *PAX::StandaloneRuntime::_state = sub { return $fake_state };
    local *PAX::StandaloneRuntime::_install_namespace_compat = sub { return 1 };
    local *PAX::StandaloneRuntime::_install_require_hook = sub { return 1 };
    local *PAX::StandaloneRuntime::_install_pending_wrappers = sub { return 1 };
    local *PAX::StandaloneRuntime::_run_entrypoint = sub {
        return $0;
    };
    my $result = PAX::StandaloneRuntime->run(
        entrypoint => 'entrypoint.pl',
        argv => [],
    );
    is($result, '/tmp/pax-demo', 'standalone runtime runs entrypoint with the standalone executable path as $0');
}

done_testing;
