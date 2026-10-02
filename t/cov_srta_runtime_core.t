use strict;
use warnings;
no warnings 'once';
use Test::More;
use Capture::Tiny qw(capture);
use B ();
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/../lib";

# The runtime ends a few entry paths with exit(). Tests trap it so the in-process
# calls can observe the exit code instead of terminating the harness.
BEGIN {
    *CORE::GLOBAL::exit = sub {
        if ($PaxCovSrta::TRAP_EXIT) {
            die bless { code => (@_ ? $_[0] : 0) }, 'PaxCovSrta::Exit';
        }
        CORE::exit(@_ ? $_[0] : 0);
    };
}

use PAX::GuardManager ();
use PAX::StandaloneRuntime ();


=pod

=head1 NAME

t/cov_srta_runtime_core.t - in-process coverage of the standalone runtime loader core

=head1 WHY IT EXISTS

The standalone runtime normally runs inside a built binary, which Devel::Cover
never sees. This test loads the runtime in-process, points it at a fabricated
manifest and code tree in a temp directory, and calls the manifest/state
loading, require hook, compiled-unit loading, helper running and path utility
functions directly so every statement, branch and condition is exercised.

=head1 DESCRIPTION

Each C<fresh()> call resets the runtime's file-scoped C<$STATE> (reached through
the sub's pad with C<B>) and builds a new manifest and code tree.
Collaborators are replaced with local glob overrides. C<exit> is trapped.

=cut

my $BASE = tempdir('pax-cov-srta-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $SEQ = 0;
my $P = 'PAX::StandaloneRuntime';
my $PKG_SEQ = 0;

# write_file($path, $text)
# Writes a fixture file, creating parent directories first.
# Input: destination path and text. Output: the path written.
sub write_file {
    my ($path, $text) = @_;
    my ($vol, $dir) = File::Spec->splitpath($path);
    make_path($dir) if length $dir && !-d $dir;
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    return $path;
}

# write_json($path, $data)
# Writes a data structure as a JSON fixture file.
# Input: destination path and data. Output: the path written.
sub write_json {
    my ($path, $data) = @_;
    return write_file($path, JSON::PP->new->utf8->canonical->encode($data));
}

# reset_state()
# Clears the runtime's file-scoped $STATE through its pad entry so each case
# starts from a clean manifest load. Input: none. Output: none.
sub reset_state {
    my $padlist = B::svref_2object(\&PAX::StandaloneRuntime::_state)->PADLIST;
    my @names = $padlist->ARRAYelt(0)->ARRAY;
    my @pad = $padlist->ARRAYelt(1)->ARRAY;
    for my $i (1 .. $#names) {
        next if ref($names[$i]) ne 'B::PADNAME';
        next if $names[$i]->PV ne '$STATE';
        ${ $pad[$i]->object_2svref } = undef;
        return;
    }
    die 'cannot find $STATE in the runtime pad';
}

# fresh($manifest)
# Builds a temp runtime root with a manifest and loads a private runtime copy.
# Input: manifest hash (or undef for an empty one). Output: (package, root dir).
sub fresh {
    my ($manifest) = @_;
    my $dir = File::Spec->catdir($BASE, 'root' . ++$SEQ);
    make_path($dir);
    write_json("$dir/manifest.json", $manifest || {});
    $ENV{PAX_STANDALONE_MANIFEST_PATH} = "$dir/manifest.json";
    $ENV{PAX_STANDALONE_TMPDIR} = $dir;
    reset_state();
    call($P, '_state');
    return ($P, $dir);
}

# call($pkg, $name, @args)
# Calls a function of a private runtime copy.
# Input: package, function name, arguments. Output: whatever the function returns.
sub call {
    my ($pkg, $name, @args) = @_;
    no strict 'refs';
    return &{"${pkg}::$name"}(@args);
}

# dies($code)
# Runs a code ref and returns the exception text, or undef when it lived.
# Input: code ref. Output: error string or undef.
sub dies {
    my ($code) = @_;
    my $ok = eval { $code->(); 1 };
    my $error = $@;
    return $ok ? undef : $error;
}

# trapped_exit($code)
# Runs a code ref with exit() trapped.
# Input: code ref. Output: (exit code or undef, other exception or undef).
sub trapped_exit {
    my ($code) = @_;
    local $PaxCovSrta::TRAP_EXIT = 1;
    my $ok = eval { $code->(); 1 };
    my $error = $@;
    return (undef, undef) if $ok;
    return ($error->{code}, undef) if ref($error) eq 'PaxCovSrta::Exit';
    return (undef, $error);
}

# uniq_pkg($label)
# Returns a package name unique to this test run.
# Input: label. Output: package name.
sub uniq_pkg {
    my ($label) = @_;
    return 'PaxCovSrta' . $label . ++$PKG_SEQ;
}

delete @ENV{qw(PAX_STANDALONE_TRACE PAX_STANDALONE_EXECUTABLE PAX_STANDALONE_NATIVE_HIT_LOG PAX_EAGER_SUBS)};

# ---------------------------------------------------------------- _state errors
{
    local %ENV = %ENV;
    delete @ENV{qw(PAX_STANDALONE_MANIFEST_PATH PAX_STANDALONE_TMPDIR)};
    reset_state();
    my $p = $P;
    like(dies(sub { call($p, '_state') }), qr/PAX_STANDALONE_MANIFEST_PATH not set/, '_state needs a manifest path');
    $ENV{PAX_STANDALONE_MANIFEST_PATH} = "$BASE/does-not-exist.json";
    like(dies(sub { call($p, '_state') }), qr/cannot read \Q$BASE\E\/does-not-exist\.json/, '_state reports an unreadable manifest');
    write_json("$BASE/early.json", {});
    $ENV{PAX_STANDALONE_MANIFEST_PATH} = "$BASE/early.json";
    like(dies(sub { call($p, '_state') }), qr/PAX_STANDALONE_TMPDIR not set/, '_state needs a runtime root');
    $ENV{PAX_STANDALONE_TMPDIR} = $BASE;
    my $state = call($p, '_state');
    is(ref $state, 'HASH', '_state builds once the environment is complete');
    is(call($p, '_state'), $state, '_state caches its result');
}

# ---------------------------------------------------------------- _state shapes
{
    my ($p) = fresh({
        app => { namespace => 'My::App', compat => { legacy_namespace => 'Old::App' } },
        native_dispatch => [ { region_name => 'Reg::one' }, { note => 'no region name' } ],
        code_units => [
            { packaging => 'compiled_pcu_v1', require_path => 'My/App.pm', package => 'My::App' },
            { packaging => 'hybrid_compiled_pcu_v1', require_path => 'My/App/Sub.pm', package => 'My::App::Sub' },
            { packaging => 'compiled_pcu_v1' },
            { packaging => 'residual_pcu_v1', require_path => 'Res.pm', package => 'Res' },
            { require_path => 'Nopack.pm' },
        ],
    });
    my $state = call($p, '_state');
    is($state->{app_namespace}, 'My::App', 'namespace read from app');
    is($state->{legacy_namespace}, 'Old::App', 'legacy namespace read from compat');
    is_deeply([ sort keys %{ $state->{compiled_units} } ], [ 'My/App.pm', 'My/App/Sub.pm' ], 'only compiled units with require paths are indexed');
    is_deeply([ sort keys %{ $state->{compiled_packages} } ], [ 'My::App', 'My::App::Sub', 'Res' ], 'every unit package is recorded');
    is_deeply([ sort keys %{ $state->{by_region} } ], [ '', 'Reg::one' ], 'regions are indexed by name with a blank fallback');

    my ($p2) = fresh({ app => { compat => { namespace => 'Compat::NS' } } });
    my $s2 = call($p2, '_state');
    is($s2->{app_namespace}, 'Compat::NS', 'compat namespace is used when the app namespace is blank');
    is($s2->{legacy_namespace}, 'Compat::NS', 'legacy namespace defaults to the app namespace');

    my ($p3) = fresh({});
    my $s3 = call($p3, '_state');
    is($s3->{app_namespace}, '', 'empty manifest has no namespace');
    is_deeply($s3->{compiled_units}, {}, 'empty manifest has no compiled units');
}

# ---------------------------------------------------------------- _trace and command helpers
{
    my ($p) = fresh({});
    {
        local $ENV{PAX_STANDALONE_TRACE} = 0;
        my (undef, $err) = capture { call($p, '_trace', 'quiet') };
        is($err, '', '_trace is silent unless enabled');
    }
    local $ENV{PAX_STANDALONE_TRACE} = 1;
    my (undef, $err) = capture { call($p, '_trace', 'hello') };
    is($err, "[pax-standalone] hello\n", '_trace prints the message');
    (undef, $err) = capture { call($p, '_trace') };
    is($err, "[pax-standalone] \n", '_trace tolerates a missing message');

    ok(call($p, '_system_command_missing', undef, undef), 'missing exit code means missing command');
    ok(call($p, '_system_command_missing', '', -1), 'negative exit code means missing command');
    ok(call($p, '_system_command_missing', '', 127), 'exit 127 means missing command');
    ok(call($p, '_system_command_missing', "sh: can't exec foo", 1), 'stderr text means missing command');
    is(call($p, '_system_command_missing', undef, 1), 0, 'undef stderr with a normal failure is not missing');
    is(call($p, '_system_command_missing', 'boom', 1), 0, 'unrelated stderr is not missing');
}

# ---------------------------------------------------------------- _entrypoint_looks_valid
{
    my ($p) = fresh({});
    is(call($p, '_entrypoint_looks_valid', undef), 0, 'undef entrypoint is invalid');
    is(call($p, '_entrypoint_looks_valid', '--flag'), 0, 'option-looking entrypoint is invalid');
    is(call($p, '_entrypoint_looks_valid', '  '), 0, 'blank entrypoint is invalid');
    is(call($p, '_entrypoint_looks_valid', '/x/y.pl'), 1, 'path entrypoint is valid');
}

# ---------------------------------------------------------------- _resolve_entrypoint_from_manifest
{
    my ($p, $dir) = fresh({});
    my $state = call($p, '_state');
    is(call($p, '_resolve_entrypoint_from_manifest', undef), undef, 'nothing to resolve in an empty manifest');
    write_file("$dir/code/sub/m.pl", "1;\n");
    $state->{manifest} = { entrypoint => { logical_path => 'sub/m.pl' } };
    is(call($p, '_resolve_entrypoint_from_manifest', 'x'), "$dir/code/sub/m.pl", 'manifest entrypoint wins when present');

    write_file("$dir/code/u1.dispatch.json", '{}');
    write_file("$dir/code/u2.pl", '1;');
    $state->{manifest} = {
        entrypoint => { logical_path => 'gone.pl' },
        code_units => [
            {},
            { unit_kind => 'other', packaging => 'plain' },
            { unit_kind => 'entrypoint' },
            { unit_kind => 'entrypoint', logical_path => '' },
            { unit_kind => 'entrypoint', logical_path => 'nofile.pl' },
            { packaging => 'compiled_dispatch_pcu_v1', logical_path => 'u1.dispatch.json' },
        ],
    };
    is(call($p, '_resolve_entrypoint_from_manifest', 'x'), "$dir/code/u1.dispatch.json", 'falls back to the first existing matching unit');
    $state->{manifest} = { code_units => [ { unit_kind => 'entrypoint', logical_path => 'nofile.pl' } ] };
    is(call($p, '_resolve_entrypoint_from_manifest', 'x'), undef, 'no existing candidate resolves to nothing');
    for my $packaging (qw(hybrid_cli_router_pcu_v1 residual_script_pcu_v1)) {
        $state->{manifest} = { code_units => [ { packaging => $packaging, logical_path => 'u2.pl' } ] };
        is(call($p, '_resolve_entrypoint_from_manifest', 'x'), "$dir/code/u2.pl", "$packaging units count as entrypoint candidates");
    }
    $state->{manifest} = { code_units => [ { packaging => 'compiled_pcu_v1', logical_path => 'u2.pl' } ] };
    is(call($p, '_resolve_entrypoint_from_manifest', 'x'), undef, 'ordinary compiled units are not entrypoints');
}

# ---------------------------------------------------------------- run
{
    my ($p, $dir) = fresh({ entrypoint => { logical_path => 'main.pl' } });
    write_file("$dir/code/main.pl", '$main::PAXCOV_RAN = join(",", "ran", @ARGV); 42;' . "\n");
    my $exe = write_file("$dir/fake-exe", "#!/bin/sh\n");
    chmod 0755, $exe;
    local *CORE::GLOBAL::require;

    is(call($p, 'run', undef, entrypoint => "$dir/code/main.pl", argv => [ 'a', 'b' ]), 42, 'run executes a plain entrypoint and returns its value');
    is($main::PAXCOV_RAN, 'ran,a,b', 'run hands argv to the entrypoint');

    {
        local @ARGV = ('--bad', 'extra');
        local $ENV{PAX_STANDALONE_TRACE} = 1;
        my ($out, $err, $rv) = capture { call($p, 'run', undef) };
        is($rv, 42, 'run falls back to the manifest entrypoint for a bad argument');
        like($err, qr/entrypoint fallback from manifest: '--bad' -> '\Q$dir\E\/code\/main\.pl'/, 'fallback is traced');
    }
    {
        local @ARGV = ();
        local $ENV{PAX_STANDALONE_TRACE} = 1;
        my ($out, $err, $rv) = capture { call($p, 'run', undef) };
        is($rv, 42, 'run falls back to the manifest entrypoint when none is given');
        like($err, qr/'<undef>' ->/, 'missing entrypoint is traced as undef');
    }

    {
        local $ENV{PAX_STANDALONE_EXECUTABLE} = $exe;
        my @seen;
        no strict 'refs';
        no warnings 'redefine';
        local *{"${p}::_run_standalone_managed_helper"} = sub { push @seen, [ @_, $0 ]; return 'H' };
        is(call($p, 'run', undef, entrypoint => "$dir/code/main.pl", argv => [ '--pax-standalone-helper', 'dash', 'p', 'q' ]), 'H', 'run routes helper invocations');
        is_deeply(\@seen, [ [ 'dash', 'p', 'q', abs_path($exe) ] ], 'helper receives its name, args and runs with the executable as $0');
        like(dies(sub { call($p, 'run', undef, entrypoint => "$dir/code/main.pl", argv => ['--pax-standalone-helper']) }), qr/standalone helper name required/, 'helper name is required');
    }

    my ($bare) = fresh({});
    like(dies(sub { local @ARGV = (); call($bare, 'run', undef) }), qr/entrypoint required/, 'run needs an entrypoint');
    like(dies(sub { call($bare, 'run', undef, entrypoint => '-x') }), qr/entrypoint is not a valid executable unit: -x/, 'run rejects an invalid entrypoint');
}

# ---------------------------------------------------------------- _app_env_prefix / command names
{
    my ($p) = fresh({});
    my $state = call($p, '_state');
    my $prefix = sub {
        my ($app) = @_;
        $state->{manifest} = { defined $app ? (app => $app) : () };
        $state->{app_env_prefix} = undef;
        return call($p, '_app_env_prefix');
    };
    is($prefix->({ compat => { namespace => 'Foo::Bar' } }), 'FOO_BAR', 'prefix from compat namespace');
    is($prefix->({ namespace => 'Baz' }), 'BAZ', 'prefix from app namespace');
    is($prefix->({ name => 'my-app' }), 'MY_APP', 'prefix from app name');
    is($prefix->({ name => '   ', command => 'cmd' }), 'CMD', 'blank name falls back to the command');
    is($prefix->(undef), 'APP', 'no app at all yields APP');
    is($prefix->({ name => '123' }), 'APP', 'names without letters yield APP');
    is($prefix->({ name => '--' }), 'APP', 'names that clean down to nothing yield APP');
    is($prefix->({ name => '__x--y__' }), 'X_Y', 'separators are collapsed and trimmed');
    $state->{app_env_prefix} = 'CACHED';
    is(call($p, '_app_env_prefix'), 'CACHED', 'prefix is cached');

    # _app_command_name
    $state->{app_env_prefix} = 'PXC';
    $state->{manifest} = { app => { command => 'fromcmd' } };
    local @ENV{qw(PXC_COMMAND PXC_SPECIAL PXC_BLANK)};
    delete @ENV{qw(PXC_COMMAND PXC_SPECIAL PXC_BLANK)};
    is(call($p, '_app_command_name'), 'fromcmd', 'command name falls back to the manifest command');
    delete $ENV{PXC_NOT_SET};
    is(call($p, '_app_command_name', env_names => ['PXC_NOT_SET']), 'fromcmd', 'unset env names are skipped');
    $ENV{PXC_BLANK} = '';
    is(call($p, '_app_command_name', env_names => [ undef, '', 'PXC_BLANK' ]), 'fromcmd', 'blank env names and values are skipped');
    $ENV{PXC_SPECIAL} = 'special';
    is(call($p, '_app_command_name', env_names => ['PXC_SPECIAL']), 'special', 'named env wins');
    $ENV{PXC_COMMAND} = 'prefixed';
    is(call($p, '_app_command_name'), 'prefixed', 'prefix command env wins over the manifest');
    delete $ENV{PXC_COMMAND};
    $state->{manifest} = { app => { entrypoint_command => 'ec' } };
    is(call($p, '_app_command_name'), 'ec', 'entrypoint_command is the next fallback');
    $state->{manifest} = { app => {} };
    is(call($p, '_app_command_name'), 'pax', 'pax is the last fallback');
    $state->{manifest} = {};
    is(call($p, '_app_command_name'), 'pax', 'missing app also falls back to pax');

    # _app_entry_command
    local @ENV{qw(PXE_SUB PXE_FALL PXC_COMMAND)};
    delete @ENV{qw(PXE_SUB PXE_FALL PXC_COMMAND)};
    $state->{manifest} = { app => { entrypoint_env => 'PXE_FALL', entrypoint_fallback => 'efb', command => 'cmd' } };
    is(call($p, '_app_entry_command'), 'efb', 'entry command falls back to entrypoint_fallback');
    is(call($p, '_app_entry_command', sub_fallback => 'subfb'), 'subfb', 'explicit fallback wins');
    $ENV{PXE_SUB} = '';
    is(call($p, '_app_entry_command', sub_env => 'PXE_SUB'), 'efb', 'blank sub env is ignored');
    $ENV{PXE_SUB} = 'subval';
    is(call($p, '_app_entry_command', sub_env => 'PXE_SUB'), 'subval', 'sub env wins');
    delete $ENV{PXE_SUB};
    $ENV{PXE_FALL} = 'fallval';
    is(call($p, '_app_entry_command', sub_env => 'PXE_SUB'), 'fallval', 'entrypoint env is consulted');
    is(call($p, '_app_entry_command'), 'fallval', 'entrypoint env is consulted without a sub env');
    is(call($p, '_app_entry_command', sub_env => 'PXE_FALL'), 'fallval', 'sub env equal to the entrypoint env is read once');
    $ENV{PXE_FALL} = '';
    is(call($p, '_app_entry_command', sub_env => 'PXE_FALL'), 'efb', 'sub env equal to a blank entrypoint env is skipped');
    delete $ENV{PXE_FALL};
    is(call($p, '_app_entry_command', sub_fallback => ''), 'efb', 'blank explicit fallback defers to entrypoint_fallback');
    $state->{manifest} = { app => { entrypoint_fallback => '', command => 'cmd2' } };
    is(call($p, '_app_entry_command'), 'cmd2', 'blank entrypoint_fallback defers to the command');
    $state->{manifest} = { app => { entrypoint_env => 'PXE_FALL', entrypoint_fallback => 'efb', command => 'cmd' } };
    $ENV{PXC_COMMAND} = 'pfx';
    is(call($p, '_app_entry_command'), 'pfx', 'prefix command env is consulted');
    delete $ENV{PXC_COMMAND};
    $state->{manifest} = { app => { entrypoint_env => '', command => 'cmd' } };
    is(call($p, '_app_entry_command'), 'cmd', 'blank entrypoint env falls through to the command');
    $state->{manifest} = { app => { command => '' } };
    is(call($p, '_app_entry_command'), 'pax', 'nothing configured yields pax');
    $state->{manifest} = undef;
    {
        my @warnings;
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        is(call($p, '_app_entry_command'), 'pax', 'missing manifest yields pax');
        like($warnings[0], qr/uninitialized/, 'the undef fallback is reported by perl');
    }
}

# ---------------------------------------------------------------- namespace helpers
{
    my ($p) = fresh({});
    my $state = call($p, '_state');
    is(call($p, '_normalize_namespace', undef), '', 'undef namespace normalises to blank');
    is(call($p, '_normalize_namespace', ' ::Foo::Bar:: '), 'Foo::Bar', 'namespace is trimmed');
    is(call($p, '_namespace_to_require_path', undef), '', 'undef namespace has no require path');
    is(call($p, '_namespace_to_require_path', ''), '', 'blank namespace has no require path');
    is(call($p, '_namespace_to_require_path', 'A::B'), 'A/B.pm', 'namespace maps to a require path');

    $state->{app_namespace} = 'My::App';
    $state->{legacy_namespace} = 'Old::App';
    is(call($p, '_legacy_require_path_to_app_require_path', undef), undef, 'undef path is not mapped');
    is(call($p, '_legacy_require_path_to_app_require_path', ''), undef, 'blank path is not mapped');
    is(call($p, '_legacy_require_path_to_app_require_path', 'Other/Thing.pm'), undef, 'unrelated paths are not mapped');
    is(call($p, '_legacy_require_path_to_app_require_path', 'Old/App.pm'), 'My/App.pm', 'legacy root module is mapped');
    is(call($p, '_legacy_require_path_to_app_require_path', 'Old/App/Sub.pm'), 'Old/App/Sub.pm', 'legacy submodule path is returned as matched');
    $state->{legacy_namespace} = undef;
    is(call($p, '_legacy_require_path_to_app_require_path', 'Old/App.pm'), undef, 'undef legacy namespace maps nothing');
    $state->{legacy_namespace} = '';
    is(call($p, '_legacy_require_path_to_app_require_path', 'Old/App.pm'), undef, 'blank legacy namespace maps nothing');
    $state->{legacy_namespace} = 'My::App';
    is(call($p, '_legacy_require_path_to_app_require_path', 'My/App.pm'), undef, 'identical namespaces map nothing');
    $state->{app_namespace} = undef;
    $state->{legacy_namespace} = 'Old::App';
    is(call($p, '_legacy_require_path_to_app_require_path', 'Old/App.pm'), '', 'undef app namespace maps to an empty prefix');

    $state->{app_namespace} = 'My::App';
    $state->{legacy_namespace} = 'Old::App';
    is(call($p, '_legacy_module_for_app_module', undef), undef, 'undef module is returned as is');
    is(call($p, '_legacy_module_for_app_module', ''), '', 'blank module is returned as is');
    is(call($p, '_legacy_module_for_app_module', 'My::App::X'), 'Old::App::X', 'app module maps to its legacy name');
    is(call($p, '_legacy_module_for_app_module', 'Other::X'), 'Other::X', 'unrelated module is unchanged');
    $state->{app_namespace} = '';
    is(call($p, '_legacy_module_for_app_module', 'My::App::X'), 'My::App::X', 'no app namespace maps nothing');
    $state->{app_namespace} = 'Old::App';
    is(call($p, '_legacy_module_for_app_module', 'Old::App::X'), 'Old::App::X', 'equal namespaces map nothing');
    $state->{app_namespace} = undef;
    $state->{legacy_namespace} = undef;
    is(call($p, '_legacy_module_for_app_module', 'Z'), 'Z', 'undef namespaces map nothing');
}

# ---------------------------------------------------------------- namespace aliases
{
    my ($p) = fresh({});
    my $state = call($p, '_state');
    my $new = uniq_pkg('New');
    my $old = uniq_pkg('Old');
    no strict 'refs';
    no warnings 'redefine';

    # nothing happens for degenerate names
    call($p, '_install_namespace_alias', undef, $new);
    call($p, '_install_namespace_alias', $old, '');
    call($p, '_install_namespace_alias', $new, $new);
    is_deeply($state->{namespace_aliases}, {}, 'degenerate alias requests are ignored');

    ${"${new}::marker"} = 1;
    *{"${new}::__ANON__"} = sub { 'anon' };
    ${"${new}::__END__x"} = 1;
    @{"${new}::ISA"} = ('NoSuchBase');
    *{"${new}::AUTOLOAD"} = sub { 'new-autoload' };
    *{"${new}::early"} = sub { 'early' };
    $INC{ join('/', split /::/, $new) . '.pm' } = 1;

    call($p, '_install_namespace_alias', $old, $new);
    is($state->{namespace_aliases}{$old}, $new, 'alias is recorded');
    is($old->early, 'early', 'existing subs are aliased');
    ok(!defined *{"${old}::ISA"}{ARRAY} || !@{"${old}::ISA"}, 'ISA is not copied');
    ok(!defined *{"${old}::__ANON__"}{CODE}, '__ANON__ is not copied');
    ok(defined *{"${old}::AUTOLOAD"}{CODE}, 'legacy package gets an AUTOLOAD');
    my $autoload = *{"${old}::AUTOLOAD"}{CODE};
    call($p, '_install_namespace_alias', $old, $new);
    is(*{"${old}::AUTOLOAD"}{CODE}, $autoload, 'second install is a no-op');

    *{"${new}::late"} = sub { 'late:' . join(',', @_) };
    is($old->late(1, 2), 'late:1,2', 'AUTOLOAD resolves methods defined later (invocant is consumed)');
    like(dies(sub { $old->nothing_here }), qr/Undefined subroutine ${old}::nothing_here/, 'AUTOLOAD dies for unknown methods');
    # AUTOLOAD that is called for the AUTOLOAD method itself returns quietly
    {
        local ${"${p}::AUTOLOAD"} = "${old}::AUTOLOAD";
        is(scalar($autoload->($old)), undef, 'AUTOLOAD for AUTOLOAD returns nothing');
    }

    # an existing AUTOLOAD is not replaced
    my $old2 = uniq_pkg('Old');
    *{"${old2}::AUTOLOAD"} = sub { 'mine' };
    my $mine = *{"${old2}::AUTOLOAD"}{CODE};
    call($p, '_install_namespace_alias', $old2, $new);
    is(*{"${old2}::AUTOLOAD"}{CODE}, $mine, 'a pre-existing AUTOLOAD is kept');

    # sync with an empty app stash is a no-op
    call($p, '_sync_namespace_alias_for_module', '', $new);
    call($p, '_sync_namespace_alias_for_module', $old, '');
    my $empty = uniq_pkg('Empty');
    my $legacy_empty = uniq_pkg('LegacyEmpty');
    call($p, '_sync_namespace_alias_for_module', $legacy_empty, $empty);
    ok(!exists $state->{namespace_aliases}{$legacy_empty}, 'empty app stash does not register an alias');

    # compat install over compiled packages
    my $app_ns = uniq_pkg('Ns');
    my $leg_ns = uniq_pkg('LegNs');
    $state->{app_namespace} = $app_ns;
    $state->{legacy_namespace} = $leg_ns;
    $state->{compiled_packages} = { $app_ns => 1, "${app_ns}::Sub" => 1, 'Unrelated::Pkg' => 1, "${app_ns}X" => 1 };
    *{"${app_ns}::root_sub"} = sub { 'root' };
    *{"${app_ns}::Sub::leaf"} = sub { 'leaf' };
    call($p, '_install_namespace_compat');
    is($state->{namespace_aliases}{$leg_ns}, $app_ns, 'root package is aliased');
    is($state->{namespace_aliases}{"${leg_ns}::Sub"}, "${app_ns}::Sub", 'sub package is aliased');
    ok(!exists $state->{namespace_aliases}{'Unrelated::Pkg'}, 'unrelated packages are skipped');
    is($leg_ns->root_sub, 'root', 'aliased root sub is callable through the legacy name');

    $state->{compiled_packages} = undef;
    call($p, '_install_namespace_compat');
    $state->{app_namespace} = '';
    call($p, '_install_namespace_compat');
    $state->{app_namespace} = undef;
    $state->{legacy_namespace} = undef;
    call($p, '_install_namespace_compat');
    $state->{app_namespace} = 'Same';
    $state->{legacy_namespace} = 'Same';
    call($p, '_install_namespace_compat');
    pass('compat install tolerates blank, undef and identical namespaces');

    # per-unit sync
    my $unit_app = uniq_pkg('UnitNs');
    my $unit_leg = uniq_pkg('UnitLeg');
    $state->{app_namespace} = $unit_app;
    $state->{legacy_namespace} = $unit_leg;
    *{"${unit_app}::Mod::m"} = sub { 'm' };
    call($p, '_sync_namespace_aliases_for_unit', { package => "${unit_app}::Mod" });
    is($state->{namespace_aliases}{"${unit_leg}::Mod"}, "${unit_app}::Mod", 'unit package gets a legacy alias');
    my $before = { %{ $state->{namespace_aliases} } };
    call($p, '_sync_namespace_aliases_for_unit', {});
    call($p, '_sync_namespace_aliases_for_unit', { package => '' });
    $state->{app_namespace} = '';
    call($p, '_sync_namespace_aliases_for_unit', { package => 'X' });
    $state->{app_namespace} = $unit_leg;
    call($p, '_sync_namespace_aliases_for_unit', { package => 'X' });
    $state->{app_namespace} = undef;
    $state->{legacy_namespace} = undef;
    call($p, '_sync_namespace_aliases_for_unit', { package => 'X' });
    is_deeply($state->{namespace_aliases}, $before, 'blank or identical namespaces register no unit alias');
}

# ---------------------------------------------------------------- _load_package_by_module_name
{
    my ($p, $dir) = fresh({});
    my $state = call($p, '_state');
    is(call($p, '_load_package_by_module_name', ''), undef, 'blank module loads nothing');
    {
        no strict 'refs';
        no warnings 'redefine';
        my @seen;
        local *{"${p}::_load_compiled_require"} = sub { push @seen, $_[0]; return 'compiled' };
        $state->{compiled_units} = { 'Cov/Compiled.pm' => {} };
        is(call($p, '_load_package_by_module_name', 'Cov::Compiled'), 'compiled', 'compiled units load through the compiled path');
        is_deeply(\@seen, ['Cov/Compiled.pm'], 'the require path is used');
    }
    $state->{compiled_units} = {};

    write_file("$dir/PaxCovSrtaOnDisk.pm", "package PaxCovSrtaOnDisk; \$main::PAXCOV_DISK = 7; 1;\n");
    is(call($p, '_load_package_by_module_name', 'PaxCovSrtaOnDisk'), 1, 'modules in the runtime root are required by path');
    is($main::PAXCOV_DISK, 7, 'root module was executed');

    write_file("$dir/PaxCovSrtaBroken.pm", "package PaxCovSrtaBroken; die \"broken module\\n\";\n");
    like(dies(sub { call($p, '_load_package_by_module_name', 'PaxCovSrtaBroken') }), qr/broken module/, 'errors from root modules propagate');

    my $inc_mod = uniq_pkg('Inc');
    $INC{"$inc_mod.pm"} = 1;
    is(call($p, '_load_package_by_module_name', $inc_mod), 1, 'already loaded modules succeed');
    like(dies(sub { call($p, '_load_package_by_module_name', 'PaxCov::Srta::Absent') }), qr/Can't locate PaxCov\/Srta\/Absent\.pm/, 'missing modules die');
}

# ---------------------------------------------------------------- _standalone_executable_path
{
    my ($p, $dir) = fresh({});
    my $exe = write_file("$dir/bin/tool", "#!/bin/sh\n");
    chmod 0755, $exe;
    my $plain = write_file("$dir/bin2/tool", "#!/bin/sh\n");
    chmod 0644, $plain;

    local $ENV{PAX_STANDALONE_EXECUTABLE} = '';
    is(call($p, '_standalone_executable_path'), undef, 'blank executable env gives nothing');
    delete $ENV{PAX_STANDALONE_EXECUTABLE};
    is(call($p, '_standalone_executable_path'), undef, 'unset executable env gives nothing');

    $ENV{PAX_STANDALONE_EXECUTABLE} = $exe;
    is(call($p, '_standalone_executable_path'), abs_path($exe), 'absolute path is resolved');
    $ENV{PAX_STANDALONE_EXECUTABLE} = "$dir/missing-dir/x";
    is(call($p, '_standalone_executable_path'), "$dir/missing-dir/x", 'unresolvable absolute path is returned as is');

    {
        local $ENV{PAX_STANDALONE_EXECUTABLE} = 'bin/tool';
        my $cwd = abs_path('.');
        chdir $dir or die;
        is(call($p, '_standalone_executable_path'), abs_path("$dir/bin/tool"), 'relative path with a slash is resolved');
        $ENV{PAX_STANDALONE_EXECUTABLE} = 'nodir/tool';
        is(call($p, '_standalone_executable_path'), File::Spec->rel2abs('nodir/tool'), 'unresolvable relative path is made absolute');
        chdir $cwd or die;
    }

    $ENV{PAX_STANDALONE_EXECUTABLE} = 'tool';
    {
        local $ENV{PATH} = join(':', '', "$dir/nothing", "$dir/bin2", "$dir/bin");
        is(call($p, '_standalone_executable_path'), abs_path($exe), 'bare names are searched on PATH and non-executables skipped');
    }
    {
        local $ENV{PATH} = "$dir/nothing";
        is(call($p, '_standalone_executable_path'), 'tool', 'bare names missing from PATH are returned as is');
    }
    {
        local $ENV{PATH};
        delete $ENV{PATH};
        is(call($p, '_standalone_executable_path'), 'tool', 'bare names with no PATH are returned as is');
    }

    # resolver stubs: abs_path may fail or return blanks
    no strict 'refs';
    no warnings 'redefine';
    {
        local *{"${p}::abs_path"} = sub { return undef };
        local $ENV{PAX_STANDALONE_EXECUTABLE} = $exe;
        is(call($p, '_standalone_executable_path'), $exe, 'absolute path survives a failing resolver');
        local $ENV{PAX_STANDALONE_EXECUTABLE} = 'a/b';
        is(call($p, '_standalone_executable_path'), File::Spec->rel2abs('a/b'), 'relative path survives a failing resolver');
        local $ENV{PAX_STANDALONE_EXECUTABLE} = 'tool';
        local $ENV{PATH} = "$dir/bin";
        is(call($p, '_standalone_executable_path'), "$dir/bin/tool", 'PATH hit survives a failing resolver');
    }
    {
        local *{"${p}::abs_path"} = sub { return '' };
        local $ENV{PAX_STANDALONE_EXECUTABLE} = $exe;
        is(call($p, '_standalone_executable_path'), $exe, 'absolute path survives a blank resolver result');
        local $ENV{PAX_STANDALONE_EXECUTABLE} = 'a/b';
        is(call($p, '_standalone_executable_path'), File::Spec->rel2abs('a/b'), 'relative path survives a blank resolver result');
        local $ENV{PAX_STANDALONE_EXECUTABLE} = 'tool';
        local $ENV{PATH} = "$dir/bin";
        is(call($p, '_standalone_executable_path'), "$dir/bin/tool", 'PATH hit survives a blank resolver result');
    }
}

# ---------------------------------------------------------------- quoting and wrapper content
{
    my ($p, $dir) = fresh({});
    is(call($p, '_shell_single_quote', undef), "''", 'undef quotes to an empty string');
    is(call($p, '_shell_single_quote', "it's"), q{'it'"'"'s'}, 'embedded quotes are escaped');
    {
        local $ENV{PAX_STANDALONE_EXECUTABLE} = '';
        is(call($p, '_standalone_internal_cli_wrapper_content', 'x'), undef, 'wrapper needs an executable path');
    }
    local $ENV{PAX_STANDALONE_EXECUTABLE} = '/opt/pax-demo';
    is(call($p, '_standalone_internal_cli_wrapper_content', undef), undef, 'wrapper needs a name');
    is(call($p, '_standalone_internal_cli_wrapper_content', ''), undef, 'wrapper needs a non-blank name');
    is(call($p, '_standalone_internal_cli_wrapper_content', 'sh'), "#!/bin/sh\nexec '/opt/pax-demo' --pax-standalone-helper 'sh' \"\$@\"\n", 'wrapper content execs the standalone binary');
}

# ---------------------------------------------------------------- internal CLI class and assets
{
    my ($p, $dir) = fresh({});
    my $state = call($p, '_state');
    no strict 'refs';
    no warnings 'redefine';

    $state->{app_namespace} = 'Some::App';
    is(call($p, '_standalone_internal_cli_class'), 'Some::App::InternalCLI', 'class derives from the app namespace');
    $state->{app_namespace} = undef;
    $state->{manifest} = { code_units => [ 'notahash', { package => '' }, {}, { package => 'A::B' }, { package => 'Z::InternalCLI' } ] };
    is(call($p, '_standalone_internal_cli_class'), 'Z::InternalCLI', 'class is found among unit packages');
    $state->{manifest} = {};
    is(call($p, '_standalone_internal_cli_class'), undef, 'no class when nothing matches');

    # embedded assets
    write_file("$dir/assets/share/helper-a", "A-content");
    $state->{manifest} = { assets => [ 'x', { logical_path => '' }, {}, { logical_path => 'share/other' }, { logical_path => 'share/missing-file' }, { logical_path => 'share/helper-a' } ] };
    is(call($p, '_standalone_embedded_asset_path', undef), undef, 'undef asset name finds nothing');
    is(call($p, '_standalone_embedded_asset_path', ''), undef, 'blank asset name finds nothing');
    is(call($p, '_standalone_embedded_asset_path', 'helper-a'), "$dir/assets/share/helper-a", 'asset found by suffix');
    is(call($p, '_standalone_embedded_asset_path', 'share/helper-a'), "$dir/assets/share/helper-a", 'asset found by full logical path');
    is(call($p, '_standalone_embedded_asset_path', 'share/missing-file'), undef, 'asset whose file is absent is skipped');
    is(call($p, '_standalone_embedded_asset_path', 'nope'), undef, 'unknown asset finds nothing');
    $state->{manifest} = {};
    is(call($p, '_standalone_embedded_asset_path', 'helper-a'), undef, 'no assets finds nothing');

    # class helper driven asset path/content
    my $cls_app = uniq_pkg('CliApp');
    my $cls = "${cls_app}::InternalCLI";
    $state->{app_namespace} = $cls_app;
    $state->{manifest} = { assets => [ { logical_path => 'share/helper-a' } ] };
    my @loaded;
    local *{"${p}::_load_package_by_module_name"} = sub { push @loaded, $_[0]; return 1 };
    is(call($p, '_standalone_internal_cli_asset_path', 'helper-a'), "$dir/assets/share/helper-a", 'embedded asset wins');
    is(call($p, '_standalone_internal_cli_asset_path', 'other'), undef, 'no helper function means no asset path');
    is_deeply(\@loaded, [$cls], 'the internal CLI class is loaded for lookups');
    $state->{app_namespace} = undef;
    $state->{manifest} = {};
    is(call($p, '_standalone_internal_cli_asset_path', 'other'), undef, 'no class means no asset path');
    $state->{app_namespace} = $cls_app;
    *{"${cls}::_helper_asset_path"} = sub { return $_[0] eq 'direct' ? "$dir/assets/direct-file" : undef };
    write_file("$dir/assets/direct-file", "direct-content");
    is(call($p, '_standalone_internal_cli_asset_path', 'direct'), "$dir/assets/direct-file", 'helper function supplies the asset path');

    my ($content, $path) = call($p, '_standalone_internal_cli_asset_content', 'direct');
    is($content, 'direct-content', 'asset content is read from the path');
    is($path, "$dir/assets/direct-file", 'asset path is returned');
    *{"${cls}::_helper_asset_path"} = sub { return "$dir/assets/not-there" };
    like(dies(sub { call($p, '_standalone_internal_cli_asset_content', 'x') }), qr/Unable to read \Q$dir\E\/assets\/not-there/, 'unreadable asset path dies');

    *{"${cls}::_helper_asset_path"} = sub { return undef };
    is_deeply([ call($p, '_standalone_internal_cli_asset_content', 'gen') ], [], 'no generator means no content');
    *{"${cls}::helper_content"} = sub { return $_[0] eq 'gen' ? 'generated:' . ($ENV{PAX_STANDALONE_EXECUTABLE} // 'undef') : ($_[0] eq 'blank' ? '' : undef) };
    local $ENV{PAX_STANDALONE_EXECUTABLE} = '/some/exe';
    is_deeply([ call($p, '_standalone_internal_cli_asset_content', 'gen') ], [ 'generated:', 'gen' ], 'generated content is produced with the executable env blanked');
    is_deeply([ call($p, '_standalone_internal_cli_asset_content', 'blank') ], [], 'blank generated content means no content');
    is_deeply([ call($p, '_standalone_internal_cli_asset_content', 'nothing') ], [], 'undef generated content means no content');
    $state->{app_namespace} = undef;
    is_deeply([ call($p, '_standalone_internal_cli_asset_content', 'gen') ], [], 'no class means no content');
}

# ---------------------------------------------------------------- _share_dist_private_cli_dir
{
    my ($p, $dir) = fresh({});
    is(call($p, '_share_dist_private_cli_dir', undef), undef, 'undef dist gives nothing');
    is(call($p, '_share_dist_private_cli_dir', ''), undef, 'blank dist gives nothing');
    {
        local %INC = %INC;
        delete $INC{'File/ShareDir.pm'};
        local @INC = (sub { die "blocked\n" });
        is(call($p, '_share_dist_private_cli_dir', 'Some-Dist'), undef, 'missing File::ShareDir gives nothing');
    }
    require File::ShareDir;
    is(call($p, '_share_dist_private_cli_dir', 'Pax-No-Such-Dist-Anywhere'), undef, 'unknown dist gives nothing');
    no warnings 'redefine';
    my $root = "$dir/share-root";
    make_path($root);
    local *File::ShareDir::dist_dir = sub { return $root };
    is(call($p, '_share_dist_private_cli_dir', 'D'), undef, 'dist without private-cli gives nothing');
    make_path("$root/private-cli");
    is(call($p, '_share_dist_private_cli_dir', 'D'), "$root/private-cli", 'dist private-cli dir is returned');
    local *File::ShareDir::dist_dir = sub { return "$dir/not-a-dir" };
    is(call($p, '_share_dist_private_cli_dir', 'D'), undef, 'non-directory dist root gives nothing');
}

# ---------------------------------------------------------------- managed helper running
{
    my ($p, $dir) = fresh({});
    no strict 'refs';
    no warnings 'redefine';
    my %assets;
    local *{"${p}::_standalone_internal_cli_asset_content"} = sub { my ($n) = @_; return @{ $assets{$n} || [] } };
    my $delegate = '# _dashboard-core' . "\n" . 'my $c = basename($0);' . "\n" . 'exec { $^X } $^X, $core, $command, @ARGV;' . "\n";

    like(dies(sub { call($p, '_run_standalone_managed_helper', 'none') }), qr/standalone managed helper 'none' is unavailable/, 'unknown helper dies');
    $assets{blank} = [ '', 'p' ];
    like(dies(sub { call($p, '_run_standalone_managed_helper', 'blank') }), qr/'blank' is unavailable/, 'blank helper source dies');

    $assets{plain} = [ '$main::PAXCOV_H = join("|", @ARGV, $0); 11;', '/virt/plain.pl' ];
    {
        local $ENV{PAX_STANDALONE_EXECUTABLE} = '';
        is(call($p, '_run_standalone_managed_helper', 'plain', 'x', 'y'), 11, 'plain helpers are evaluated');
        is($main::PAXCOV_H, 'x|y|/virt/plain.pl', 'plain helper sees its args and $0');
        is($ENV{DEVELOPER_DASHBOARD_ENTRYPOINT}, undef, 'entrypoint env is untouched without an executable');
    }
    {
        my $exe = write_file("$dir/exe", '');
        local $ENV{PAX_STANDALONE_EXECUTABLE} = $exe;
        $assets{plain} = [ '$main::PAXCOV_E = $ENV{DEVELOPER_DASHBOARD_ENTRYPOINT}; 5;', '' ];
        is(call($p, '_run_standalone_managed_helper', 'plain'), 5, 'helper with a blank path runs');
        is($main::PAXCOV_E, abs_path($exe), 'entrypoint env points at the standalone executable');
        $assets{plain} = [ 'undef;', '/virt/u.pl' ];
        is(call($p, '_run_standalone_managed_helper', 'plain'), 0, 'undef helper result becomes zero');
        $assets{plain} = [ 'die "helper boom\n";', '/virt/d.pl' ];
        like(dies(sub { call($p, '_run_standalone_managed_helper', 'plain') }), qr/helper boom/, 'helper errors propagate');
    }

    {
        $assets{nopath} = [ '$main::PAXCOV_N = $0; 3;' ];
        local $SIG{__WARN__} = sub { };
        is(call($p, '_run_standalone_managed_helper', 'nopath'), 3, 'helper without a path still runs');
    }
    $assets{'_dashboard-core'} = [ '$main::PAXCOV_C = join("|", @ARGV); 21;', '/virt/core.pl' ];
    is(call($p, '_run_standalone_managed_helper', '_dashboard-core', 'a'), 21, 'the core helper runs directly');
    is($main::PAXCOV_C, 'a', 'core helper receives only its args');
    $assets{deleg} = [ $delegate, '/virt/deleg' ];
    is(call($p, '_run_standalone_managed_helper', 'deleg', 'a'), 21, 'delegating helpers run the core');
    is($main::PAXCOV_C, 'deleg|a', 'delegating helper name is prepended');
    delete $assets{'_dashboard-core'};
    like(dies(sub { call($p, '_run_standalone_managed_helper', 'deleg') }), qr/helper core is unavailable/, 'missing core dies');
    $assets{'_dashboard-core'} = [ '', '/virt/core.pl' ];
    like(dies(sub { call($p, '_run_standalone_managed_helper', 'deleg') }), qr/helper core is unavailable/, 'blank core dies');

    is(call($p, '_direct_standalone_helper_name_from_path', undef), undef, 'undef helper path has no name');
    is(call($p, '_direct_standalone_helper_name_from_path', ''), undef, 'blank helper path has no name');
    is(call($p, '_direct_standalone_helper_name_from_path', '/a/b/tool'), 'tool', 'helper name is the basename');
    {
        local *{"${p}::basename"} = sub { return '' };
        is(call($p, '_direct_standalone_helper_name_from_path', '/a/'), undef, 'blank basename has no name');
        local *{"${p}::basename"} = sub { return undef };
        is(call($p, '_direct_standalone_helper_name_from_path', '/a/'), undef, 'undef basename has no name');
    }

    is(call($p, '_standalone_helper_delegates_to_dashboard_core', undef), 0, 'undef source does not delegate');
    is(call($p, '_standalone_helper_delegates_to_dashboard_core', ''), 0, 'blank source does not delegate');
    is(call($p, '_standalone_helper_delegates_to_dashboard_core', 'nothing'), 0, 'unrelated source does not delegate');
    is(call($p, '_standalone_helper_delegates_to_dashboard_core', '_dashboard-core'), 0, 'mention alone does not delegate');
    is(call($p, '_standalone_helper_delegates_to_dashboard_core', '_dashboard-core basename($0)'), 0, 'two of three markers do not delegate');
    is(call($p, '_standalone_helper_delegates_to_dashboard_core', $delegate), 1, 'all markers delegate');
}

# ---------------------------------------------------------------- require hook
{
    my $app = uniq_pkg('HookNew');
    my $leg = uniq_pkg('HookOld');
    my ($p, $dir) = fresh({
        app => { namespace => $app, compat => { legacy_namespace => $leg } },
        code_units => [
            { packaging => 'compiled_pcu_v1', require_path => "$app.pm", package => $app, logical_path => "$app.pcu.json" },
            { packaging => 'compiled_pcu_v1', require_path => "${app}Bad.pm", package => "${app}Bad", logical_path => "${app}Bad.pcu.json" },
        ],
    });
    my $state = call($p, '_state');
    write_json("$dir/code/$app.pcu.json", { package => $app, subs => [], initializers => [], unsupported_subs => [] });
    write_file("$dir/code/${app}Bad.pcu.json", 'not json at all');
    my $lib = write_file("$dir/lib/PaxCovHookPlain.pm", "package PaxCovHookPlain; 'plain-value';\n");

    {
        local *CORE::GLOBAL::require;
        call($p, '_install_require_hook');
        my $hook = \&CORE::GLOBAL::require;
        is($state->{require_hook_installed}, 1, 'hook install is recorded');
        call($p, '_install_require_hook');
        is(\&CORE::GLOBAL::require, $hook, 'second install keeps the same hook');

        like(dies(sub { $hook->(undef) }), qr/require target missing/, 'hook rejects an undef target');
        is($hook->(5.006), 1, 'hook passes version requires through');
        is($hook->('strict.pm'), 1, 'hook passes unmapped modules to the real require');
        is($hook->($lib), 'plain-value', 'hook returns the real require result for files');
        like(dies(sub { $hook->('PaxCov/Srta/NoSuch.pm') }), qr/Can't locate PaxCov\/Srta\/NoSuch\.pm/, 'hook propagates require failures');
        is($hook->("$leg.pm"), 1, 'legacy names load the compiled app unit');
        is($INC{"$app.pm"}, "$dir/code/$app.pm", 'compiled unit is recorded in %INC with its placeholder file');
        ok(-f "$dir/code/$app.pm", 'placeholder source file exists');
    }
    delete $INC{"$app.pm"};

    # direct _load_compiled_require paths
    my $trace_out;
    {
        local $ENV{PAX_STANDALONE_TRACE} = 1;
        (undef, $trace_out) = capture {
            is(call($p, '_load_compiled_require', "$app.pm"), 1, 'compiled require loads');
            is(call($p, '_load_compiled_require', "$app.pm"), 1, 'already loaded units short-circuit');
            delete $INC{"$app.pm"};
            $state->{loading_require}{"$app.pm"} = 1;
            is(call($p, '_load_compiled_require', "$app.pm"), 1, 'cycles short-circuit');
            delete $state->{loading_require}{"$app.pm"};
        };
    }
    delete $INC{"$app.pm"};
    is(call($p, '_load_compiled_require', "$leg.pm"), 1, 'legacy names resolve to the compiled app unit');
    delete $INC{"$app.pm"};
    like($trace_out, qr/require cycle short-circuit/, 'cycle is traced');
    like($trace_out, qr/require done/, 'completion is traced');
    delete $INC{"$app.pm"};
    is(call($p, '_load_compiled_require', ''), undef, 'blank target loads nothing');
    is(call($p, '_load_compiled_require', 'Not/Compiled.pm'), undef, 'unknown target loads nothing');

    like(dies(sub { call($p, '_load_compiled_require', "${app}Bad.pm") }), qr/./, 'failing units die');
    ok(!exists $INC{"${app}Bad.pm"}, 'failed unit is removed from %INC');
    {
        no strict 'refs';
        no warnings 'redefine';
        local *{"${p}::_ensure_virtual_source_file"} = sub { $INC{"${app}Bad.pm"} = '/previous'; return '/virtual' };
        like(dies(sub { call($p, '_load_compiled_require', "${app}Bad.pm") }), qr/./, 'failing units die again');
        is($INC{"${app}Bad.pm"}, '/previous', 'previous %INC entry is restored');
        delete $INC{"${app}Bad.pm"};
    }
    $state->{app_namespace} = $app;
    $state->{legacy_namespace} = $leg;
    delete $INC{"$app.pm"};
}

# ---------------------------------------------------------------- pending wrappers
{
    my $region = uniq_pkg('Region');
    my $log = "$BASE/native-hit.log";
    my ($p, $dir) = fresh({
        runtime_epochs => { e => 1 },
        native_dispatch => [
            { region_name => "${region}::add", region_id => 'r1', executable_logical_path => 'bin/add.probe', guards => [ { g => 1 } ], deopt => { d => 1 } },
            { region_name => "${region}::plain", region_id => 'r2', executable_logical_path => 'bin/plain.probe' },
            { region_name => "${region}::nopath" },
            { region_name => "${region}::undefined", executable_logical_path => 'x' },
            { region_name => 'nocolons', executable_logical_path => 'x' },
            { note => 'no region name' },
        ],
    });
    my $state = call($p, '_state');
    no strict 'refs';
    no warnings 'redefine';
    for my $name (qw(add plain nopath)) {
        *{"${region}::$name"} = sub { return "orig:$name:" . join('+', map { $_ // 'u' } @_) };
    }
    write_file("$dir/bin/add.probe", 'probe');
    chmod 0644, "$dir/bin/add.probe";

    call($p, '_install_pending_wrappers');
    is_deeply([ sort keys %{ $state->{wrapped} } ], [ "${region}::add", "${region}::plain" ], 'only wrappable regions are wrapped');
    my $wrapper = \&{"${region}::add"};
    call($p, '_install_pending_wrappers');
    is(\&{"${region}::add"}, $wrapper, 'wrapped regions are not wrapped twice');

    my @guard_calls;
    my $guard_status = 'native_allowed';
    my %run_result = (status => 'ok', value => 99);
    my @runs;
    require PAX::GuardManager;
    local *PAX::GuardManager::validate_or_deopt = sub {
        my ($self, $unit, %args) = @_;
        push @guard_calls, { epochs => $self->{epochs}, unit => $unit, args => \%args };
        return { status => $guard_status };
    };
    *PaxCovSrta::Runner::run_i64_binary = sub { my ($self, %a) = @_; push @runs, \%a; return { %run_result } };
    $state->{native_runner} = bless {}, 'PaxCovSrta::Runner';

    is(&{"${region}::add"}(1), 'orig:add:1', 'ineligible calls run the original');
    is(scalar @guard_calls, 0, 'ineligible calls skip the guard');
    is(&{"${region}::add"}(2, 3), 99, 'native result is returned');
    is($guard_calls[0]{epochs}, $state->{manifest}{runtime_epochs}, 'guard manager receives runtime epochs');
    is_deeply($guard_calls[0]{unit}, { region_id => 'r1', region_name => "${region}::add", guards => [ { g => 1 } ], deopt => { d => 1 } }, 'guard unit carries region metadata');
    is_deeply($guard_calls[0]{args}, { args => [ 2, 3 ], context => 'scalar' }, 'guard args carry the two operands');
    is($runs[0]{path}, "$dir/bin/add.probe", 'native probe path is built under the code root');
    is(sprintf('%04o', (stat "$dir/bin/add.probe")[2] & 07777), '0700', 'probe is made executable');
    is(&{"${region}::plain"}(4, 5), 99, 'region without guards uses defaults');
    is_deeply($guard_calls[1]{unit}{guards}, [], 'missing guards default to empty');
    is_deeply($guard_calls[1]{unit}{deopt}, {}, 'missing deopt defaults to empty');
    is(&{"${region}::plain"}(4, 5), 99, 'missing probe file is tolerated');

    {
        local $ENV{PAX_STANDALONE_NATIVE_HIT_LOG} = $log;
        is(&{"${region}::add"}(6, 7), 99, 'native hit with logging');
        open my $fh, '<', $log or die;
        my @lines = <$fh>;
        close $fh;
        is_deeply(\@lines, [ "${region}::add\n" ], 'native hit is logged');
    }

    %run_result = (status => 'ok', value => undef);
    is(&{"${region}::add"}(1, 2), 'orig:add:1+2', 'native result without a value falls back');
    %run_result = (status => 'error');
    is(&{"${region}::add"}(1, 2), 'orig:add:1+2', 'native error falls back');
    %run_result = ();
    is(&{"${region}::add"}(1, 2), 'orig:add:1+2', 'empty native result falls back');
    %run_result = (status => 'ok', value => 1);
    $guard_status = 'deopt';
    is(&{"${region}::add"}(1, 2), 'orig:add:1+2', 'denied guard falls back');
    $guard_status = undef;
    is(&{"${region}::add"}(1, 2), 'orig:add:1+2', 'missing guard status falls back');

    # a manifest without runtime epochs
    my ($p2) = fresh({ native_dispatch => [ { region_name => "${region}::plain2", executable_logical_path => 'x/y' } ] });
    my $s2 = call($p2, '_state');
    *{"${region}::plain2"} = sub { 'o2' };
    call($p2, '_install_pending_wrappers');
    $s2->{native_runner} = bless {}, 'PaxCovSrta::Runner';
    @guard_calls = ();
    $guard_status = 'deopt';
    is(&{"${region}::plain2"}(1, 2), 'o2', 'wrapper without runtime epochs falls back');
    is_deeply($guard_calls[0]{epochs}, {}, 'missing runtime epochs default to empty');

    is(call($p, '_eligible_i64_args', [1]), 0, 'wrong argument count is not eligible');
    is(call($p, '_eligible_i64_args', [ undef, 1 ]), 0, 'undef first argument is not eligible');
    is(call($p, '_eligible_i64_args', [ 1, undef ]), 0, 'undef second argument is not eligible');
    is(call($p, '_eligible_i64_args', [ 'a', 1 ]), 0, 'non-numeric first argument is not eligible');
    is(call($p, '_eligible_i64_args', [ 1, 'b' ]), 0, 'non-numeric second argument is not eligible');
    is(call($p, '_eligible_i64_args', [ -4, 12 ]), 1, 'integers are eligible');
}

# ---------------------------------------------------------------- compiled unit loading
{
    my ($p, $dir) = fresh({});
    my $state = call($p, '_state');
    no strict 'refs';
    no warnings 'redefine';
    my @events;
    local *{"${p}::_load_residual_module"} = sub { push @events, [ 'module', $_[1]{package} ]; return };
    local *{"${p}::_apply_initializer"} = sub { push @events, [ 'init', $_[0]{op} ]; return };
    local *{"${p}::_install_compiled_sub_lazily"} = sub { push @events, [ 'sub', @_[ 0, 1 ] && ($_[0], $_[1]{name}) ]; return };
    local *{"${p}::_install_residual_stubs"} = sub { push @events, [ 'stubs', scalar @{ $_[1]{unsupported_subs} } ]; return };

    like(dies(sub { call($p, '_load_compiled_unit', { require_path => 'x', logical_path => 'absent.json' }) }), qr/cannot read compiled unit \Q$dir\E\/code\/absent\.json/, 'missing unit file dies');
    write_json("$dir/code/mod.json", { package => 'M', residual_mode => 'module' });
    call($p, '_load_compiled_unit', { logical_path => 'mod.json' });
    is_deeply(\@events, [ [ 'module', 'M' ] ], 'residual module records take the module path');
    @events = ();
    write_json("$dir/code/modsubs.json", { package => 'M', residual_mode => 'module', subs => [ { name => 'adapter' }, { name => 'other' } ] });
    call($p, '_load_compiled_unit', { logical_path => 'modsubs.json' });
    is_deeply(\@events, [ [ 'module', 'M' ], [ 'sub', 'M', 'adapter' ], [ 'sub', 'M', 'other' ] ], 'a module-mode unit puts its vouched handlers back over the real definitions');
    @events = ();
    write_json("$dir/code/full.json", {
        package => 'F',
        initializers => [ { op => 'i1' }, { op => 'i2' } ],
        subs => [ { name => 's1' } ],
        unsupported_subs => [ 'F::u1', 'F::u2' ],
    });
    call($p, '_load_compiled_unit', { require_path => 'F.pm', logical_path => 'full.json' });
    is_deeply(\@events, [ [ 'init', 'i1' ], [ 'init', 'i2' ], [ 'sub', 'F', 's1' ], [ 'stubs', 2 ] ], 'initializers, subs and residual stubs are installed in order');
    @events = ();
    write_json("$dir/code/empty.json", { package => 'E', residual_mode => 'other' });
    call($p, '_load_compiled_unit', { logical_path => 'empty.json' });
    is_deeply(\@events, [], 'empty records install nothing');
    {
        local $SIG{__WARN__} = sub { };
        like(dies(sub { call($p, '_load_compiled_unit', {}) }), qr/./, 'a unit with no paths cannot be loaded');
    }
}

# ---------------------------------------------------------------- virtual source files
{
    my ($p, $dir) = fresh({ entrypoint => { logical_path => 'ep/main.script.json' } });
    my $v = sub { call($p, '_virtual_source_logical_path', @_) };
    is($v->({ logical_path => 'a/b.pcu.json', require_path => 'A/B.pm' }), 'a/b.pm', 'pcu units map to .pm placeholders');
    is($v->({ logical_path => 'a/b.json', require_path => 'A/B.pm' }), File::Spec->catfile('virtual', 'A', 'B.pm'), 'other units with require paths live under virtual/');
    is($v->({ logical_path => 'x.dashboard.json' }), 'x.pl', 'dashboard units map to .pl');
    is($v->({ logical_path => 'x.dispatch.json', require_path => '' }), 'x.pl', 'dispatch units map to .pl');
    is($v->({ logical_path => 'x.script.json' }), 'x.pl', 'script units map to .pl');
    is($v->({ logical_path => 'x.other' }), File::Spec->catfile('virtual', 'entrypoint.pl'), 'unknown units share the entrypoint placeholder');
    is($v->({}), File::Spec->catfile('virtual', 'entrypoint.pl'), 'unit without paths shares the entrypoint placeholder');

    my $path = call($p, '_ensure_virtual_source_file', { logical_path => 'q/r.pcu.json', require_path => 'Q/R.pm' });
    is($path, "$dir/code/q/r.pm", 'placeholder path is under the code root');
    open my $fh, '<', $path or die;
    my $text = do { local $/; <$fh> };
    close $fh;
    is($text, "# PAX compiled unit placeholder for Q/R.pm\n1;\n", 'placeholder text names the require path');
    write_file($path, 'custom');
    is(call($p, '_ensure_virtual_source_file', { logical_path => 'q/r.pcu.json', require_path => 'Q/R.pm' }), $path, 'existing placeholders are kept');
    is(do { open my $h, '<', $path or die; local $/; <$h> }, 'custom', 'existing placeholder is not rewritten');
    my $sibling = call($p, '_ensure_virtual_source_file', { logical_path => 'q/s.pcu.json', require_path => 'Q/S.pm' });
    ok(-f $sibling, 'placeholder in an existing directory is created');
    my $logical_only = call($p, '_ensure_virtual_source_file', { logical_path => 'z/only.dispatch.json' });
    open my $lh, '<', $logical_only or die;
    like(do { local $/; <$lh> }, qr/placeholder for z\/only\.dispatch\.json/, 'placeholder falls back to the logical path');
    my $unknown = call($p, '_ensure_virtual_source_file', {});
    open my $uh, '<', $unknown or die;
    like(do { local $/; <$uh> }, qr/placeholder for unknown/, 'placeholder falls back to unknown');
    make_path("$dir/code/dirhere.pm");
    like(dies(sub { call($p, '_ensure_virtual_source_file', { logical_path => 'dirhere.pcu.json', require_path => 'D.pm' }) }), qr/cannot write virtual source file/, 'unwritable placeholder dies');

    is(call($p, '_virtual_source_path', { logical_path => 'q/r.pcu.json', require_path => 'Q/R.pm' }, {}), $path, 'virtual source path reuses the placeholder');
    is(call($p, '_virtual_entrypoint_path', 'whatever'), "$dir/code/ep/main.pl", 'entrypoint path comes from the manifest');
    call($p, '_state')->{manifest} = undef;
    is(call($p, '_virtual_entrypoint_path', 'ep2/run.script.json'), "$dir/code/ep2/run.pl", 'entrypoint path falls back to the argument');
}

# ---------------------------------------------------------------- _run_entrypoint
{
    my ($p, $dir) = fresh({});
    no strict 'refs';
    no warnings 'redefine';
    my @seen;
    local *{"${p}::_run_service_dispatch_unit"} = sub { push @seen, [ 'service', $_[0] ]; return 'rv:_run_service_dispatch_unit' };
    local *{"${p}::_run_cli_router_unit"} = sub { push @seen, [ 'router', $_[0] ]; return 'rv:_run_cli_router_unit' };
    local *{"${p}::_run_dispatch_script_unit"} = sub { push @seen, [ 'dispatch', $_[0] ]; return 'rv:_run_dispatch_script_unit' };
    local *{"${p}::_run_script_unit"} = sub { push @seen, [ 'script', $_[0] ]; return 'rv:_run_script_unit' };
    is(call($p, '_run_entrypoint', 'a.service.json'), 'rv:_run_service_dispatch_unit', 'service units dispatch');
    is(call($p, '_run_entrypoint', 'a.cli-router.json'), 'rv:_run_cli_router_unit', 'router units dispatch');
    is(call($p, '_run_entrypoint', 'a.dispatch.json'), 'rv:_run_dispatch_script_unit', 'dispatch units dispatch');
    is(call($p, '_run_entrypoint', 'a.script.json'), 'rv:_run_script_unit', 'script units dispatch');
    is(scalar @seen, 4, 'each unit kind reached its runner');

    is(call($p, '_run_entrypoint', write_file("$dir/ok.pl", "17;\n")), 17, 'plain files are executed with do');
    like(dies(sub { call($p, '_run_entrypoint', write_file("$dir/die.pl", "die qq{plain boom\\n};\n")) }), qr/plain boom/, 'errors in plain files propagate');
    like(dies(sub { call($p, '_run_entrypoint', "$dir/missing.pl") }), qr/failed to load \Q$dir\E\/missing\.pl/, 'missing files die');
    is(call($p, '_run_entrypoint', write_file("$dir/undef.pl", "\$! = 0; undef;\n")), undef, 'an undef result without an error is returned');
}

# ---------------------------------------------------------------- service dispatch unit
{
    my ($p, $dir) = fresh({ entrypoint => { logical_path => 'svc.service.json' } });
    no strict 'refs';
    no warnings 'redefine';
    my $svc_app = uniq_pkg('SvcApp');
    my $svc_server = uniq_pkg('SvcServer');
    my @built;
    my @ran;
    *{"${svc_app}::make_app"} = sub { my ($class, %a) = @_; push @built, [ $class, \%a ]; return 'APP' };
    *{"${svc_server}::new"} = sub { return bless {}, $_[0] };
    *{"${svc_server}::run"} = sub { my ($self, $app, $opts) = @_; push @ran, [ $app, $opts ]; return };
    $INC{ join('/', split /::/, $svc_app) . '.pm' } = 1;
    $INC{ join('/', split /::/, $svc_server) . '.pm' } = 1;
    my $unit = "$dir/svc.service.json";

    like(dies(sub { call($p, '_run_service_dispatch_unit', "$dir/none.json") }), qr/cannot read service dispatch unit/, 'missing unit dies');

    write_json($unit, { version => '1.2.3' });
    for my $argv ([], ['']) {
        local @ARGV = @$argv;
        my ($out) = capture { my ($code) = trapped_exit(sub { call($p, '_run_service_dispatch_unit', $unit) }); is($code, 0, 'version exits zero') };
        is($out, "1.2.3\n", 'version is the default command and prints the record version');
    }
    write_json($unit, {});
    {
        local @ARGV = ('version');
        my ($out) = capture { trapped_exit(sub { call($p, '_run_service_dispatch_unit', $unit) }) };
        is($out, "0.0.0\n", 'missing version prints 0.0.0');
    }
    {
        local @ARGV = ('bogus');
        like(dies(sub { call($p, '_run_service_dispatch_unit', $unit) }), qr/unknown command: bogus/, 'unknown commands die');
    }

    write_json($unit, { app_module => $svc_app, server_module => $svc_server, builder_method => 'make_app' });
    {
        local @ARGV = ('serve', '--host', '0.0.0.0', '--port', '8080');
        local $ENV{PAX_EMBEDDED_ASSET_ROOT} = '/assets';
        is(call($p, '_run_service_dispatch_unit', $unit), 0, 'serve returns zero after the server stops');
        is_deeply($built[-1], [ $svc_app, { asset_root => '/assets' } ], 'app is built with the asset root');
        is_deeply($ran[-1], [ 'APP', { host => '0.0.0.0', port => 8080, listen => ['0.0.0.0:8080'], workers => 1 } ], 'server runs with the parsed options');
    }
    {
        local @ARGV = ('serve');
        local $ENV{PAX_EMBEDDED_ASSET_ROOT};
        delete $ENV{PAX_EMBEDDED_ASSET_ROOT};
        call($p, '_run_service_dispatch_unit', $unit);
        is($built[-1][1]{asset_root}, File::Spec->catdir("$dir/code/virtual", '..', 'share'), 'asset root defaults beside the virtual entrypoint');
        is_deeply($ran[-1][1], { host => '127.0.0.1', port => 5000, listen => ['127.0.0.1:5000'], workers => 1 }, 'defaults are used without options');
    }
    for my $bad (['--host'], ['--port'], ['--wat']) {
        local @ARGV = ('serve', @$bad);
        local $ENV{PAX_EMBEDDED_ASSET_ROOT} = '/assets';
        like(dies(sub { call($p, '_run_service_dispatch_unit', $unit) }), qr/requires a value|unexpected argument: --wat/, "serve rejects @$bad");
    }

    # default builder method
    *{"${svc_app}::build_psgi_app"} = sub { push @built, [ 'default', {} ]; return 'APP2' };
    write_json($unit, { app_module => $svc_app, server_module => $svc_server });
    {
        local @ARGV = ('serve');
        local $ENV{PAX_EMBEDDED_ASSET_ROOT} = '/assets';
        call($p, '_run_service_dispatch_unit', $unit);
        is($built[-1][0], 'default', 'builder method defaults to build_psgi_app');
        is($ran[-1][0], 'APP2', 'default builder result reaches the server');
    }

    # serve when the app module is a compiled unit
    {
        write_json($unit, { app_module => $svc_app, server_module => $svc_server });
        my @loads;
        local *{"${p}::_load_compiled_require"} = sub { push @loads, $_[0]; return 1 };
        local @ARGV = ('serve');
        local $ENV{PAX_EMBEDDED_ASSET_ROOT} = '/assets';
        call($p, '_run_service_dispatch_unit', $unit);
        is($loads[0], join('/', split /::/, $svc_app) . '.pm', 'compiled app modules are loaded through the compiled path');
    }
    # missing server module: the empty require path fails first
    {
        write_json($unit, { app_module => $svc_app });
        local @ARGV = ('serve');
        local $ENV{PAX_EMBEDDED_ASSET_ROOT} = '/assets';
        like(dies(sub { call($p, '_run_service_dispatch_unit', $unit) }), qr/Missing or undefined argument to require/, 'missing server module dies at its require');
    }
    # missing app module
    {
        write_json($unit, { server_module => $svc_server });
        local *{"${p}::_load_compiled_require"} = sub { return 1 };
        local @ARGV = ('serve');
        local $ENV{PAX_EMBEDDED_ASSET_ROOT} = '/assets';
        like(dies(sub { call($p, '_run_service_dispatch_unit', $unit) }), qr/service dispatch missing app module/, 'missing app module dies');
    }
}

# ---------------------------------------------------------------- cli router unit
{
    my ($p, $dir) = fresh({ entrypoint => { logical_path => 'router.cli-router.json' } });
    no strict 'refs';
    no warnings 'redefine';
    my @usage;
    local *{"${p}::_router_usage"} = sub { push @usage, [ $_[1], [ @{ $_[2] } ] ]; die "usage:$_[1]\n" };
    my $unit = "$dir/router.cli-router.json";
    my $vpath = "$dir/code/virtual/entrypoint.pl";

    like(dies(sub { call($p, '_run_cli_router_unit', "$dir/none") }), qr/cannot read cli router unit/, 'missing router unit dies');

    # bootstrap, usage file, prelude
    write_json($unit, {
        bootstrap_source => '$main::PAXCOV_BOOT = "booted"; 1;',
        usage_source => '# usage text',
        prelude_source => '$main::PAXCOV_PRELUDE = "prelude:" . join(",", @ARGV); 1;',
    });
    {
        local @ARGV = ('help');
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/usage:help/, 'help prints the long usage');
        is($main::PAXCOV_BOOT, 'booted', 'bootstrap source is evaluated');
        is($main::PAXCOV_PRELUDE, 'prelude:', 'prelude source is evaluated after the command is consumed');
        is_deeply(\@usage, [ [ 'help', [ -input => "$vpath.usage.pl" ] ] ], 'usage input points at the written usage file');
        ok(-f "$vpath.usage.pl", 'usage file was written');
        @usage = ();
    }
    {
        local @ARGV = ('--help');
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/usage:help/, '--help prints the long usage');
        is_deeply($usage[0][1], [ -input => "$vpath.usage.pl" ], 'existing usage file is reused');
        @usage = ();
        local @ARGV = ('-h');
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/usage:help/, '-h prints the long usage');
        @usage = ();
        local @ARGV = ();
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/usage:short/, 'no command prints the short usage');
        @usage = ();
    }

    write_json($unit, { prelude_source => '' });
    {
        local @ARGV = ('help');
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/usage:help/, 'blank prelude source is treated as absent');
    }

    # prelude errors, bootstrap errors
    write_json($unit, { prelude_source => 'die "prelude boom\n";' });
    {
        local @ARGV = ('x');
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/prelude boom/, 'prelude errors propagate');
    }
    write_json($unit, { bootstrap_source => 'die "boot boom\n";' });
    {
        local @ARGV = ('x');
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/boot boom/, 'bootstrap errors propagate');
    }

    # no prelude: runtime env helpers
    my @env_calls;
    write_json($unit, { bootstrap_source => '', usage_source => '' });
    {
        local @ARGV = ('help', 'more');
        local *main::_load_runtime_env = sub { push @env_calls, ['load']; return };
        local *main::_prime_command_result_env = sub { push @env_calls, [ 'prime', @_ ]; return };
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/usage:help/, 'router without prelude reaches usage');
        is_deeply(\@env_calls, [ ['load'], [ 'prime', 'help', 'more' ] ], 'runtime env helpers are called with the command and args');
        is_deeply($usage[-1][1], [], 'blank usage source adds no usage input');
        @env_calls = ();
        local @ARGV = ();
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/usage:short/, 'router without a command reaches the short usage');
        is_deeply(\@env_calls, [ ['load'] ], 'priming is skipped without a command');
    }
    {
        local @ARGV = ('help');
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/usage:help/, 'router without runtime env helpers still works');
    }

    # usage file cannot be written
    make_path("$vpath.usage.pl.d");
    write_json($unit, { usage_source => 'text' });
    unlink "$vpath.usage.pl";
    make_path("$vpath.usage.pl");
    {
        local @ARGV = ('help');
        like(dies(sub { call($p, '_run_cli_router_unit', $unit) }), qr/usage:help/, 'router tolerates an unwritable usage file');
        is_deeply($usage[-1][1], [], 'unwritable usage file adds no usage input');
    }
}

done_testing;
