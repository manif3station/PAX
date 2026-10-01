use strict;
use warnings;
no warnings 'once';
use Test::More;
use Capture::Tiny ();
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/../lib";

# The runtime calls exit() from router/dispatch/script runners. Override it
# before the module compiles so a flag can turn exit into a catchable exception.
our $TRAP_EXIT = 0;

BEGIN {
    no warnings 'once';
    *CORE::GLOBAL::exit = sub {
        my $code = @_ ? $_[0] : 0;
        die bless({ code => $code }, 'PaxCovExit') if $main::TRAP_EXIT;
        CORE::exit($code);
    };
}

use PAX::StandaloneRuntime;

=pod

=head1 NAME

t/cov_srtb_runtime_units.t - in-process coverage of the standalone runtime unit runners

=head1 DESCRIPTION

Drives the second half of C<PAX::StandaloneRuntime> in-process with a fabricated
runtime state and tempdir-backed units: the CLI router, dispatch-script and
script unit runners, JSON decoding, initializers, native-shape helpers, lazy
compiled-sub stubs, residual stubs, virtual source paths, template rendering,
and the lazily compiled op-handler loader.

=head1 WHY IT EXISTS

The runtime normally executes inside a standalone binary that Devel::Cover never
sees, so these paths need direct in-process tests with collaborators replaced.

=cut

my $root = tempdir('pax-cov-srtb-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($path, $text)
# Writes a fixture file, creating parent directories first.
# Input: destination path and text. Output: the path written.
sub write_file {
    my ($path, $text) = @_;
    my ($volume, $dir) = File::Spec->splitpath($path);
    make_path($dir) if length $dir && !-d $dir;
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh or die "cannot close $path: $!";
    return $path;
}

# write_json($path, $data)
# Writes a data structure as a JSON unit file.
# Input: destination path and data. Output: the path written.
sub write_json {
    my ($path, $data) = @_;
    return write_file($path, JSON::PP->new->canonical(1)->encode($data));
}

# run_catch($code, @argv)
# Runs code with exit trapped and output captured.
# Input: code ref and the @ARGV to run under. Output: hash ref with out, err, exit, error, ret.
sub run_catch {
    my ($code, @argv) = @_;
    my %r;
    local $TRAP_EXIT = 1;
    local @ARGV = @argv;
    ($r{out}, $r{err}) = Capture::Tiny::capture(sub {
        my $ok = eval { $r{ret} = [ $code->() ]; 1 };
        if (!$ok) {
            my $e = $@;
            if (ref($e) eq 'PaxCovExit') { $r{exit} = $e->{code} }
            else { $r{error} = $e }
        }
    });
    return \%r;
}

# PaxCovFakeRunner::run_i64_binary($self, %args)
# Records the call and returns the canned result.
# Input: runner object and named arguments. Output: canned result hash.
sub PaxCovFakeRunner::run_i64_binary {
    my ($self, %args) = @_;
    push @{ $self->{calls} }, \%args;
    return $self->{result};
}

# The runtime state is faked so no manifest or environment is needed.
my $STATE = {
    manifest => {
        entrypoint => { logical_path => 'ep.script.json' },
        code_units => [],
    },
    root => $root,
    by_region => {},
    native_runner => undef,
    residual_loaded => {},
    residual_bootstrap_loaded => {},
    compiled_units => {},
};
{
    no warnings 'redefine';
    *PAX::StandaloneRuntime::_state = sub { return $STATE };
}

# Replace the DATA section reader's source with the real handlers plus fakes so
# the compile-failure and multi-op paths of the lazy loader can be exercised.
my $DATA_TEXT;
{
    no strict 'refs';
    my $glob = \*{'PAX::StandaloneRuntime::DATA'};
    $DATA_TEXT = do { local $/; <$glob> };
    close $glob;
    $DATA_TEXT .= "#\@\@PAX_OP pcov_bad\nthis is not ( valid perl\n"
        . "#\@\@PAX_OP pcov_a pcov_b\n"
        . "        \$impl = sub { return \"pcov:\$name\" };\n"
        . "        return PAX::StandaloneRuntime::_install_sub_impl(\$package, \$name, \$sub->{prototype}, \$impl);\n";
    open $glob, '<', \$DATA_TEXT or die "cannot reopen DATA: $!";
}

# JSON decoding: block JSON::XS on first use so the JSON::PP fallback is taken.
{
    delete local $INC{'JSON/XS.pm'};
    local @INC = (sub { return unless $_[1] eq 'JSON/XS.pm'; die "JSON::XS blocked for test\n" }, @INC);
    my $decoder = PAX::StandaloneRuntime::_runtime_json_decoder();
    isa_ok($decoder, 'JSON::PP', 'decoder falls back to JSON::PP without JSON::XS');
    is(PAX::StandaloneRuntime::_runtime_json_decoder(), $decoder, 'decoder is cached');
    is_deeply(PAX::StandaloneRuntime::_runtime_json_decode('{"a":[1,2]}'), { a => [1, 2] }, 'decode works');
}

# Main-package collaborators the router calls through _code_for.
our (@CALLS, @EXEC, @POD, %BUILTIN, %CUSTOM, %SKILL, @MANAGED);
{
    no warnings 'once';
    *main::_load_runtime_env = sub { push @CALLS, 'env' };
    *main::_prime_command_result_env = sub { push @CALLS, ['prime', @_] };
    *main::_builtin_helper_path = sub { $BUILTIN{ $_[0] } };
    *main::_custom_command_path = sub { $CUSTOM{ $_[0] } };
    *main::_skill_dotted_command_parts = sub { @{ $SKILL{ $_[0] } || [] } };
    *main::_exec_switchboard_command = sub { push @EXEC, [@_]; return 'execed' };
    *main::pod2usage = sub { my %a = @_; push @POD, \%a; exit($a{-exitval}) };
    *main::pcov_target = sub { return 'tv:' . join(',', @_) };
}
{
    no warnings 'once';
    $INC{'PaxCovVer.pm'} = 1;
    $PaxCovVer::VERSION = '9.87';
    $INC{'PaxCovSuggest.pm'} = 1;
}

# PaxCovSuggest::new($class)
# Builds the fake suggestion helper.
# Input: class name. Output: object.
sub PaxCovSuggest::new { return bless {}, shift }

# PaxCovSuggest::unknown_command_message($self, $cmd)
# Returns the fake unknown-command text.
# Input: object and command. Output: message string.
sub PaxCovSuggest::unknown_command_message { return "unknown: $_[1]\n" }

my $router_file = "$root/r.cli-router.json";

# router($record, @argv)
# Writes a router record and runs the router unit under run_catch.
# Input: record hash and argv. Output: run_catch result.
sub router {
    my ($record, @argv) = @_;
    write_json($router_file, $record);
    return run_catch(sub { PAX::StandaloneRuntime::_run_cli_router_unit($router_file) }, @argv);
}

{
    no warnings 'redefine';
    local *PAX::StandaloneRuntime::_run_standalone_managed_helper = sub { push @MANAGED, [@_]; return 'managed' };

    # Empty command prints the rendered short usage; missing stdout text is skipped.
    my $short = { short => { stdout => "S-out\n", stderr => "S-err\n", exit => 2 } };
    my $r = router({
        bootstrap_source => '$main::PAXCOV_BOOT = 1;',
        usage_source     => "=head1 NAME\n",
        usage_outputs    => $short,
    });
    is($r->{exit}, 2, 'rendered short usage exits with recorded code');
    is($r->{out}, "S-out\n", 'rendered stdout replayed');
    is($r->{err}, "S-err\n", 'rendered stderr replayed');
    is($main::PAXCOV_BOOT, 1, 'router bootstrap source evaluated');

    $r = router({ usage_outputs => { short => { stdout => '', stderr => undef } } });
    is($r->{exit}, 0, 'rendered usage without exit code exits 0');
    is($r->{out} . $r->{err}, '', 'empty rendered streams print nothing');

    # Help forms use the rendered help text.
    for my $word (qw(help --help -h)) {
        $r = router({ usage_outputs => { help => { stdout => "H\n", exit => 0 } } }, $word);
        is($r->{out}, "H\n", "rendered help for $word");
    }

    # Without rendered text pod2usage is called.
    @POD = ();
    $r = router({ usage_source => "x\n" });
    is($r->{exit}, 1, 'short usage via pod2usage exits 1');
    is($POD[-1]{-verbose}, 99, 'pod2usage short verbose');
    is_deeply($POD[-1]{-sections}, [qw(NAME SYNOPSIS)], 'pod2usage short sections');
    ok(exists $POD[-1]{-input}, 'pod2usage receives the usage input');
    $r = router({ usage_source => '' }, 'help');
    is($r->{exit}, 0, 'help via pod2usage exits 0');
    ok(!exists $POD[-1]{-sections}, 'help form has no sections');
    ok(!exists $POD[-1]{-input}, 'no usage input without usage source');

    # With a pod2usage that returns, the router falls through to the end.
    {
        no warnings 'redefine';
        @POD = ();
        local *main::pod2usage = sub { my %a = @_; push @POD, \%a; return };
        %BUILTIN = ();
        $r = router({ usage_source => '' });
        is(scalar(@POD), 2, 'empty command shows short usage twice when pod2usage returns');
        is($r->{error}, undef, 'router returns normally when usage does not exit');
    }

    $r = run_catch(sub { PAX::StandaloneRuntime::_run_cli_router_unit("$root/no-such-router.json") });
    like($r->{error}, qr/cannot read cli router unit/, 'unreadable router unit dies');

    # Version handling.
    $r = router({ prelude_source => '1;' }, 'version');
    like($r->{error}, qr/missing version module/, 'version without module dies');
    $r = router({ version_module => 'PaxCovVer' }, 'version');
    is($r->{out}, "9.87\n", 'version prints module version');
    is($r->{exit}, 0, 'version exits 0');
    @CALLS = ();
    $r = router({ version_module => 'PaxCovVer' }, 'version');
    is_deeply($CALLS[0], 'env', 'runtime env loaded when no prelude');
    is_deeply($CALLS[1], ['prime', 'version'], 'command env primed');

    # Helper dispatch.
    %BUILTIN = (tool => '/opt/helpers/tool-helper', odd => '/opt/odd', skills => '/opt/helpers/skills');
    @MANAGED = ();
    $r = router({}, 'tool', 'a1');
    is_deeply($MANAGED[0], ['tool-helper', 'a1'], 'builtin helper runs as managed helper');
    {
        local *PAX::StandaloneRuntime::_direct_standalone_helper_name_from_path = sub { return };
        @EXEC = ();
        $r = router({}, 'odd', 'a2');
        is_deeply($EXEC[0], ['/opt/odd', 'a2'], 'builtin helper without direct name goes to switchboard');
    }

    %BUILTIN = ();
    %CUSTOM = (mine => '/opt/custom');
    @EXEC = ();
    $r = router({}, 'mine', 'a3');
    is_deeply($EXEC[0], ['/opt/custom', 'a3'], 'custom command uses switchboard');

    %CUSTOM = ();
    %BUILTIN = (skills => '/opt/helpers/skills-helper');
    %SKILL = ('sk.run' => ['sk', 'run']);
    @MANAGED = ();
    $r = router({}, 'sk.run', 'z');
    is_deeply($MANAGED[0], ['skills-helper', '_exec', 'sk', 'run', 'z'], 'skill command runs managed helper');
    {
        local *PAX::StandaloneRuntime::_direct_standalone_helper_name_from_path = sub { return };
        @EXEC = ();
        $r = router({}, 'sk.run', 'y');
        is_deeply($EXEC[0], ['/opt/helpers/skills-helper', '_exec', 'sk', 'run', 'y'], 'skill command without direct name uses switchboard');
    }

    # Unknown commands.
    %BUILTIN = ();
    %SKILL = ();
    $r = router({ suggest_class => 'PaxCovSuggest', usage_outputs => { short => { exit => 5 } } }, 'bogus');
    is($r->{err}, "unknown: bogus\n", 'unknown command prints suggestion');
    is($r->{exit}, 5, 'unknown command ends with short usage');
    $r = router({}, 'bogus');
    like($r->{error}, qr/missing suggest class/, 'unknown command without suggest class dies');
}

# Dispatch-script unit runner and actions.
my $dispatch_file = "$root/d.dispatch.json";

# dispatch($record, @argv)
# Writes a dispatch record and runs the unit under run_catch.
# Input: record and argv. Output: run_catch result.
sub dispatch {
    my ($record, @argv) = @_;
    write_json($dispatch_file, $record);
    return run_catch(sub { PAX::StandaloneRuntime::_run_dispatch_script_unit($dispatch_file) }, @argv);
}

{
    my $print = { op => 'print_call', target => 'main::pcov_target', args => [1, 2], newline => 1, exit_code => 4 };
    my $r = dispatch({
        bootstrap_source => '$main::PAXCOV_DBOOT = 7;',
        actions          => [ { action => $print }, { command => 'go', action => $print } ],
    }, 'go');
    is($main::PAXCOV_DBOOT, 7, 'dispatch bootstrap evaluated');
    is($r->{out}, "tv:1,2\n", 'print_call prints value and newline');
    is($r->{exit}, 4, 'print_call exit code');

    $r = dispatch({ actions => [ { command => 'go', action => { op => 'print_call', target => 'main::pcov_target' } } ] }, 'go');
    is($r->{out}, 'tv:', 'print_call without newline');
    is($r->{exit}, 0, 'print_call default exit 0');
    $r = dispatch({ actions => [ { command => 'go', action => { op => 'print_call', target => 'main::pcov_nothing' } } ] }, 'go');
    like($r->{error}, qr/missing dispatch target/, 'print_call missing target dies');

    $r = run_catch(sub { PAX::StandaloneRuntime::_run_dispatch_script_unit("$root/no-such-dispatch.json") });
    like($r->{error}, qr/cannot read dispatch script unit/, 'unreadable dispatch unit dies');
    $r = dispatch({ bootstrap_source => '', unknown_action => { op => 'stderr_interpolate_cmd', prefix => 'u' } });
    is($r->{err}, 'u', 'empty bootstrap source is skipped');
    $r = dispatch({ bootstrap_source => 'die "bootfail\n";' });
    is($r->{error}, "bootfail\n", 'dispatch bootstrap error rethrown');
    $r = dispatch({ actions => [ { command => 'a', action => $print } ], unknown_action => { op => 'stderr_interpolate_cmd', prefix => 'x' } });
    is($r->{err}, 'x', 'undef command skips entries and uses unknown action');

    # Command defaulting.
    $r = dispatch({ command_default => 'go', actions => [ { command => 'go', action => { op => 'print_call', target => 'main::pcov_target', newline => 1 } } ] });
    is($r->{out}, "tv:\n", 'default command used when argv empty');
    $r = dispatch({ command_default => 'go', actions => [ { command => 'go', action => { op => 'print_call', target => 'main::pcov_target' } } ] }, '');
    is($r->{out}, 'tv:', 'default command used when argv is empty string');
    $r = dispatch({ command_default_mode => 'defined_or', command_default => 'go',
        actions => [ { command => 'go', action => { op => 'print_call', target => 'main::pcov_target' } } ] });
    is($r->{out}, 'tv:', 'defined_or mode uses default for undef command');
    $r = dispatch({ command_default_mode => 'defined_or', command_default => 'go', unknown_action => { op => 'stderr_interpolate_cmd', exit_code => 9 } }, '');
    is($r->{exit}, 9, 'defined_or keeps empty string command');

    # No match and unknown handling.
    $r = dispatch({ actions => [ { command => 'a', action => $print } ] }, 'zzz');
    like($r->{error}, qr/no dispatch action for command zzz/, 'no action dies with command');
    $r = dispatch({});
    like($r->{error}, qr/no dispatch action for command \(undef\)/, 'no action dies with undef command');
    $r = dispatch({ actions => [ { action => $print } ] }, 'zzz');
    like($r->{error}, qr/no dispatch action/, 'entry without command does not match');
    $r = dispatch({ unknown_action => { op => 'stderr_interpolate_cmd', prefix => 'pre:', suffix => ':post' } }, 'q');
    is($r->{err}, 'pre:q:post', 'unknown action interpolates the command');
    is($r->{exit}, 0, 'interpolate default exit');
    $r = dispatch({ unknown_action => { op => 'stderr_interpolate_cmd' } });
    is($r->{err}, '', 'interpolate with undef command and no prefix');
    $r = dispatch({ unknown_action => { op => 'print_call', target => 'main::pcov_target' } }, 'q');
    is($r->{out}, 'tv:', 'unknown action print_call');

    # Direct action calls.
    $r = run_catch(sub { PAX::StandaloneRuntime::_run_dispatch_action({}, 'x') });
    like($r->{error}, qr/dispatch action op missing/, 'missing op dies');
    $r = run_catch(sub { PAX::StandaloneRuntime::_run_dispatch_action({ op => 'nope' }, 'x') });
    like($r->{error}, qr/unsupported dispatch action op: nope/, 'unsupported op dies');

    # print_required_global
    {
        no warnings 'once';
        $INC{'PaxCovGlob.pm'} = 1;
        $PaxCovGlob::VALUE = 'globval';
    }
    $r = run_catch(sub {
        PAX::StandaloneRuntime::_run_dispatch_action({ op => 'print_required_global', require_module => 'PaxCovGlob', symbol => 'PaxCovGlob::VALUE', newline => 1, exit_code => 6 }, 'x');
    });
    is($r->{out}, "globval\n", 'required global printed with newline');
    is($r->{exit}, 6, 'required global exit code');
    $r = run_catch(sub {
        PAX::StandaloneRuntime::_run_dispatch_action({ op => 'print_required_global', require_module => 'PaxCovGlob', symbol => 'PaxCovGlob::VALUE' }, 'x');
    });
    is($r->{out}, 'globval', 'required global without newline');
    is($r->{exit}, 0, 'required global default exit');
    $r = run_catch(sub { PAX::StandaloneRuntime::_run_dispatch_action({ op => 'print_required_global' }, 'x') });
    like($r->{error}, qr/require module missing/, 'required global needs module');

    # print_embedded_asset
    write_file("$root/assets/dir/a.txt", 'asset-body');
    my $asset = { op => 'print_embedded_asset', logical_path => 'dir/a.txt' };
    {
        local $ENV{PAX_EMBEDDED_ASSET_ROOT} = "$root/assets";
        $r = run_catch(sub { PAX::StandaloneRuntime::_run_dispatch_action($asset, 'x') });
        is($r->{out}, 'asset-body', 'embedded asset content printed');
        is($r->{exit}, 0, 'embedded asset exit 0');
        $r = run_catch(sub { PAX::StandaloneRuntime::_run_dispatch_action({ op => 'print_embedded_asset', logical_path => 'dir/none.txt' }, 'x') });
        is($r->{exit}, 3, 'missing asset file exits 3');
        like($r->{err}, qr/missing asset/, 'missing asset message');
        $r = run_catch(sub { PAX::StandaloneRuntime::_run_dispatch_action({ op => 'print_embedded_asset' }, 'x') });
        like($r->{error}, qr/asset logical path missing/, 'asset needs logical path');
    }
    {
        local $ENV{PAX_EMBEDDED_ASSET_ROOT} = '';
        $r = run_catch(sub { PAX::StandaloneRuntime::_run_dispatch_action($asset, 'x') });
        is($r->{exit}, 3, 'asset without root exits 3');
        delete local $ENV{PAX_EMBEDDED_ASSET_ROOT};
        $r = run_catch(sub { PAX::StandaloneRuntime::_run_dispatch_action($asset, 'x') });
        is($r->{exit}, 3, 'asset with unset root exits 3');
    }
}

# Script unit runner.
my $script_file = "$root/s.script.json";

# script($record, @argv)
# Writes a script record and runs the unit under run_catch.
# Input: record and argv. Output: run_catch result.
sub script {
    my ($record, @argv) = @_;
    write_json($script_file, $record);
    return run_catch(sub { PAX::StandaloneRuntime::_run_script_unit($script_file) }, @argv);
}

{
    my $r = script({ script_source => '1;', entry_invocation => { op => 'call_main_argv_and_exit' } });
    like($r->{error}, qr/missing main/, 'entry invocation without main dies');
    $r = run_catch(sub { PAX::StandaloneRuntime::_run_script_unit("$root/no-such-script.json") });
    like($r->{error}, qr/cannot read script unit/, 'unreadable script unit dies');
    $r = script({ script_source => '1;', entry_invocation => { op => 'bogus' } });
    like($r->{error}, qr/unsupported script entry invocation op: bogus/, 'unsupported entry op dies');
    $r = script({ script_source => '1;', entry_invocation => {} });
    like($r->{error}, qr/unsupported script entry invocation op: /, 'missing entry op dies');

    $r = script({ script_source => 'my $x = 40; $x + 2;' });
    is_deeply($r->{ret}, [42], 'script value returned');
    $r = script({ script_source => 'undef;' });
    is_deeply($r->{ret}, [0], 'undef script value becomes 0');
    $r = script({ script_source => 'die "boom\n";' });
    is($r->{error}, "boom\n", 'script eval error rethrown');

    $r = script({ script_source => '' });
    like($r->{error}, qr/script source is empty/, 'empty source dies');
    $r = script({});
    like($r->{error}, qr/script source missing/, 'absent source dies');

    $r = script({
        script_source => 'sub pcov_add { my ($l, $r) = @_; return $l + $r } pcov_add(3, 4);',
        compiled_subs => [ { op => 'native_shape_sub', full_name => 'main::pcov_add', native_shape => { kind => 'i64_binary_leaf', op => 'add', args => [1, 2] } } ],
    });
    is_deeply($r->{ret}, [7], 'compiled script sub runs through native shape interpreter');

    $r = script({
        script_source => 'sub main { return scalar(@_) } 1;',
        entry_invocation => { op => 'call_main_argv_and_exit' },
    }, 'a', 'b');
    is($r->{exit}, 2, 'main called with argv and result used as exit code');
    $r = script({
        script_source => 'no warnings "redefine"; sub main { return } 1;',
        entry_invocation => { op => 'call_main_argv_and_exit' },
    });
    is($r->{exit}, 0, 'undef main result exits 0');
    delete $main::{main};

    # Source fallbacks through the manifest code units.
    write_file("$root/code/fb.script.json", '{}');
    write_file("$root/real_src.pl", '"from-path";');
    $STATE->{manifest}{code_units} = [
        { logical_path => "$script_file", script_source => '"from-unit-source";' },
    ];
    $r = script({});
    is_deeply($r->{ret}, ['from-unit-source'], 'script source from code unit');
    $STATE->{manifest}{code_units} = [
        { logical_path => "$script_file", bytes => JSON::PP->new->encode({ script_source => '"from-bytes-json";' }) },
    ];
    $r = script({});
    is_deeply($r->{ret}, ['from-bytes-json'], 'script source from JSON bytes');
    $STATE->{manifest}{code_units} = [
        { logical_path => "$script_file", bytes => '"raw-bytes";' },
    ];
    $r = script({});
    is_deeply($r->{ret}, ['raw-bytes'], 'script source from raw bytes');
    $STATE->{manifest}{code_units} = [
        { logical_path => "$script_file", bytes => '{"other":1}' },
    ];
    is(PAX::StandaloneRuntime::_script_source_from_code_units($script_file), '{"other":1}', 'JSON bytes without script source returned raw');
    $STATE->{manifest}{code_units} = [ { logical_path => "$script_file", source_path => "$root/real_src.pl" } ];
    $r = script({});
    is_deeply($r->{ret}, ['from-path'], 'script source from source path');
    $STATE->{manifest}{code_units} = [ { logical_path => "$script_file", residual_payload => '"from-residual";' } ];
    $r = script({});
    is_deeply($r->{ret}, ['from-residual'], 'script source from residual payload');
    $STATE->{manifest}{code_units} = [];
}

# Code-unit lookup and source helpers.
{
    $STATE->{manifest}{code_units} = [ { logical_path => 'x.script.json' } ];
    is(PAX::StandaloneRuntime::_script_source_from_code_units("$root/none"), undef, 'no unit gives no source');
    is(PAX::StandaloneRuntime::_script_source_from_code_units('x.script.json'), undef, 'unit without source or bytes gives undef');
    is(PAX::StandaloneRuntime::_source_path_to_script_source("$root/none"), undef, 'no unit gives no source path source');
    is(PAX::StandaloneRuntime::_source_path_to_script_source('x.script.json'), undef, 'unit without source path');
    is(PAX::StandaloneRuntime::_script_source_from_residual_payload("$root/none"), undef, 'no unit gives no residual payload');
    is(PAX::StandaloneRuntime::_script_source_from_residual_payload('x.script.json'), undef, 'unit without payload');

    $STATE->{manifest}{entrypoint}{source_path} = "$root/entry_src.pl";
    $STATE->{manifest}{code_units} = [ { logical_path => 'p.script.json', source_path => "$root/missing_src.pl" } ];
    is(PAX::StandaloneRuntime::_source_path_to_script_source('p.script.json'), undef, 'unreadable source path gives undef');
    $STATE->{manifest}{entrypoint} = undef;
    $STATE->{manifest}{code_units} = [ { logical_path => 'p.script.json', payload => 'pay' } ];
    is(PAX::StandaloneRuntime::_script_source_from_residual_payload('p.script.json'), 'pay', 'payload fallback used');
    $STATE->{manifest}{entrypoint} = { logical_path => 'ep.script.json' };

    my $unit = { logical_path => 'm.pl' };
    my $other = { logical_path => 'o.pl', source_path => "$root/real_src.pl" };
    my $blank = { logical_path => 'b.pl', source_path => '' };
    $STATE->{manifest}{code_units} = [ undef, 'str', $blank, $other, $unit ];
    is(PAX::StandaloneRuntime::_find_code_unit_for_entrypoint('m.pl'), $unit, 'unit found by logical path');
    is(PAX::StandaloneRuntime::_find_code_unit_for_entrypoint(File::Spec->catfile($root, 'code', 'm.pl')), $unit, 'unit found by packed path');
    is(PAX::StandaloneRuntime::_find_code_unit_for_entrypoint("$root/real_src.pl"), $other, 'unit found by source path');
    is(PAX::StandaloneRuntime::_find_code_unit_for_entrypoint('nope'), undef, 'no unit found');
    {
        my @warnings;
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        $STATE->{manifest}{code_units} = [ {} ];
        is(PAX::StandaloneRuntime::_find_code_unit_for_entrypoint('nope'), undef, 'unit without logical path does not match');
        ok(scalar(@warnings) >= 0, 'lookup tolerated missing logical path');
    }
    delete $STATE->{manifest}{code_units};
    is(PAX::StandaloneRuntime::_find_code_unit_for_entrypoint('nope'), undef, 'missing unit list handled');
    $STATE->{manifest}{code_units} = [];
}

# Initializers.
{
    no warnings 'once';
    $INC{'PaxCovInit.pm'} = 1;
    @PaxCovInit::IMPORTED = ();
    $INC{'PaxCovBadInit.pm'} = 1;
}

# PaxCovInit::import($class, @args)
# Records import arguments.
# Input: class and import arguments. Output: none.
sub PaxCovInit::import { my ($class, @args) = @_; @PaxCovInit::IMPORTED = @args; return }

# PaxCovBadInit::import($class)
# Always fails so the initializer error path runs.
# Input: class. Output: dies.
sub PaxCovBadInit::import { die "import failed\n" }

{
    local $ENV{PAX_STANDALONE_TRACE} = 1;
    my $apply = sub {
        my ($init) = @_;
        return run_catch(sub { PAX::StandaloneRuntime::_apply_initializer($init) });
    };
    my $r = $apply->({ op => 'require_module', module => 'PaxCovInit' });
    ok(!$r->{error}, 'require_module of loaded module works');
    like($r->{err}, qr/initializer require_module PaxCovInit/, 'initializer traced');
    $r = $apply->({ op => 'require_module', symbol => 'only' });
    like($r->{error}, qr/initializer module missing/, 'require_module needs module');
    {
        no warnings 'redefine';
        my @loaded;
        local *PAX::StandaloneRuntime::_load_compiled_require = sub { push @loaded, $_[0]; return 1 };
        $r = $apply->({ op => 'require_module', module => 'Not::Really::There' });
        is($loaded[0], 'Not/Really/There.pm', 'compiled require tried first');
        ok(!$r->{error}, 'compiled require short-circuits plain require');
    }
    $r = $apply->({ op => 'use_module', module => 'PaxCovInit', args => ['a', 3, "it's \\"], package => 'PaxCovTarget' });
    ok(!$r->{error}, 'use_module imports') or diag $r->{error};
    is_deeply(\@PaxCovInit::IMPORTED, ['a', 3, "it's \\"], 'import received literal arguments');
    like($r->{err}, qr/initializer import done PaxCovInit into PaxCovTarget/, 'import traced');
    $r = $apply->({ op => 'use_module', module => 'PaxCovInit' });
    like($r->{err}, qr/into main/, 'import defaults to main package');
    {
        no warnings 'redefine';
        local *PAX::StandaloneRuntime::_load_compiled_require = sub { return 1 };
        $INC{'PaxCovInit2.pm'} = 1;
        @PaxCovInit::IMPORTED = ();
        $r = $apply->({ op => 'use_module', module => 'PaxCovInit' });
        ok(!$r->{error}, 'use_module accepts a compiled require');
    }
    $r = $apply->({ op => 'use_module', symbol => 'x' });
    like($r->{error}, qr/initializer module missing/, 'use_module needs module');
    $r = $apply->({ op => 'use_module', module => 'PaxCovBadInit' });
    like($r->{error}, qr/import failed/, 'failing import dies');

    $r = $apply->({ op => 'set_scalar_literal', symbol => 'PaxCovSym::S', value => 'sv' });
    is($PaxCovSym::S, 'sv', 'scalar literal set');
    $r = $apply->({ op => 'set_scalar_literal', value => 'sv' });
    like($r->{error}, qr/initializer symbol missing/, 'scalar literal needs symbol');
    $r = $apply->({ op => 'set_array_literal', symbol => 'PaxCovSym::A', values => [1, 2] });
    is_deeply(\@PaxCovSym::A, [1, 2], 'array literal set');
    $r = $apply->({ op => 'set_array_literal', symbol => 'PaxCovSym::A' });
    is_deeply(\@PaxCovSym::A, [], 'array literal defaults to empty');
    $r = $apply->({ op => 'set_array_literal' });
    like($r->{error}, qr/initializer symbol missing/, 'array literal needs symbol');
    $PaxCovSym::N = undef;
    $r = $apply->({ op => 'increment_scalar_default_zero', symbol => 'PaxCovSym::N', by => 5 });
    is($PaxCovSym::N, 5, 'increment from undef');
    $r = $apply->({ op => 'increment_scalar_default_zero', symbol => 'PaxCovSym::N' });
    is($PaxCovSym::N, 5, 'increment by default zero');
    $r = $apply->({ op => 'increment_scalar_default_zero' });
    like($r->{error}, qr/initializer symbol missing/, 'increment needs symbol');
    $r = $apply->({ op => 'weird' });
    like($r->{error}, qr/unsupported compiled initializer op: weird/, 'unknown initializer op dies');
    $r = $apply->({});
    like($r->{error}, qr/unsupported compiled initializer op: /, 'missing initializer op dies');
}

# Perl literal rendering.
{
    is(PAX::StandaloneRuntime::_perl_literal(undef), 'undef', 'undef literal');
    is(PAX::StandaloneRuntime::_perl_literal(-12.5), '-12.5', 'number literal');
    is(PAX::StandaloneRuntime::_perl_literal("a'b\\c"), "'a\\'b\\\\c'", 'string literal escapes');
    like(PAX::StandaloneRuntime::_perl_literal([1]), qr/\A'ARRAY\(0x[0-9a-f]+\)'\z/, 'reference stringified and quoted');
}

# Native runner construction.
{
    $STATE->{native_runner} = undef;
    my $runner = PAX::StandaloneRuntime::_native_runner($STATE);
    isa_ok($runner, 'PAX::NativeRunner', 'native runner created on demand');
    is(PAX::StandaloneRuntime::_native_runner($STATE), $runner, 'native runner reused');
    $STATE->{native_runner} = undef;
}

# Lazily installed compiled subs.
{
    no warnings 'redefine';
    PAX::StandaloneRuntime::_install_compiled_sub_lazily('PaxCovL', { name => 'lit', op => 'return_literal', value => 'v1' });
    my $stub = \&PaxCovL::lit;
    is(PaxCovL::lit(), 'v1', 'lazy stub builds the real sub on first call');
    isnt(\&PaxCovL::lit, $stub, 'stub replaced by the real sub');
    is($stub->(), 'v1', 'old stub still forwards to the real sub');

    PAX::StandaloneRuntime::_install_compiled_sub_lazily('PaxCovL', { name => 'proto', op => 'return_literal', prototype => '($)', value => 'v2' });
    is(prototype('PaxCovL::proto'), '$', 'prototyped subs are installed eagerly with their prototype');
    PAX::StandaloneRuntime::_install_compiled_sub_lazily('PaxCovL', { name => 'emptyproto', op => 'return_literal', prototype => '', value => 'v3' });
    isnt(\&PaxCovL::emptyproto, undef, 'empty prototype installs lazily');
    is(PaxCovL::emptyproto(), 'v3', 'empty prototype sub works');
    {
        local $ENV{PAX_EAGER_SUBS} = 1;
        PAX::StandaloneRuntime::_install_compiled_sub_lazily('PaxCovL', { name => 'eager', op => 'return_literal', value => 'v4' });
        is(PaxCovL::eager(), 'v4', 'PAX_EAGER_SUBS installs directly');
    }
    eval { PAX::StandaloneRuntime::_install_compiled_sub_lazily('PaxCovL', { op => 'return_literal' }) };
    like($@, qr/compiled sub name missing/, 'lazy install needs a name');

    {
        local *PAX::StandaloneRuntime::_install_compiled_sub = sub { return };
        PAX::StandaloneRuntime::_install_compiled_sub_lazily('PaxCovL', { name => 'noinst', op => 'ghost' });
        eval { PaxCovL::noinst() };
        like($@, qr/compiled sub op 'ghost' did not install PaxCovL::noinst/, 'stub detects op that installed nothing');
        PAX::StandaloneRuntime::_install_compiled_sub_lazily('PaxCovL', { name => 'noop' });
        eval { PaxCovL::noop() };
        like($@, qr/compiled sub op '' did not install/, 'stub reports empty op');
    }
    {
        local *PAX::StandaloneRuntime::_install_compiled_sub = sub {
            no strict 'refs';
            delete $PaxCovL::{vanish};
            return;
        };
        PAX::StandaloneRuntime::_install_compiled_sub_lazily('PaxCovL', { name => 'vanish', op => 'ghost' });
        my $s = \&PaxCovL::vanish;
        eval { $s->() };
        like($@, qr/did not install PaxCovL::vanish/, 'stub detects missing installed sub');
    }
}

# Compiled sub installation and the lazy op handler loader.
{
    eval { PAX::StandaloneRuntime::_install_compiled_sub('PaxCovI', { op => 'return_literal' }) };
    like($@, qr/compiled sub name missing/, 'install needs a name');
    eval { PAX::StandaloneRuntime::_install_compiled_sub('PaxCovI', { name => 'x' }) };
    like($@, qr/unsupported compiled sub op: /, 'install without op dies');
    eval { PAX::StandaloneRuntime::_install_compiled_sub('PaxCovI', { name => 'x', op => 'unknown_op' }) };
    like($@, qr/unsupported compiled sub op: unknown_op/, 'install of unknown op dies');
    PAX::StandaloneRuntime::_install_compiled_sub('PaxCovI', { name => 'two', op => 'pcov_a' });
    PAX::StandaloneRuntime::_install_compiled_sub('PaxCovI', { name => 'three', op => 'pcov_b' });
    is(PaxCovI::two(), 'pcov:two', 'first op of a shared handler');
    is(PaxCovI::three(), 'pcov:three', 'second op of a shared handler');
    my $h = PAX::StandaloneRuntime::_compiled_op_handler('pcov_a');
    is(PAX::StandaloneRuntime::_compiled_op_handler('pcov_a'), $h, 'compiled handler is cached');
    eval { PAX::StandaloneRuntime::_compiled_op_handler('pcov_bad') };
    like($@, qr/cannot compile runtime op pcov_bad/, 'handler compile failure dies');
    is(PAX::StandaloneRuntime::_compiled_op_handler('never_defined'), undef, 'unknown handler gives undef');

    PAX::StandaloneRuntime::_require_modules_for_op_source(join "\n",
        'Getopt::Long::GetOptions(); open3(); make_path();',
        'my $x = pack_sockaddr_in(1, 2); my $l = LOCK_EX; my $o = O_CREAT; SEEK_SET; Time::HiRes::time(); md5_hex(); inet_aton();',
    );
    ok($INC{'Getopt/Long.pm'}, 'qualified module token loaded');
    ok($INC{'Socket.pm'}, 'socket token loaded');
    ok($INC{'Fcntl.pm'}, 'fcntl constants loaded');
    ok($INC{'IPC/Open3.pm'}, 'alias token loaded');
    PAX::StandaloneRuntime::_require_modules_for_op_source('nothing here');

    # An unreadable DATA section yields no handlers rather than dying.
    {
        no strict 'refs';
        my $glob = \*{'PAX::StandaloneRuntime::DATA'};
        close $glob;
        local $SIG{__WARN__} = sub { };
        PAX::StandaloneRuntime::_load_compiled_op_sources();
        pass('closed DATA section tolerated');
    }
}

# Native-shape script sub support.
{
    my $shape = { kind => 'i64_binary_leaf', op => 'add', args => [1, 2] };
    is(PAX::StandaloneRuntime::_compiled_script_sub_source('main::f', undef, undef, $shape), undef, 'no source without short name');
    is(PAX::StandaloneRuntime::_compiled_script_sub_source('main::f', '', undef, $shape), undef, 'no source for empty short name');
    is(PAX::StandaloneRuntime::_compiled_script_sub_source('main::f', 'f', undef, 'notahash'), undef, 'no source for non-hash shape');
    my $two = PAX::StandaloneRuntime::_compiled_script_sub_source('main::f', 'f', '$$', $shape);
    like($two, qr/\Asub f\$\$ \{\n    my \(\$PAX_ARG0, \$PAX_ARG1\) = \@_;/, 'two-arg replacement with prototype');
    like($two, qr/_run_native_shape_sub\('main::f', '/, 'replacement calls the native shape runner');
    my $one = PAX::StandaloneRuntime::_compiled_script_sub_source('main::g', 'g', undef, { kind => 'k' });
    like($one, qr/\Asub g \{\n    my \(\$PAX_ARG0\) = \@_;/, 'one-arg replacement without prototype');

    is(PAX::StandaloneRuntime::_apply_compiled_script_subs(undef, [1]), undef, 'undef source passes through');
    is(PAX::StandaloneRuntime::_apply_compiled_script_subs('', [1]), '', 'empty source passes through');
    is(PAX::StandaloneRuntime::_apply_compiled_script_subs('src', undef), 'src', 'no subs passes through');
    is(PAX::StandaloneRuntime::_apply_compiled_script_subs('src', []), 'src', 'empty subs passes through');
    my $src = "sub f { return 1; }\nsub g { return 2 }\nsub h {\n  if (1) { return 3 }\n}\n";
    my $out = PAX::StandaloneRuntime::_apply_compiled_script_subs($src, [
        { op => 'other', full_name => 'main::f' },
        { full_name => 'main::f' },
        { op => 'native_shape_sub', full_name => 'Pkg::f' },
        { op => 'native_shape_sub' },
        { op => 'native_shape_sub', full_name => 'main::f', native_shape => 'bad' },
        { op => 'native_shape_sub', full_name => 'main::missing', native_shape => $shape },
        { op => 'native_shape_sub', full_name => 'main::f', native_shape => $shape },
        { op => 'native_shape_sub', full_name => 'main::h', native_shape => { kind => 'k' }, prototype => '' },
    ]);
    like($out, qr/\Asub f \{\n    my \(\$PAX_ARG0, \$PAX_ARG1\)/, 'sub f replaced');
    like($out, qr/sub g \{ return 2 \}/, 'sub g untouched');
    unlike($out, qr/if \(1\)/, 'nested-brace sub h replaced');

    is(PAX::StandaloneRuntime::_extract_sub_source_runtime('no subs here', 'f'), undef, 'no sub found');
    is(PAX::StandaloneRuntime::_extract_sub_source_runtime('sub f { 1 } ;', 'f'), 'sub f { 1 } ;', 'trailing spaces and semicolon included');
    is(PAX::StandaloneRuntime::_extract_sub_source_runtime('sub f { 1 }', 'f'), 'sub f { 1 }', 'sub at end of source');
    is(PAX::StandaloneRuntime::_extract_sub_source_runtime("sub f { 1 }\nx", 'f'), 'sub f { 1 }', 'no semicolon after sub');
    is(PAX::StandaloneRuntime::_extract_sub_source_runtime('sub f { 1 ', 'f'), undef, 'unbalanced sub gives undef');
    is(PAX::StandaloneRuntime::_extract_sub_source_runtime('sub f { 1 } ', 'f'), 'sub f { 1 } ', 'trailing space at end of source');

    # Native shape execution.
    my $fake = bless { result => { status => 'ok', value => 99 }, calls => [] }, 'PaxCovFakeRunner';
    $STATE->{native_runner} = $fake;
    $STATE->{by_region} = { 'main::nat' => { executable_logical_path => 'bin/nat' } };
    write_file("$root/bin/nat", "bin");
    is(PAX::StandaloneRuntime::_run_native_shape_sub('main::nat', $shape, 3, 4), 99, 'native result used');
    is($fake->{calls}[0]{right}, 4, 'second argument passed through');
    is(PAX::StandaloneRuntime::_run_native_shape_sub('main::nat', JSON::PP->new->encode($shape), 3, 4), 99, 'JSON shape decoded');
    is(PAX::StandaloneRuntime::_run_native_shape_sub('main::nat', { kind => 'i64_sum_loop', args => [1] }, 4), 99, 'one-arg shape runs native');
    is($fake->{calls}[-1]{right}, 0, 'missing second argument defaults to zero');
    ok(-x "$root/bin/nat", 'native probe made executable');
    $fake->{result} = { status => 'fallback' };
    is(PAX::StandaloneRuntime::_run_native_shape_sub('main::nat', $shape, 3, 4), 7, 'fallback status interprets shape');
    $fake->{result} = { status => 'ok' };
    is(PAX::StandaloneRuntime::_run_native_shape_sub('main::nat', $shape, 3, 4), 7, 'ok without value interprets shape');
    is(PAX::StandaloneRuntime::_run_native_shape_sub('main::nat', { kind => 'i64_sum_loop', args => [1] }, 3, 4), 6, 'wrong argument count interprets shape');
    is(PAX::StandaloneRuntime::_run_native_shape_sub('main::nat', { kind => 'i64_sum_loop', args => [1] }, '2.5'), 3, 'non-integer arguments skip native path');
    is(PAX::StandaloneRuntime::_run_native_shape_sub('main::nat', { kind => 'i64_sum_loop' }, 4), 10, 'shape without args interprets');
    $STATE->{by_region} = {};
    my $res = PAX::StandaloneRuntime::_invoke_native_shape_runtime('main::none', $shape, [1, 2]);
    is($res->{status}, 'fallback', 'missing native region falls back');
    $STATE->{by_region} = { 'main::nat' => { executable_logical_path => 'bin/absent' } };
    $fake->{result} = { status => 'ok', value => 5 };
    $res = PAX::StandaloneRuntime::_invoke_native_shape_runtime('main::nat', $shape, [1, 2]);
    is($res->{value}, 5, 'absent probe file still dispatched');
    $STATE->{by_region} = { 'main::nat' => {} };
    $res = PAX::StandaloneRuntime::_invoke_native_shape_runtime('main::nat', $shape, [1, 2]);
    is($res->{status}, 'fallback', 'region without executable falls back');
    $STATE->{by_region} = {};
    $STATE->{native_runner} = undef;

    ok(PAX::StandaloneRuntime::_native_shape_args_are_i64([1, -2, '30']), 'integer arguments accepted');
    ok(!PAX::StandaloneRuntime::_native_shape_args_are_i64([1, undef]), 'undef argument rejected');
    ok(!PAX::StandaloneRuntime::_native_shape_args_are_i64([1.5]), 'non-integer argument rejected');

    my $bin = sub { PAX::StandaloneRuntime::_interpret_native_shape({ kind => 'i64_binary_leaf', op => $_[0] }, [$_[1], $_[2]]) };
    is($bin->('add', 2, 3), 5, 'add');
    is($bin->('subtract', 2, 3), -1, 'subtract');
    is($bin->('multiply', 2, 3), 6, 'multiply');
    is($bin->('greater_than', 3, 2), 1, 'greater than true');
    is($bin->('greater_than', 2, 3), 0, 'greater than false');
    eval { $bin->('bogus', 1, 1) };
    like($@, qr/unsupported native shape kind: i64_binary_leaf/, 'unknown binary op falls through to die');
    eval { PAX::StandaloneRuntime::_interpret_native_shape({ kind => 'i64_binary_leaf' }, [1, 2]) };
    like($@, qr/unsupported native shape kind/, 'missing binary op dies');
    my $sum = sub { PAX::StandaloneRuntime::_interpret_native_shape({ kind => 'i64_sum_loop' }, [@_]) };
    is($sum->(4), 10, 'sum loop');
    is($sum->(0), 0, 'sum loop non-positive');
    is($sum->(), 0, 'sum loop undef');
    my $mix = sub { PAX::StandaloneRuntime::_interpret_native_shape({ kind => 'i64_masked_mix_accum_loop' }, [@_]) };
    my $want = 0;
    $want += (($_ * 13) ^ ($_ >> 3)) & 0xFFFF for 0 .. 9;
    is($mix->(10), $want, 'masked mix loop');
    is($mix->(-1), 0, 'masked mix non-positive');
    is($mix->(), 0, 'masked mix undef');
    eval { PAX::StandaloneRuntime::_interpret_native_shape({}, []) };
    like($@, qr/unsupported native shape kind: /, 'missing kind dies');
}

# Installing handlers under package symbols.
{
    PAX::StandaloneRuntime::_install_sub_impl('PaxCovS', 'plain', undef, sub { 'plain' });
    is(PaxCovS::plain(), 'plain', 'plain install');
    PAX::StandaloneRuntime::_install_sub_impl('PaxCovS', 'empty', '', sub { 'empty' });
    is(PaxCovS::empty(), 'empty', 'empty prototype installs plainly');
    PAX::StandaloneRuntime::_install_sub_impl('PaxCovS', 'proto', '($$)', sub { 'proto:' . join ',', @_ });
    is(prototype('PaxCovS::proto'), '$$', 'prototype preserved');
    is(PaxCovS::proto(1, 2), 'proto:1,2', 'prototyped sub forwards');
    eval { PAX::StandaloneRuntime::_install_sub_impl('PaxCovS', 'bad name', '($)', sub { 1 }) };
    ok($@, 'invalid sub name with prototype dies');
}

# Residual stubs and sources.
{
    my $noisy = '$SIG{__WARN__}->(undef); warn "custom warning\n"; sub delta { 1 } use warnings "redefine"; sub delta { 2 } sub proto1($$) { 1 } sub proto1 { 2 }';

    # Stubs with no unsupported subs installed nothing.
    PAX::StandaloneRuntime::_install_residual_stubs({}, {});
    pass('no residual subs tolerated');

    my $record = {
        package => 'PaxCovR',
        require_path => 'PaxCovR.pm',
        unsupported_subs => ['PaxCovR::alpha', 'PaxCovR::beta'],
        residual_bootstrap_source => 'package PaxCovR; our $BOOT = 1;',
        residual_sub_sources => {
            'PaxCovR::alpha' => 'sub alpha { return "alpha:$BOOT" }',
            'PaxCovR::beta'  => "$noisy; sub beta { return 'b' }",
        },
    };
    my $unit = { logical_path => 'r.pcu.json' };
    PAX::StandaloneRuntime::_install_residual_stubs($unit, $record);
    is(PaxCovR::alpha(), 'alpha:1', 'residual sub loaded on first call with bootstrap');
    is(PaxCovR::alpha(), 'alpha:1', 'loaded residual sub called again');
    my $r = run_catch(sub { PaxCovR::beta() });
    is_deeply($r->{ret}, ['b'], 'noisy residual sub still works');
    like($r->{err}, qr/custom warning/, 'ordinary warnings pass through');
    like($r->{err}, qr/something's wrong/, 'undef warning passes through');
    unlike($r->{err}, qr/redefined|Prototype mismatch/, 'redefinition and prototype warnings suppressed');
    ok(PAX::StandaloneRuntime::_load_residual_sub($unit, $record, 'PaxCovR::beta') ? 1 : 1, 'repeat load is a no-op');
    is(PAX::StandaloneRuntime::_load_residual_sub($unit, $record, 'PaxCovR::beta'), undef, 'already loaded sub returns undef');

    eval { PAX::StandaloneRuntime::_load_residual_sub($unit, $record, 'PaxCovR::absent') };
    like($@, qr/residual sub source missing for PaxCovR::absent/, 'missing residual sub source dies');
    $STATE->{residual_bootstrap_loaded} = {};
    $record->{residual_sub_sources}{'PaxCovR::bad'} = 'sub bad { die "no\n" } }';
    eval { PAX::StandaloneRuntime::_load_residual_sub($unit, $record, 'PaxCovR::bad') };
    ok($@, 'residual source syntax error dies');

    # Key derivation falls back through require_path, logical_path and source_path.
    for my $variant ({ logical_path => 'k1.pcu.json' }, { source_path => '/some/k2.pm' }, {}) {
        my $rec = { package => 'PaxCovK', residual_sub_sources => { 'PaxCovK::k' => 'sub k { 1 }' } };
        PAX::StandaloneRuntime::_load_residual_sub($variant, $rec, 'PaxCovK::k') if %$variant;
        next if %$variant;
        eval { PAX::StandaloneRuntime::_load_residual_sub($variant, $rec, 'PaxCovK::k') };
        ok(1, 'residual load with empty key tolerated');
    }

    # Residual bootstrap.
    $STATE->{residual_bootstrap_loaded} = {};
    my $brec = { package => 'PaxCovB', require_path => 'PaxCovB.pm', residual_bootstrap_source => "package PaxCovB; $noisy; our \$LOADED = 1;" };
    $r = run_catch(sub { PAX::StandaloneRuntime::_load_residual_bootstrap({ logical_path => 'b.pcu.json' }, $brec) });
    is_deeply($r->{ret}, [1], 'bootstrap loaded');
    is($PaxCovB::LOADED, 1, 'bootstrap source ran');
    like($r->{err}, qr/custom warning/, 'bootstrap passes through ordinary warnings');
    unlike($r->{err}, qr/redefined|Prototype mismatch/, 'bootstrap suppresses redefinition warnings');
    is(PAX::StandaloneRuntime::_load_residual_bootstrap({ logical_path => 'b.pcu.json' }, $brec), undef, 'bootstrap loads once');
    is(PAX::StandaloneRuntime::_load_residual_bootstrap({ logical_path => 'nb.pcu.json' }, { package => 'X' }), 1, 'missing bootstrap source is fine');
    is(PAX::StandaloneRuntime::_load_residual_bootstrap({ logical_path => 'eb.pcu.json' }, { package => 'X', residual_bootstrap_source => '' }), 1, 'empty bootstrap source is fine');
    eval { PAX::StandaloneRuntime::_load_residual_bootstrap({ source_path => 'sb' }, { package => 'X', residual_bootstrap_source => 'die "bootdie\n"' }) };
    is($@, "bootdie\n", 'bootstrap errors propagate');
    PAX::StandaloneRuntime::_load_residual_bootstrap({}, { package => 'X' });
    pass('bootstrap with no key tolerated');

    # Module-mode residuals.
    $STATE->{residual_bootstrap_loaded} = {};
    my $mrec = {
        package => 'PaxCovM',
        require_path => 'PaxCovM.pm',
        residual_mode => 'module',
        subs => [ { name => 'old' }, {} ],
        unsupported_subs => ['PaxCovM::mod', 'plain'],
        residual_source => "package PaxCovM; $noisy; sub mod { return 'mod' } 1;",
    };
    {
        no strict 'refs';
        *{'PaxCovM::old'} = sub { 'old' };
    }
    my $munit = { logical_path => 'm.pcu.json' };
    PAX::StandaloneRuntime::_install_residual_stubs($munit, $mrec);
    $r = run_catch(sub { PaxCovM::mod() });
    is_deeply($r->{ret}, ['mod'], 'module residual loaded on first call');
    like($r->{err}, qr/custom warning/, 'module residual passes through ordinary warnings');
    unlike($r->{err}, qr/redefined|Prototype mismatch/, 'module residual suppresses redefinition warnings');
    ok(!PaxCovM->can('old'), 'stale compiled sub removed before module residual load');
    is(PAX::StandaloneRuntime::_load_residual_module($munit, $mrec), undef, 'module residual loads once');
    $STATE->{residual_loaded} = {};
    is(PAX::StandaloneRuntime::_load_residual_sub($munit, $mrec, 'PaxCovM::mod'), 1, 'module-mode sub load succeeds');
    eval { PAX::StandaloneRuntime::_load_residual_sub($munit, $mrec, 'PaxCovM::gone') };
    like($@, qr/module residual source did not define PaxCovM::gone/, 'module residual must define the sub');
    $STATE->{residual_bootstrap_loaded} = {};
    eval { PAX::StandaloneRuntime::_load_residual_module({ source_path => 'ms' }, { package => 'PaxCovM2' }) };
    like($@, qr/residual module source missing for ms/, 'module residual needs source');
    $STATE->{residual_bootstrap_loaded} = {};
    eval { PAX::StandaloneRuntime::_load_residual_module({}, { residual_source => 'die "moddie\n"' }) };
    is($@, "moddie\n", 'module residual errors propagate');
    $STATE->{residual_bootstrap_loaded} = {};
    PAX::StandaloneRuntime::_load_residual_module({ logical_path => 'mm.pcu.json' }, { package => 'PaxCovMM', residual_source => '1;' });
    pass('module residual without sub lists loads');

    # A stub whose loader leaves the sub undefined dies cleanly.
    {
        no warnings 'redefine';
        local *PAX::StandaloneRuntime::_load_residual_sub = sub {
            no strict 'refs';
            delete $PaxCovG::{ghost};
            return 1;
        };
        PAX::StandaloneRuntime::_install_residual_stubs({}, { unsupported_subs => ['PaxCovG::ghost'] });
        my $stub = \&PaxCovG::ghost;
        eval { $stub->() };
        like($@, qr/residual source did not define PaxCovG::ghost/, 'stub dies when residual source defines nothing');
    }
}

# Code lookup and virtual source paths.
{
    is(PAX::StandaloneRuntime::_code_for('PaxCovS::plain')->(), 'plain', 'code ref looked up');
    is(PAX::StandaloneRuntime::_code_for('PaxCovS::nothing'), undef, 'missing code gives undef');
    my $path = PAX::StandaloneRuntime::_virtual_source_path({ logical_path => 'v.script.json' }, {});
    is($path, File::Spec->catfile($root, 'code', 'v.pl'), 'virtual source path for a unit');
    ok(-f $path, 'virtual source file created');
    is(PAX::StandaloneRuntime::_virtual_entrypoint_path('ignored'), File::Spec->catfile($root, 'code', 'ep.pl'), 'entrypoint path from manifest');
    $STATE->{manifest}{entrypoint} = {};
    is(PAX::StandaloneRuntime::_virtual_entrypoint_path('fallback.dispatch.json'), File::Spec->catfile($root, 'code', 'fallback.pl'), 'entrypoint path falls back to argument');
    is(PAX::StandaloneRuntime::_virtual_entrypoint_path(''), File::Spec->catfile($root, 'code', 'virtual', 'entrypoint.pl'), 'entrypoint path falls back to the generic virtual file');
    my $saved = $STATE->{manifest};
    $STATE->{manifest} = undef;
    is(PAX::StandaloneRuntime::_virtual_entrypoint_path('other.script.json'), File::Spec->catfile($root, 'code', 'other.pl'), 'entrypoint path without manifest');
    $STATE->{manifest} = $saved;
    $STATE->{manifest}{entrypoint} = { logical_path => 'ep.script.json' };
}

# Template rendering.
{
    write_file("$root/t/tpl.txt", "Hi [% name %], [%missing%]! [% 1bad %]\n");
    write_file("$root/t/empty.txt", '');
    my $vars = { name => 'Ann' };
    is(PAX::StandaloneRuntime::_render_simple_template_asset("$root/t/tpl.txt", $vars), "Hi Ann, ! [% 1bad %]\n", 'template variables substituted');
    is(PAX::StandaloneRuntime::_render_simple_template_asset(undef, $vars), undef, 'no path gives undef');
    is(PAX::StandaloneRuntime::_render_simple_template_asset("$root/t/nothing.txt", $vars), undef, 'missing file gives undef');
    is(PAX::StandaloneRuntime::_render_simple_template_asset("$root/t/empty.txt", $vars), undef, 'empty template gives undef');
}

# Native hit log.
{
    my $log = "$root/hits.log";
    {
        local $ENV{PAX_STANDALONE_NATIVE_HIT_LOG};
        delete $ENV{PAX_STANDALONE_NATIVE_HIT_LOG};
        PAX::StandaloneRuntime::_log_native_hit('main::none');
        ok(!-e $log, 'no log without configuration');
    }
    {
        local $ENV{PAX_STANDALONE_NATIVE_HIT_LOG} = "$root/no/such/dir/hits.log";
        PAX::StandaloneRuntime::_log_native_hit('main::none');
        pass('unwritable log tolerated');
    }
    local $ENV{PAX_STANDALONE_NATIVE_HIT_LOG} = $log;
    PAX::StandaloneRuntime::_log_native_hit('main::one');
    PAX::StandaloneRuntime::_log_native_hit('main::two');
    open my $fh, '<', $log or die $!;
    my @lines = <$fh>;
    close $fh;
    is_deeply(\@lines, ["main::one\n", "main::two\n"], 'native hits appended');
}

done_testing;
