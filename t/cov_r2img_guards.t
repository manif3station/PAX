use strict;
use warnings;
use Symbol ();

# Replaces the global open builtin before PAX::StandaloneImage compiles so a test
# can make a pipe open fail; every other open is passed through unchanged.
our $FAIL_PIPE_OPEN;
BEGIN {
    *CORE::GLOBAL::open = sub (*;$@) {
        return undef if $FAIL_PIPE_OPEN && @_ >= 3 && defined $_[1] && $_[1] eq '-|';
        if (defined $_[0] && !ref $_[0] && ref(\$_[0]) ne 'GLOB') {
            my $handle = Symbol::qualify_to_ref($_[0], scalar caller);
            return CORE::open($handle, $_[1]) if @_ == 2;
            return CORE::open($handle, $_[1], @_[2 .. $#_]);
        }
        return CORE::open($_[0], $_[1]) if @_ == 2;
        return CORE::open($_[0], $_[1], @_[2 .. $#_]);
    };
}

use Test::More;
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneImage;

=pod

=head1 NAME

t/cov_r2img_guards.t - guard, helper and regression coverage for StandaloneImage

=head1 DESCRIPTION

Exercises the small helpers that replaced repeated defensive idioms in
PAX::StandaloneImage (C<_real_path>, C<_try_write_bytes>, C<_first_executable>),
the child-process helpers whose fork and devnull failure paths need forced
failures, and regression cases for the namespace marker rewrite and launcher
failure reasons.

=head1 WHY IT EXISTS

These paths cannot be reached from a normal build, so each case forces one
failure and asserts a concrete result.

=cut

my $T = tempdir('pax-cov-r2img-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $S = 'PAX::StandaloneImage::';

# write_file($path, $text, $mode)
# Writes a fixture file, creating parent directories first.
# Input: path, text and optional mode. Output: the path.
sub write_file {
    my ($path, $text, $mode) = @_;
    my ($volume, $dir) = File::Spec->splitpath($path);
    make_path($dir) if length $dir && !-d $dir;
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh or die "cannot close $path: $!";
    chmod $mode, $path if defined $mode;
    return $path;
}

# call(name, args...)
# Calls a private StandaloneImage function by name in list context.
# Input: function name and arguments. Output: the function's list result.
sub call {
    my ($name, @args) = @_;
    no strict 'refs';
    return &{"$S$name"}(@args);
}

# ---- _real_path
{
    is(call('_real_path', $T), abs_path($T), 'existing path is canonicalised');
    no warnings 'redefine';
    local *PAX::StandaloneImage::abs_path = sub { return undef };
    is(call('_real_path', '/no/such/place'), '/no/such/place', 'unresolvable path is kept as given');
}

# ---- _try_write_bytes
{
    is(call('_try_write_bytes', "$T/tw/ok.bin", 'x'), 0, 'open failure in a missing directory reports 0');
    make_path("$T/tw");
    is(call('_try_write_bytes', "$T/tw/ok.bin", 'abc'), 1, 'successful write reports 1');
    is(do { open my $fh, '<', "$T/tw/ok.bin" or die; local $/; <$fh> }, 'abc', 'bytes written');
    SKIP: {
        skip '/dev/full is not available', 1 if !-c '/dev/full';
        is(call('_try_write_bytes', '/dev/full', 'abc'), 0, 'close failure on a full device reports 0');
    }
}

# ---- _materialize_entrypoint_source write failure and tree escape guard
{
    my $extract = "$T/me";
    make_path("$extract/source-entrypoint/entry.pl");
    is(scalar call('_materialize_entrypoint_source', $extract, { source_path => '/x/entry.pl', source_bytes => 'code' }), '',
        'unwritable entrypoint source gives an empty path');

    my $ex2 = "$T/me2";
    make_path($ex2);
    my $manifest = {
        entrypoint => { source_path => "$T/m1/bin/main.pl", source_bytes => 'main' },
        code_units => [
            { unit_kind => 'lib', source_path => "$T/m1/bin/../esc/Evil.pm", source_bytes => 'evil' },
            { unit_kind => 'lib', source_path => "$T/m1/bin/Good.pm", source_bytes => 'good' },
        ],
    };
    my $r = call('_materialize_manifest_source_tree', $ex2, $manifest);
    ok(-f "$ex2/rebuild-source/main.pl", 'entrypoint materialised');
    ok(-f "$ex2/rebuild-source/Good.pm", 'sibling materialised');
    ok(!-e "$ex2/esc/Evil.pm", 'a source path that climbs out of the common root is not written outside it');
    is($r->{entrypoint}, "$ex2/rebuild-source/main.pl", 'tree result names the entrypoint');
}

# ---- _declared_app_prefixes ordering by count
is_deeply(
    [ call('_declared_app_prefixes', qw(Yy::Bb::One Xx::Aa::One Xx::Aa::Two Xx::Aa::Three Yy::Bb::Two)) ],
    [qw(Xx::Aa Yy::Bb)],
    'prefixes with more modules sort first'
);

# ---- payload path helpers with a leading slash
is(scalar call('_extract_payload_path', '/r', 'code', '/abs//x.pm'), '/r/code/abs/x.pm', 'leading slash dropped from logical path');
is(scalar call('_extract_payload_path', '/r', 'code', undef), '/r/code', 'undef logical path');
write_file("$T/xr/code/lib/Z/Y.pm", "1;\n");
is_deeply(call('_extracted_manifest_roots', "$T/xr", 'code', ['/lib', 'lib', '', undef]), ["$T/xr/code/lib"], 'leading slash logical root normalised and de-duplicated');

# ---- _standalone_inspect_json / _standalone_extract_quietly / _quiet_exec_command
{
    is_deeply([ call('_quiet_exec_command', '2>/dev/null', 'prog', 'a b', '$x') ],
        [ '/bin/sh', '-c', 'exec "$0" "$@" 2>/dev/null', 'prog', 'a b', '$x' ],
        'program and arguments are passed as positional shell arguments');

    my $good = write_file("$T/sj/good", "#!/bin/sh\necho \"\$@\" > \"$T/sj/args\"\necho noise >&2\nprintf '{\"ok\":1}'\n", 0755);
    my $bad = write_file("$T/sj/bad", "#!/bin/sh\necho nope\nexit 3\n", 0755);
    is(scalar call('_standalone_inspect_json', $good), '{"ok":1}', 'inspect returns the JSON the binary prints');
    is(do { open my $fh, '<', "$T/sj/args" or die; local $/; <$fh> }, "--pax-standalone-inspect\n", 'inspect flag passed');
    is(scalar call('_standalone_inspect_json', $bad), '', 'inspect of a failing binary gives nothing');
    is(scalar call('_standalone_inspect_json', "$T/no/such/exe"), '', 'inspect of a program that cannot start gives nothing');
    {
        local $FAIL_PIPE_OPEN = 1;
        is(scalar call('_standalone_inspect_json', $good), '', 'inspect gives nothing when the pipe cannot be opened');
    }

    is(scalar call('_standalone_extract_quietly', $good, "$T/ex dir"), 1, 'extract reports success');
    is(do { open my $fh, '<', "$T/sj/args" or die; local $/; <$fh> }, "--pax-standalone-extract $T/ex dir\n", 'extract flag and a root with a space passed intact');
    is(scalar call('_standalone_extract_quietly', $bad, "$T/ex"), 0, 'extract reports a failing binary');
    is(scalar call('_standalone_extract_quietly', "$T/no/such/exe", "$T/ex"), 0, 'extract of a program that cannot start fails');
}

# ---- _first_executable / _linked_shared_lib_paths
{
    my $exe = write_file("$T/fe/tool", "#!/bin/sh\n", 0755);
    my $plain = write_file("$T/fe/data", "x\n", 0644);
    is(call('_first_executable'), '', 'no candidates');
    is(call('_first_executable', undef, '', $plain, "$T/fe/missing", $exe, $plain), $exe, 'first executable file wins');
    is(call('_first_executable', undef, ''), '', 'only unusable candidates');

    my $binary = write_file("$T/fe/bin", "x\n", 0644);
    no warnings 'redefine';
    {
        local *PAX::StandaloneImage::_first_executable = sub { return '' };
        is_deeply([ call('_linked_shared_lib_paths', $binary) ], [], 'no ldd available');
    }
    {
        local *PAX::StandaloneImage::_first_executable = sub { return "$T/no/such/ldd" };
        local $SIG{__WARN__} = sub { };
        is_deeply([ call('_linked_shared_lib_paths', $binary) ], [], 'ldd that cannot start gives no libraries');
    }
}

# ---- _runtime_inc_dirs
{
    my $real = "$T/inc/real";
    my $dev = "$T/inc/devtree";
    my $file = write_file("$T/inc/afile", "x\n");
    make_path($real, $dev);
    local @INC = (sub { return }, $file, "$T/inc/missing", $real, $real, "$dev/");
    local $PAX::StandaloneImage::PAX_DEV_TREE = qr{\A\Q@{[ abs_path($dev) ]}\E(?:/|$)};
    is_deeply([ call('_runtime_inc_dirs', []) ], [ abs_path($real) ], 'non-directories, duplicates and the dev tree are skipped');
}

# ---- _related_xs_files_for_source with a module named .pm
{
    my $root = "$T/rx/root";
    write_file("$root/.pm", "1;\n");
    is_deeply([ call('_related_xs_files_for_source', "$root/.pm", [$root]) ], [], 'a file named .pm has no module parts');
    write_file("$root/Rx/Mod.pm", "1;\n");
    write_file("$root/auto/Rx/Mod/Mod.so", "so\n");
    is_deeply([ call('_related_xs_files_for_source', "$root/Rx/Mod.pm", [$root]) ], ["$root/auto/Rx/Mod/Mod.so"], 'related shared object found');
}

# ---- _runtime_tree_family_dirs
{
    my $arch = "$T/fam/lib/x86_64-linux-gnu";
    make_path($arch);
    is_deeply(
        [ call('_runtime_tree_family_dirs', [ '', "$T/fam/missing", $arch, $arch, "$T/fam/lib" ]) ],
        [ $arch, "$T/fam/lib" ],
        'unusable and duplicate dirs skipped, arch dir brings its parent'
    );
    is_deeply([ call('_runtime_tree_family_dirs', undef) ], [], 'undef dirs');
}

# ---- namespace marker regression and deterministic inference
is(scalar call('_replace_runtime_namespace', '__PAX_RUNTIME_LEGACY_NAMESPACE__/X.pm and __PAX_RUNTIME_LEGACY_NAMESPACE__::X', 'My::App'),
    'My/App/X.pm and My::App::X', 'marker path form becomes the namespace path');
is(scalar call('_infer_legacy_runtime_namespace', 'Zed::One Zed::One Alp::Two Alp::Two'), 'Alp::Two', 'tied candidates resolve alphabetically');
is(scalar call('_infer_legacy_runtime_namespace', ''), '', 'empty bytes infer nothing');

done_testing;
