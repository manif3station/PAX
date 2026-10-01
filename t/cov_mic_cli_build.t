use strict;
use warnings;
use Test::More;
use Fcntl;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP qw(decode_json);
use lib "$FindBin::Bin/../lib";

use PAX::CLI;

=pod

=head1 NAME

t/cov_mic_cli_build.t - in-process tests for the build, run, app and standalone CLI paths

=head1 DESCRIPTION

Drives the argument parsing, paxfile merging, inline C<-e> entrypoint
materialisation, progress board selection and the app/standalone management
commands of PAX::CLI with the image builder, app server and child process
launch stubbed or replaced by tiny shell scripts.

=head1 WHY IT EXISTS

The existing CLI tests spawn bin/pax as a subprocess, which Devel::Cover does
not measure, so the build/run front end was never covered.

=cut

my $tmp = tempdir('pax-cov-mic-bld-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($name, $text, $mode)
# Writes a fixture file into the temp dir. Input: name, text, optional mode.
# Output: the path.
sub write_file {
    my ($name, $text, $mode) = @_;
    my $path = File::Spec->catfile($tmp, $name);
    open my $fh, '>', $path or die "$path: $!";
    print {$fh} $text;
    close $fh;
    chmod $mode, $path if defined $mode;
    return $path;
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

my $exit7 = write_file('exit7.sh', "#!/bin/sh\nexit 7\n", 0755);
my $exit0 = write_file('exit0.sh', "#!/bin/sh\nexit 0\n", 0755);

# ------------------------------------------------------------------ stubs
my %S;
my @builds;
my @calls;

# reset_state()
# Restores the default stub behaviour. Input: none. Output: none.
sub reset_state {
    %S = (
        build_result => { status => 'built', standalone => { output_path => $exit7 } },
        build_dies => 0,
        image => { output_path => $exit7, runtime => { mode => 'bundled_perl' } },
        native => { status => 'native' },
    );
    @builds = ();
    @calls = ();
    return;
}
reset_state();

{
    no warnings 'redefine';
    *PAX::StandaloneImage::build = sub {
        my ($self, %args) = @_;
        if ($args{entrypoint} && -f $args{entrypoint}) {
            open my $fh, '<', $args{entrypoint} or die $!;
            local $/;
            $args{entry_source} = <$fh>;
        }
        push @builds, \%args;
        unlink $args{entrypoint} if $S{unlink_entry} && -f $args{entrypoint};
        die "build exploded\n" if $S{build_dies};
        $args{progress}->({ task_id => 'resolve_inputs', status => 'running' }) if $args{progress};
        return $S{build_result};
    };
    *PAX::StandaloneImage::load = sub { my ($self, %args) = @_; push @calls, ['image_load', \%args]; return $S{image} };
    *PAX::StandaloneDispatch::run_i64 = sub { my ($self, %args) = @_; push @calls, ['run_i64', \%args]; return $S{native} };
    *PAX::AppImage::build = sub { my ($self, %args) = @_; push @calls, ['app_build', \%args]; return { status => 'built', name => $args{name} } };
    *PAX::AppImage::load = sub { my ($self, %args) = @_; push @calls, ['app_load', \%args]; return { socket_path => '/tmp/sock', name => $args{name} } };
    *PAX::AppServer::start = sub { my ($self, %args) = @_; push @calls, ['app_start', \%args]; return 11 };
    *PAX::AppServer::run_client = sub { my ($class, %args) = @_; push @calls, ['app_run', \%args]; return 12 };
    *PAX::AppServer::stop = sub { my ($class, %args) = @_; push @calls, ['app_stop', \%args]; return 13 };
}

# ------------------------------------------------------ run / build routing
{
    no warnings 'redefine';
    local *PAX::CLI::_run_standalone = sub { return 'standalone:' . join(',', @_[1 .. $#_]) };
    local *PAX::CLI::_build_standalone = sub { return 'built:' . join(',', @_[1 .. $#_]) };
    is(PAX::CLI->_run('a'), 'standalone:a', '_run delegates to standalone run');
    is(PAX::CLI->_build('b'), 'built:b', '_build delegates to standalone build');
    is(PAX::CLI->_standalone_build('c'), 'built:c', '_standalone_build delegates');
}

# --------------------------------------------------------------- app build
{
    my $pf = write_file('app.yml', "name: cfgapp\nentrypoint: cfg.pl\nlibs:\n  - cfglib\nassets:\n  - cfgasset\nasset_dirs:\n  - cfgdir\n");
    my ($rc, $out) = cli('_app_build', '--paxfile', $pf, '--compact');
    is($rc, 0, 'app build from paxfile');
    my ($c) = grep { $_->[0] eq 'app_build' } @calls;
    is($c->[1]{name}, 'cfgapp', 'name from paxfile');
    is($c->[1]{entrypoint}, 'cfg.pl', 'entrypoint from paxfile');
    is_deeply($c->[1]{lib_dirs}, ['cfglib'], 'libs from paxfile');
    is_deeply($c->[1]{assets}, ['cfgasset'], 'assets from paxfile');
    is_deeply($c->[1]{asset_dirs}, ['cfgdir'], 'asset dirs from paxfile');
    unlike($out, qr/\n  /, 'compact output');

    @calls = ();
    ($rc, $out) = cli('_app_build', '--name', 'n', '--paxfile', $pf, '--lib', 'l1', '--asset', 'a1', '--asset-dir', 'd1', 'entry.pl');
    ($c) = grep { $_->[0] eq 'app_build' } @calls;
    is($c->[1]{name}, 'n', 'CLI name wins');
    is($c->[1]{entrypoint}, 'entry.pl', 'CLI entrypoint wins');
    is_deeply($c->[1]{lib_dirs}, ['l1'], 'CLI libs win');
    is_deeply($c->[1]{assets}, ['a1'], 'CLI assets win');
    is_deeply($c->[1]{asset_dirs}, ['d1'], 'CLI asset dirs win');

    @calls = ();
    my $bare = write_file('bare.yml', "entrypoint: only.pl\n");
    cli('_app_build', '--paxfile', $bare);
    ($c) = grep { $_->[0] eq 'app_build' } @calls;
    is_deeply($c->[1]{lib_dirs}, [], 'libs default to empty');
    is_deeply($c->[1]{assets}, [], 'assets default to empty');
    is_deeply($c->[1]{asset_dirs}, [], 'asset dirs default to empty');

    @calls = ();
    cli('_app_build', '--no-paxfile', 'x.pl');
    ($c) = grep { $_->[0] eq 'app_build' } @calls;
    is($c->[1]{entrypoint}, 'x.pl', 'no-paxfile uses CLI entrypoint');
}

# ------------------------------------------------------------ app lifecycle
{
    @calls = ();
    my ($rc, $out) = cli('_app_start', '--name', 'a', '--daemonize', '--compact');
    is($rc, 0, 'daemonized start');
    is(decode_json($out)->{status}, 'started', 'start reported');
    is($calls[-1][1]{daemonize}, 1, 'daemonize passed');
    is((cli('_app_start', '--name', 'a'))[0], 11, 'foreground start returns server result');

    is((cli('_app_run', '--name', 'a', '--', 'x', 'y'))[0], 12, 'app run');
    is_deeply($calls[-1][1]{argv}, ['x', 'y'], 'app run args');
    is((cli('_app_run', '--name', 'a', 'z'))[0], 12, 'app run without separator');
    is_deeply($calls[-1][1]{argv}, ['z'], 'app run bare args');
    my ($rc2, $o2, $e2) = cli('_app_run', '--name');
    is($rc2, 2, 'app run name needs value');
    is($e2, "--name requires a value\n", 'app run name message');
    ($rc2, $o2, $e2) = cli('_app_run', '--', 'x');
    is($rc2, 2, 'app run needs name');
    like($e2, qr/app-run requires --name/, 'app run name message');
    ($rc2) = cli('_app_run');
    is($rc2, 2, 'app run with nothing');

    is((cli('_app_stop', '--name', 'a'))[0], 13, 'app stop');
}

# ----------------------------------------------------- build config parsing
{
    my @missing = (qw(-I -M -e --name --paxfile --lib --source-root --asset --asset-dir --cpanfile --output -o --runtime-mode --app-name --app-namespace --app-entrypoint-env --app-entrypoint-fallback --app-command));
    for my $opt (@missing) {
        my ($rc, $out, $err) = cli('_standalone_build_config', $opt);
        is($rc, 2, "$opt without value returns 2");
        like($err, qr/requires a value/, "$opt without value explained");
    }
    my ($rc, $out, $err) = cli('_standalone_build_config', 'a.pl', 'b.pl');
    is($rc, 2, 'second entrypoint rejected');
    like($err, qr/unexpected argument: b\.pl/, 'second entrypoint explained');
    ($rc, $out, $err) = cli('_standalone_build_config', '--no-paxfile', 'a.pl', '-e', '1');
    is($rc, 2, 'entrypoint and -e conflict');
    like($err, qr/cannot accept both an entrypoint and -e/, 'conflict explained');
    ($rc, $out, $err) = cli('_standalone_build_config', '--no-paxfile');
    is($rc, 2, 'nothing to build');
    like($err, qr/requires a Perl entrypoint or paxfile\.yml entrypoint/, 'nothing to build explained');

    my $pf = write_file('build.yml', join "\n",
        'name: pfname', 'entrypoint: pf.pl', 'output: pfout', 'runtime_mode: host_perl',
        'app_name: pfapp', 'app_namespace: pfns', 'app_entrypoint_env: PFENV', 'app_entrypoint_fallback: pffb', 'app_command: pfcmd',
        'libs:', '  - pflib', 'source_roots:', '  - pfroot', 'assets:', '  - pfasset', 'asset_dirs:', '  - pfdir', 'cpanfiles:', '  - pfcpan', '');

    my $cfg = PAX::CLI->_standalone_build_config('--paxfile', $pf);
    is($cfg->{entrypoint}, 'pf.pl', 'entrypoint from paxfile');
    is($cfg->{name}, 'pfname', 'name from paxfile');
    is($cfg->{output}, 'pfout', 'output from paxfile');
    is($cfg->{runtime_mode}, 'host_perl', 'runtime mode from paxfile');
    is($cfg->{app_name}, 'pfapp', 'app name from paxfile');
    is($cfg->{app_namespace}, 'pfns', 'app namespace from paxfile');
    is($cfg->{app_entrypoint_env}, 'PFENV', 'app env from paxfile');
    is($cfg->{app_entrypoint_fallback}, 'pffb', 'app fallback from paxfile');
    is($cfg->{app_command}, 'pfcmd', 'app command from paxfile');
    is_deeply($cfg->{libs}, ['pflib'], 'libs from paxfile');
    is_deeply($cfg->{source_roots}, ['pfroot'], 'source roots from paxfile');
    is_deeply($cfg->{assets}, ['pfasset'], 'assets from paxfile');
    is_deeply($cfg->{asset_dirs}, ['pfdir'], 'asset dirs from paxfile');
    is_deeply($cfg->{cpanfiles}, ['pfcpan'], 'cpanfiles from paxfile');
    is($cfg->{paxfile_applied}, 1, 'paxfile applied');
    is_deeply($cfg->{override_fields}, [], 'nothing overridden');

    my $full = PAX::CLI->_standalone_build_config(
        '--paxfile', $pf, '-I', 'inc1', '-Iinc2', '-M', 'Mod::A', '-MMod::B=x,y', '--name', 'cn', '--lib', 'cl',
        '--source-root', 'cr', '--asset', 'ca', '--asset-dir', 'cd', '--cpanfile', 'cc', '--output', 'co',
        '--runtime-mode', 'bundled_perl', '--app-name', 'can', '--app-namespace', 'cns', '--app-entrypoint-env', 'CENV',
        '--app-entrypoint-fallback', 'cfb', '--app-command', 'ccmd', '--compact', 'cli.pl');
    is($full->{entrypoint}, 'cli.pl', 'CLI entrypoint');
    is($full->{name}, 'cn', 'CLI name wins');
    is($full->{output}, 'co', 'CLI output wins');
    is($full->{pretty}, 0, 'compact flag');
    is_deeply($full->{perl_libs}, ['inc1', 'inc2'], '-I forms');
    is_deeply($full->{perl_modules}, ['Mod::A', 'Mod::B=x,y'], '-M forms');
    is_deeply($full->{libs}, ['cl'], 'CLI libs win');
    is_deeply($full->{cpanfiles}, ['cc'], 'CLI cpanfiles win');
    is($full->{app_command}, 'ccmd', 'CLI app command wins');
    is($full->{paxfile_applied}, 1, 'explicit paxfile applies to a CLI entrypoint');
    ok(scalar(grep { $_ eq 'entrypoint' } @{ $full->{override_fields} }), 'entrypoint override recorded');

    my $isolated = PAX::CLI->_standalone_build_config('-o', 'out1', 'cli.pl');
    is($isolated->{output}, 'out1', '-o short form');
    is($isolated->{paxfile_applied}, 0, 'ambient paxfile is not applied to a CLI entrypoint');
    is($isolated->{name}, undef, 'no inherited name');

    my $none = PAX::CLI->_standalone_build_config('--no-paxfile', 'cli.pl');
    is($none->{paxfile_applied}, 0, 'no-paxfile never applies');

    my $inline = PAX::CLI->_standalone_build_config('--no-paxfile', '-e', 'print 1;', '-e', 'print 2;');
    is($inline->{inline_eval}, "print 1;\nprint 2;", 'inline eval parts are joined');
    is($inline->{entrypoint}, undef, 'inline build has no entrypoint');
    my $inline_pf = PAX::CLI->_standalone_build_config('--paxfile', $pf, '-e', 'print 1;');
    is($inline_pf->{entrypoint}, undef, 'inline eval ignores the paxfile entrypoint');
    is($inline_pf->{name}, 'pfname', 'explicit paxfile applies to inline eval');
    my $inline_amb = PAX::CLI->_standalone_build_config('-e', 'print 1;');
    is($inline_amb->{paxfile_applied}, 0, 'ambient paxfile skipped for inline eval');

    my $sparse = PAX::CLI->_standalone_build_config('--paxfile', write_file('sparse.yml', "entrypoint: sparse.pl\n"));
    is($sparse->{name}, undef, 'paxfile without a name leaves it unset');
    is($sparse->{output}, undef, 'paxfile without output leaves it unset');
    is_deeply($sparse->{libs}, [], 'paxfile without libs leaves them empty');
    my $gone = PAX::CLI->_standalone_build_config('--paxfile', File::Spec->catfile($tmp, 'gone.yml'), 'cli.pl');
    is($gone->{paxfile_applied}, 0, 'explicit but missing paxfile is not applied');

    # The ambient ./paxfile.yml is honoured when nothing is on the CLI.
    my $cwd = File::Spec->rel2abs('.');
    chdir $tmp or die $!;
    write_file('paxfile.yml', "entrypoint: ambient.pl\nname: ambient\n");
    my $amb = PAX::CLI->_standalone_build_config();
    chdir $cwd or die $!;
    is($amb->{entrypoint}, 'ambient.pl', 'ambient paxfile entrypoint');
    is($amb->{paxfile_applied}, 1, 'ambient paxfile applied');
}

# ------------------------------------------------------- inline entrypoints
{
    is_deeply([PAX::CLI::_parse_perl_module_switch('Mod')], ['Mod'], 'module without imports');
    is_deeply([PAX::CLI::_parse_perl_module_switch('Mod=')], ['Mod'], 'module with empty import list');
    is_deeply([PAX::CLI::_parse_perl_module_switch('Mod=a,b')], ['Mod', 'a', 'b'], 'module with imports');
    is(PAX::CLI::_perl_single_quote(undef), "''", 'undef quotes to empty');
    is(PAX::CLI::_perl_single_quote("it's a\\b"), "'it\\'s a\\\\b'", 'quote escaping');

    my $src = PAX::CLI->_standalone_inline_entrypoint_source({
        perl_libs => ['lib1'], perl_modules => ['Mod', 'Other=x,y'], inline_eval => 'print 1;',
    });
    like($src, qr/^use lib 'lib1';$/m, 'lib line');
    like($src, qr/^BEGIN \{ require Mod; Mod->import\(\); \}$/m, 'plain import');
    like($src, qr/^BEGIN \{ require Other; Other->import\('x', 'y'\); \}$/m, 'import with args');
    like($src, qr/print 1;\n\z/, 'body last');
    my $bare = PAX::CLI->_standalone_inline_entrypoint_source({ inline_eval => '1;' });
    unlike($bare, qr/use lib|BEGIN/, 'no libs or modules by default');

    my ($path, $cleanup) = PAX::CLI->_standalone_materialize_entrypoint({ entrypoint => 'e.pl' });
    is($path, 'e.pl', 'plain entrypoint passes through');
    is($cleanup, undef, 'nothing to clean up');
    ($path, $cleanup) = PAX::CLI->_standalone_materialize_entrypoint({ inline_eval => 'print 1;' });
    ok(-f $path, 'inline entrypoint written');
    is($cleanup, $path, 'inline entrypoint cleaned up later');
    unlink $path;

  SKIP: {
        skip 'no /dev/full', 1 if !-w '/dev/full';
        no warnings 'redefine';
        local *File::Temp::tempfile = sub { open my $fh, '>', '/dev/full' or die $!; return ($fh, '/dev/full') };
        eval { PAX::CLI->_standalone_materialize_entrypoint({ inline_eval => 'print 1;' }) };
        like($@, qr/unable to close inline entrypoint \/dev\/full/, 'close failure is fatal');
    }
}

# -------------------------------------------------------- building from config
{
    my $saved = $ENV{PAX_PROGRESS};
    local $ENV{PAX_PROGRESS} = 0;
    my ($rc, $out, $err) = cli('_build_standalone', '--no-paxfile', '--compact', '-I', 'inc', '-M', 'Mod', '-e', 'print 1;', '--lib', 'l1');
    is($rc, 0, 'inline build succeeds');
    is(decode_json($out)->{status}, 'built', 'result printed');
    is($err, '', 'no progress board when disabled');
    like($builds[-1]{entry_source}, qr/print 1;/, 'inline source passed to the builder');
    is_deeply($builds[-1]{lib_dirs}, ['inc', 'l1'], 'perl libs precede libs');
    ok(!-e $builds[-1]{entrypoint}, 'temporary entrypoint removed');

    ($rc, $out, $err) = cli('_build_standalone', 'plain.pl');
    is($rc, 0, 'plain build succeeds');
    is($builds[-1]{entrypoint}, 'plain.pl', 'entrypoint untouched');
    like($out, qr/\n  /, 'pretty result by default');

    $S{build_result} = { status => 'failed' };
    is((cli('_build_standalone', 'plain.pl'))[0], 1, 'failed build exits 1');
    reset_state();

    $S{build_dies} = 1;
    eval { cli('_build_standalone', '--no-paxfile', '-e', '1;') };
    like($@, qr/build exploded/, 'builder errors propagate');
    reset_state();

    is((cli('_build_standalone', '-I'))[0], 2, 'config errors propagate unchanged');

    $S{unlink_entry} = 1;
    ($rc) = cli('_build_standalone', '--no-paxfile', '-e', '1;');
    is($rc, 0, 'builder removing the temporary entrypoint is tolerated');
    reset_state();

    my $bare = PAX::CLI->_standalone_build_from_config({ entrypoint => 'bare.pl', pretty => 1 });
    is($bare->{result}{status}, 'built', 'config without library lists builds');
    is_deeply($builds[-1]{lib_dirs}, [], 'no library directories');

    $ENV{PAX_PROGRESS} = 1;
    ($rc, $out, $err) = cli('_build_standalone', 'plain.pl');
    like($err, qr/pax build progress/, 'progress board when enabled');
    delete $ENV{PAX_PROGRESS};
    ($rc, $out, $err) = cli('_build_standalone', 'plain.pl');
    like($err, qr/pax build progress/, 'progress board by default');
    $ENV{PAX_PROGRESS} = 0;
    ok(!defined PAX::CLI->_standalone_build_progress, 'progress disabled by env');
    $ENV{PAX_PROGRESS} = $saved if defined $saved;
}

# A terminal on STDERR switches the board to dynamic, coloured output.
SKIP: {
    my $master;
    skip 'no pseudo terminal available', 3
        if !sysopen($master, '/dev/ptmx', O_RDWR | O_NOCTTY);
    my $zero = pack('i', 0);
    my $num = '';
    skip 'cannot unlock pseudo terminal', 3
        if !ioctl($master, 0x40045431, $zero) || !ioctl($master, 0x80045430, $num);
    my $slave_path = '/dev/pts/' . unpack('i', $num);
    open my $slave, '>', $slave_path or skip "cannot open $slave_path", 3;
    local $ENV{PAX_PROGRESS} = 1;
    my $progress;
    {
        local *STDERR;
        open STDERR, '>&', $slave or die $!;
        $progress = PAX::CLI->_standalone_build_progress;
    }
    ok($progress, 'progress created on a terminal');
    is($progress->{dynamic}, 1, 'dynamic on a terminal');
    is($progress->{color}, 1, 'colour on a terminal');
    close $slave;
    close $master;
}

# ------------------------------------------------------------- run standalone
{
    local $ENV{PAX_PROGRESS} = 0;
    reset_state();
    is((cli('_run_standalone', 'plain.pl', '--', 'arg'))[0], 7, 'run returns the child exit code');
    is((cli('_run_standalone', 'plain.pl'))[0], 7, 'run without separator');
    $S{build_result} = { status => 'failed' };
    is((cli('_run_standalone', 'plain.pl'))[0], 1, 'failed build fails run');
    $S{build_result} = {};
    is((cli('_run_standalone', 'plain.pl'))[0], 1, 'build without status fails run');
    reset_state();
    is((cli('_run_standalone', '-I'))[0], 2, 'config error propagates');

    is((cli('_standalone_run', '--name', 'n', '--', 'a', 'b'))[0], 7, 'standalone-run executes the image');
    is((cli('_standalone_run', '--name', 'n', 'a'))[0], 7, 'standalone-run with bare args');
    is((cli('_standalone_run', 'a'))[0], 2, 'standalone-run needs a name');
    $S{image} = { output_path => $exit0 };
    is((cli('_standalone_run', '--name', 'n'))[0], 0, 'standalone-run success');
    is((cli('_standalone_extract', '--name', 'n', '--output', File::Spec->catdir($tmp, 'x')))[0], 0, 'extract runs the image');
    reset_state();
    is((cli('_standalone_extract', '--name', 'n', '--output', 'o'))[0], 7, 'extract returns child exit code');
    my ($rc, $out, $err) = cli('_standalone_extract', '--name', 'n');
    is($rc, 2, 'extract needs output');
    like($err, qr/requires --output/, 'extract output message');
}

# ----------------------------------------------------- inspect and why-not
{
    reset_state();
    $S{image} = { output_path => $exit0, runtime => { mode => 'bundled_perl' }, name => 'img' };
    my ($rc, $out) = cli('_standalone_inspect', '--name', 'n', '--compact');
    is($rc, 0, 'inspect ok');
    is(decode_json($out)->{name}, 'img', 'image printed');

    ($rc, $out) = cli('_standalone_why_not', '--name', 'n', '--compact');
    my $r = decode_json($out);
    ok($r->{standalone_ready}, 'image without sections is ready');
    is_deeply($r->{missing_dependencies}, [], 'no missing dependencies');

    $S{image} = {
        runtime => { mode => 'host_perl' },
        dependencies => [{ class => 'missing', module => 'M::X', provider => 'p' }, { class => 'present', module => 'M::Y' }, {}],
        native_artifacts => [
            { status => 'native_artifact', entry_kind => 'x', region_name => 'a' },
            { status => 'fallback', entry_kind => 'native_i64_leaf', region_name => 'b' },
            { status => 'fallback', entry_kind => 'reference', region_name => 'c', reason => 'why' },
            { region_name => 'd' },
        ],
        code_units => [
            { packaging => 'source_payload_fallback', logical_path => 'p.pm', unit_kind => 'module', fallback_reason => 'r', fallback_detail => 'd' },
            { packaging => 'native', logical_path => 'q.pm' },
            {},
        ],
    };
    ($rc, $out) = cli('_standalone_why_not', '--name', 'n');
    $r = decode_json($out);
    ok(!$r->{standalone_ready}, 'missing dependency means not ready');
    is($r->{bundled_runtime}, 'host_perl', 'runtime mode reported');
    is_deeply($r->{missing_dependencies}, [{ module => 'M::X', provider => 'p' }], 'missing dependency listed');
    is_deeply([map { $_->{region_name} } @{ $r->{native_not_packaged} }], ['c', 'd'], 'unpackaged native regions listed');
    is_deeply($r->{source_fallback_units}, [{ logical_path => 'p.pm', unit_kind => 'module', reason => 'r', detail => 'd' }], 'source fallbacks listed');
}

# ---------------------------------------------------------------- native run
{
    reset_state();
    my ($rc, $out) = cli('_standalone_native_run', '--name', 'n', '--region', 'r', '--left', '4', '--right', '5',
        '--invalidate', 'e1', '--invalidate', 'e2', '--compact');
    is($rc, 0, 'native run ok');
    is_deeply($calls[-1][1]{invalidate}, ['e1', 'e2'], 'invalidations passed');
    is($calls[-1][1]{left}, 4, 'left passed');
    ($rc) = cli('_standalone_native_run', '--name', 'n', '--region', 'r');
    is($calls[-1][1]{left}, 0, 'left defaults to zero');
    $S{native} = { result => { status => 'ok' } };
    is((cli('_standalone_native_run', '--name', 'n', '--region', 'r'))[0], 0, 'nested ok result');
    $S{native} = { status => 'fallback', result => { status => 'error' } };
    is((cli('_standalone_native_run', '--name', 'n', '--region', 'r'))[0], 1, 'failure result');
    $S{native} = {};
    is((cli('_standalone_native_run', '--name', 'n', '--region', 'r'))[0], 1, 'empty result');
    my ($rc2, $o2, $e2) = cli('_standalone_native_run', '--name', 'n');
    is($rc2, 2, 'region required');
    like($e2, qr/requires --region/, 'region message');
}

done_testing;
