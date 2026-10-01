use strict;
use warnings;

# Replaces the global open builtin before PAX::StandaloneImage compiles so a test
# can feed a fake /proc/cpuinfo to _build_job_count; every other open is passed through.
our ($FAKE_CPUINFO, $FAKE_CPUINFO_FAIL);
BEGIN {
    *CORE::GLOBAL::open = sub (*;$@) {
        if (@_ >= 3 && defined $_[2] && !ref $_[2] && $_[2] eq '/proc/cpuinfo' && (defined $FAKE_CPUINFO || $FAKE_CPUINFO_FAIL)) {
            return 0 if $FAKE_CPUINFO_FAIL;
            my $text = $FAKE_CPUINFO;
            return CORE::open($_[0], '<', \$text);
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

t/cov_simb_helpers.t - coverage for the small source and manifest helpers of StandaloneImage

=head1 DESCRIPTION

Calls the private dependency-scan, asset-discovery, manifest-copy, native payload,
namespace-rewrite and file helpers of PAX::StandaloneImage directly with tiny
fabricated trees.

=head1 WHY IT EXISTS

These helpers hold many guard branches that the end-to-end build tests never hit;
each case here asserts a concrete return value for one guard.

=cut

my $T = tempdir('pax-cov-simb-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $S = 'PAX::StandaloneImage::';

# write_file($path, $text)
# Writes a fixture file, creating parent directories first.
# Input: path and text. Output: the path.
sub write_file {
    my ($path, $text) = @_;
    my ($vol, $dir) = File::Spec->splitpath($path);
    make_path($dir) if length $dir && !-d $dir;
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    return $path;
}

# call(name, args...)
# Calls a private StandaloneImage function by name.
# Input: function name and arguments. Output: the function's list result.
sub call {
    my ($name, @args) = @_;
    no strict 'refs';
    return &{"PAX::StandaloneImage::$name"}(@args);
}

# ---- _build_job_count
{
    local $ENV{PAX_JOBS};
    delete $ENV{PAX_JOBS};
    local $FAKE_CPUINFO = join('', map { "processor\t: $_\nmodel\t: x\n" } 0 .. 11);
    is(scalar call('_build_job_count'), 8, 'many cpus are capped at 8');
    $FAKE_CPUINFO = "processor : 0\nprocessor : 1\nprocessor : 2\n";
    is(scalar call('_build_job_count'), 3, 'cpu count is used directly under the cap');
    $FAKE_CPUINFO = "nothing here\n";
    is(scalar call('_build_job_count'), 1, 'no processors listed falls back to 1');
    local $FAKE_CPUINFO_FAIL = 1;
    is(scalar call('_build_job_count'), 1, 'unreadable cpuinfo falls back to 1');
    for my $bad ('abc', '0', '') {
        local $ENV{PAX_JOBS} = $bad;
        $FAKE_CPUINFO_FAIL = 1;
        is(scalar call('_build_job_count'), 1, "PAX_JOBS='$bad' is ignored");
    }
    local $ENV{PAX_JOBS} = '5';
    is(scalar call('_build_job_count'), 5, 'PAX_JOBS positive integer wins');
}

# ---- _progress_source_label
is(scalar call('_progress_source_label', 'code', undef), 'code:', 'undef path gives an empty label');
is(scalar call('_progress_source_label', 'code', 'a/b/c.pm'), 'code:a/b/c.pm', 'nested path is kept');
is(scalar call('_progress_source_label', 'code', 'plain.pl'), 'code:plain.pl', 'bare path stays');

# ---- _strip_pod / _skip_dependency_module / _declared_modules
is(scalar call('_strip_pod', undef), '', 'undef source strips to empty');
is(scalar call('_strip_pod', "a\n=pod\nx\n=cut\nb\n__END__\nz\n"), "a\nb\n", 'pod and END section are removed');
ok(scalar call('_skip_dependency_module', ''), 'empty module name is skipped');
ok(scalar call('_skip_dependency_module', 'strict'), 'pragma skipped');
ok(scalar call('_skip_dependency_module', 'PAX::X'), 'PAX modules skipped');
ok(!scalar call('_skip_dependency_module', 'Foo::Bar'), 'ordinary module kept');
is_deeply(
    [ call('_declared_modules', "use Foo::A;\nrequire Foo::B;\nuse parent qw(Foo::C Foo::D);\nuse base 'Foo::E';\nuse Foo::A;\n") ],
    [qw(Foo::A parent base Foo::B Foo::C Foo::D Foo::E)],
    'declared modules from use/require/parent/base are de-duplicated in order'
);

# ---- _dependency_runtime_only
{
    my %cases = (
        plain      => ["package P;\nsub x { 1 }\n1;\n", 0, 1],
        import     => ["package P;\nsub import { 1 }\n", 1, 0],
        caller     => ["package P;\nmy \@c = caller(0);\n", 1, 0],
        intoo      => ["package P;\nimport::into(1);\n", 1, 1],
        export     => ["package P;\nour \@EXPORT_OK = ();\n", 1, 0],
        exporter   => ["package P;\nuse Exporter;\n", 1, 0],
        autoload   => ["package P;\nsub AUTOLOAD { 1 }\n", 0, 0],
        evalcode   => ["package P;\neval { 1 };\n", 0, 0],
        gotoamp    => ["package P;\nsub f { goto &g }\n", 0, 0],
        globref    => ["package P;\n*foo = sub { 1 };\n", 0, 0],
        proto      => ["package P;\nsub f (\$) { 1 }\n", 0, 0],
        podonly    => ["package P;\n1;\n=pod\n\nsub import {}\n\n=cut\n", 0, 1],
    );
    for my $name (sort keys %cases) {
        my ($text, $runtime_only) = @{ $cases{$name} };
        my $path = write_file("$T/dep/$name.pm", $text);
        is(scalar call('_dependency_runtime_only', $path), $runtime_only, "runtime_only $name");
    }
    is(scalar call('_dependency_runtime_only', "$T/dep/missing.pm"), 0, 'missing file is not runtime-only');
}

# ---- _locate_pure_perl_module
{
    my $root = "$T/loc/root";
    my $dup = "$T/loc/dup";
    write_file("$root/Loc/Plain.pm", "package Loc::Plain; 1;\n");
    write_file("$root/Loc/Xs.pm", "package Loc::Xs; use XSLoader; 1;\n");
    make_path($dup);
    my $hook = sub { return };
    local $SIG{__WARN__} = sub { };
    my $found = call('_locate_pure_perl_module', 'Loc::Plain', [ undef, '', $hook, '/nonexistent/a/b', $root, $root, $dup ]);
    is($found, abs_path("$root/Loc/Plain.pm"), 'plain module located past odd roots');
    is(scalar call('_locate_pure_perl_module', 'Loc::Plain', [ undef, '', $hook, '/nonexistent/a/b', $root, $root, $dup ]), $found, 'second lookup is cached');
    is(scalar call('_locate_pure_perl_module', 'Loc::Xs', [$root]), undef, 'xs module is not pure perl');
    {
        local @INC = ($root);
        is(scalar call('_locate_pure_perl_module', 'Loc::Plain'), abs_path("$root/Loc/Plain.pm"), 'undef preferred roots uses @INC');
    }
    is(scalar call('_locate_pure_perl_module', 'Loc::Nope', [ $root, $dup ]), undef, 'missing module gives undef');
}

# ---- _module_name_from_source_path
{
    my $inc = "$T/mn/inc";
    write_file("$inc/Mn/Name.pm", "1;\n");
    make_path("$inc/Mn");
    local @INC = (sub { return }, '/nonexistent/q/r', $inc, $inc);
    is(scalar call('_module_name_from_source_path', undef), undef, 'undef path');
    is(scalar call('_module_name_from_source_path', "$inc/Mn/Name.txt"), undef, 'non pm path');
    is(scalar call('_module_name_from_source_path', '/nonexistent/z/y/Other.pm'), undef, 'outside every inc root');
    is(scalar call('_module_name_from_source_path', "$inc/Mn/Name.pm"), 'Mn::Name', 'module name derived');
    is(scalar call('_module_name_from_source_path', "$inc/.pm"), undef, 'empty relative name is rejected');
}

# ---- _entrypoint_logical_path
is(scalar call('_entrypoint_logical_path', 'bin/x', [ { source_path => 'bin/x', logical_path => 'entrypoint/x' } ]), 'entrypoint/x', 'matching unit supplies logical path');
is(scalar call('_entrypoint_logical_path', 'bin/y', [ { source_path => 'bin/x', logical_path => 'entrypoint/x' } ]), 'entrypoint/y', 'fallback builds logical path');

# ---- _perl_files / _nested_runtime_inc_dirs
{
    my $root = "$T/pf/root";
    write_file("$root/a.pm", '1;');
    write_file("$root/b.pl", '1;');
    write_file("$root/c.txt", 'x');
    write_file("$root/nested/n.pm", '1;');
    {
        local @INC = ("$root/nested", "$root/nested", $root, '/nonexistent/k/l', sub { return });
        my @all = call('_perl_files', [ "$root", '/nonexistent/m' ]);
        is_deeply([ map { s{^\Q$T\E/}{}r } @all ], [qw(pf/root/a.pm pf/root/b.pl pf/root/nested/n.pm)], 'all perl files without exclusion');
        my @some = call('_perl_files', [$root], exclude_nested_inc => 1);
        is_deeply([ map { s{^\Q$T\E/}{}r } @some ], [qw(pf/root/a.pm pf/root/b.pl)], 'nested inc dir pruned');
        is_deeply([ call('_nested_runtime_inc_dirs', $root) ], [ abs_path("$root/nested") ], 'nested inc dirs found once');
    }
    is_deeply([ call('_nested_runtime_inc_dirs', undef) ], [], 'undef root');
    is_deeply([ call('_nested_runtime_inc_dirs', '/nonexistent/zz') ], [], 'missing root');
}

# ---- _asset_manifest
{
    write_file("$T/am/one.txt", 'one');
    write_file("$T/am/dir/two.txt", 'twotwo');
    write_file("$T/am/other/one.txt", 'dup');
    my $m = call('_asset_manifest',
        [ "$T/am/one.txt", '/nonexistent/q/w/gone.txt', "$T/am/other/one.txt" ],
        [ "$T/am/dir", '/nonexistent/q/w' ]);
    is_deeply([ map { $_->{logical_path} } @$m ], [qw(one.txt two.txt)], 'missing paths skipped and duplicate logical names dropped');
    is($m->[0]{bytes}, 'one', 'first asset wins');
    is($m->[1]{size}, 6, 'size recorded');
}

# ---- _repo_private_cli_dir_from_source / _shared_private_cli_dir / _inferred_asset_dirs
{
    my $repo = "$T/ir/repo";
    make_path("$repo/lib/Deep/Er", "$repo/share/private-cli");
    my $src = write_file("$repo/lib/Deep/Er/Mod.pm", '1;');
    my $norepo = "$T/ir/norepo";
    make_path("$norepo/lib");
    write_file("$norepo/lib/X.pm", '1;');
    write_file("$T/ir/nolib/X.pm", '1;');
    my $private = abs_path("$repo/share/private-cli");
    is(scalar call('_repo_private_cli_dir_from_source', undef), undef, 'undef source');
    is(scalar call('_repo_private_cli_dir_from_source', ''), undef, 'empty source');
    is(scalar call('_repo_private_cli_dir_from_source', $src), "$repo/share/private-cli", 'private-cli dir found above lib');
    is(scalar call('_repo_private_cli_dir_from_source', "$norepo/lib/X.pm"), undef, 'lib without share/private-cli');
    is(scalar call('_repo_private_cli_dir_from_source', "$T/ir/nolib/X.pm"), undef, 'no lib ancestor');
    is(scalar call('_repo_private_cli_dir_from_source', 'relative.pl'), undef, 'relative path terminates');

    is(scalar call('_shared_private_cli_dir', undef), undef, 'undef dist');
    is(scalar call('_shared_private_cli_dir', ''), undef, 'empty dist');
    {
        local %INC = %INC;
        delete $INC{'File/ShareDir.pm'};
        local @INC = ();
        is(scalar call('_shared_private_cli_dir', 'anything'), undef, 'missing File::ShareDir yields no dir');
    }
    make_path("$T/ir/repo2/lib", "$T/ir/repo2/share/private-cli", "$T/ir/share3/private-cli");
    my $src2 = write_file("$T/ir/repo2/lib/M2.pm", '1;');
    make_path("$T/ir/share1/private-cli", "$T/ir/share2");
    require File::ShareDir;
    {
        no warnings 'redefine';
        local *File::ShareDir::dist_dir = sub {
            my ($dist) = @_;
            return "$T/ir/share1" if $dist eq 'has';
            return "$T/ir/share2" if $dist eq 'noprivate';
            return "$T/ir/share3" if $dist eq 'fresh';
            die "no dist\n" if $dist eq 'dies';
            return '/nonexistent/qq/ww' if $dist eq 'gone';
            return;
        };
        is(scalar call('_shared_private_cli_dir', 'has'), "$T/ir/share1/private-cli", 'shared private-cli found');
        is(scalar call('_shared_private_cli_dir', 'noprivate'), undef, 'dist without private-cli');
        is(scalar call('_shared_private_cli_dir', 'dies'), undef, 'dist_dir failure');
        is(scalar call('_shared_private_cli_dir', 'gone'), undef, 'dist dir missing on disk');
        is(scalar call('_shared_private_cli_dir', 'nothing'), undef, 'dist_dir returned nothing');

        my @dirs = call('_inferred_asset_dirs', [
            'notahash',
            { source_path => $src, subs => [ 'x', { op => 'internal_cli_repo_private_cli_root' }, { op => 'internal_cli_repo_private_cli_root' } ] },
            { source_path => "$T/ir/nolib/X.pm", subs => [ { op => 'internal_cli_repo_private_cli_root' }, {} ] },
            { subs => [ { op => 'internal_cli_shared_private_cli_root', dist_name => 'has' }, { op => 'internal_cli_shared_private_cli_root', dist_name => 'has' }, { op => 'internal_cli_shared_private_cli_root', dist_name => 'gone' } ] },
            { source_bytes => '' },
            { source_bytes => "private-cli _helper_asset_path dist_dir('fresh')", source_path => $src2 },
            { source_bytes => "private-cli _helper_asset_path dist_dir('fresh')", source_path => $src2 },
            { source_bytes => 'only private-cli here' },
            { source_bytes => 'private-cli and _helper_asset_path', source_path => $src },
            { source_bytes => "private-cli _helper_asset_path dist_dir('has')", source_path => "$T/ir/nolib/X.pm" },
            { source_bytes => "private-cli _helper_asset_path", source_path => "$T/ir/nolib/X.pm" },
        ]);
        is_deeply(\@dirs, [ "$repo/share/private-cli", "$T/ir/share1/private-cli", "$T/ir/repo2/share/private-cli", "$T/ir/share3/private-cli" ], 'asset dirs inferred and de-duplicated');
        is_deeply([ call('_inferred_asset_dirs', undef) ], [], 'undef units');
    }
}

# ---- _source_hash / _payload_bytes
{
    my $a = [ { logical_path => 'a', sha256 => '1', size => 2 } ];
    my $with = call('_source_hash', $a, [ { logical_path => 'b', sha256 => '2' } ], [ { logical_path => 'c', sha256 => '3' } ], [ { logical_path => 'd', sha256 => '4' } ]);
    my $without = call('_source_hash', $a, [ { logical_path => 'b', sha256 => '2' } ]);
    isnt($with, $without, 'runtime and native payloads change the hash');
    like($with, qr/\A[0-9a-f]{64}\z/, 'sha256 hex');
    is(scalar call('_payload_bytes', [ { size => 3 }, { size => 4 } ]), 7, 'payload byte total');
}

# ---- _toolchain_path
is(scalar call('_toolchain_path', '/opt/x/cc', undef, '', '/opt/x/objcopy', '/usr/bin/ld'),
    '/opt/x:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin', 'toolchain path is de-duplicated and padded');

# ---- _manifest_fast_version
{
    my $json = sub { JSON::PP::encode_json($_[0]) };
    my $m = {
        entrypoint => { logical_path => 'e.pl' },
        code_units => [
            'str',
            { logical_path => 'other', bytes => $json->({ version => '9' }) },
            { logical_path => 'e.pl' },
            { logical_path => 'e.pl', bytes => '' },
            { logical_path => 'e.pl', bytes => 'not json' },
            { logical_path => 'e.pl', bytes => '[1]' },
            { logical_path => 'e.pl', bytes => $json->({ version => '' }) },
            { logical_path => 'e.pl', bytes => $json->({}) },
            { logical_path => 'e.pl', bytes => $json->({ version => '1.2' }) },
        ],
    };
    is(scalar call('_manifest_fast_version', $m), '1.2', 'first usable version is returned');
    is(scalar call('_manifest_fast_version', { entrypoint => {} }), undef, 'no units gives undef');
    is(scalar call('_manifest_fast_version', { entrypoint => { logical_path => 'e.pl' }, code_units => [ { bytes => $json->({ version => '3' }) } ] }), undef, 'unit without logical path does not match');
}

# ---- _launcher_manifest / _manifest_without_bytes / _strip_payload
{
    my $lm = call('_launcher_manifest', {});
    is_deeply($lm->{code_units}, [], 'launcher manifest of an empty manifest has no units');
    ok(!exists $lm->{runtime_payloads}, 'runtime payloads removed');
    my $full = call('_manifest_without_bytes', {});
    is_deeply([ @{$full}{qw(code_units runtime_payloads assets native_payloads)} ], [ [], [], [], [] ], 'missing lists become empty');
    is_deeply(call('_strip_payload', { a => 1, bytes => 'x' }), { a => 1 }, 'bytes removed from payload');
}

# ---- _native_payloads / _native_dispatch_manifest / _strip_native_runtime_paths
{
    my $exe = write_file("$T/np/probe", 'exe');
    my $lib = write_file("$T/np/lib.so", 'lib');
    my $ir = write_file("$T/np/m.ll", 'ir');
    my $p = call('_native_payloads', [
        { region_id => 'r0' },
        { region_id => 'r1', executable_path => '/nonexistent/q/probe' },
        { region_id => 'r2', executable_path => $exe },
        { region_id => 'r3', executable_path => $exe, library_path => $lib, tier2_artifact => { path => $ir } },
        { region_id => 'r4', executable_path => $exe, library_path => '/nonexistent/q/l.so', tier2_artifact => { path => '/nonexistent/q/m.ll' } },
        { region_id => 'r5', executable_path => $exe, tier2_artifact => {} },
    ]);
    is_deeply([ map { $_->{logical_path} } @$p ],
        [qw(native/r2/probe native/r3/probe native/r3/library.so native/r3/module.ll native/r4/probe native/r5/probe)],
        'native payload logical paths');
    my $d = call('_native_dispatch_manifest', [
        { status => 'x' },
        { region_id => 'a', region_name => 'n', status => 's', entry_kind => 'k', reason => 'r', executable_path => $exe, library_path => $lib, tier2_artifact => { path => $ir }, guards => ['g'], deopt => { a => 1 } },
        { region_id => 'b' },
    ]);
    is(scalar @$d, 2, 'region-less item skipped');
    is($d->[0]{executable_logical_path}, 'native/a/probe', 'executable path');
    is($d->[0]{library_logical_path}, 'native/a/library.so', 'library path');
    is($d->[0]{tier2_logical_path}, 'native/a/module.ll', 'tier2 path');
    is_deeply($d->[0]{guards}, ['g'], 'guards kept');
    is_deeply($d->[1]{guards}, [], 'guards default');
    is_deeply($d->[1]{deopt}, {}, 'deopt default');
    is($d->[1]{executable_logical_path}, undef, 'no exe');
    is($d->[1]{library_logical_path}, undef, 'no lib');
    is($d->[1]{tier2_logical_path}, undef, 'no tier2');
    my $s = call('_strip_native_runtime_paths', { executable_path => 'x', library_path => 'y', tier2_artifact => { path => 'z', k => 1 }, keep => 1 });
    is_deeply($s, { tier2_artifact => { k => 1 }, keep => 1 }, 'runtime paths stripped');
    is_deeply(call('_strip_native_runtime_paths', { executable_path => 'x', tier2_artifact => 'scalar' }), { tier2_artifact => 'scalar' }, 'non hash tier2 left alone');
}

# ---- _string_array_c / _c_string / _safe_logical_path / _logical_name
like(scalar call('_string_array_c', 'n', undef), qr/n_count = 0;.*n\[\] = \{ 0 \}/s, 'undef array');
like(scalar call('_string_array_c', 'n', []), qr/n_count = 0;/, 'empty array');
like(scalar call('_string_array_c', 'n', [ 'a"b', "c\\d\n" ]), qr/n_count = 2;.*"a\\"b",.*"c\\\\d\\n",/s, 'array escapes strings');
is(scalar call('_c_string', "a\"b\\c\nd"), '"a' . '\\"' . 'b' . '\\\\' . 'c' . '\\n' . 'd"', 'c string escaping');
is(scalar call('_safe_logical_path', 'a/../b/./c//d'), 'a/b/c/d', 'logical path scrubbed');
is(scalar call('_logical_name', '/x/y/z.txt'), 'z.txt', 'logical name');

# ---- _write_json / _write_binary / _slurp_bytes
{
    call('_write_json', "$T/wj/deep/m.json", { code_units => [ { bytes => 'x', n => 1 } ] });
    my $text = do { open my $fh, '<', "$T/wj/deep/m.json" or die; local $/; <$fh> };
    unlike($text, qr/"bytes"/, 'json written without payload bytes');
    like($text, qr/"n"\s*:\s*1/, 'json carries fields');
    call('_write_json', "$T/wj/deep/m2.json", {});
    ok(-f "$T/wj/deep/m2.json", 'json written into an existing dir');
    call('_write_json', 'cov_simb_cwd.json.tmp', {});
    ok(unlink('cov_simb_cwd.json.tmp'), 'json written to cwd-relative path');
    call('_write_binary', "$T/wb/deep/b.bin", "\0\1\2");
    call('_write_binary', "$T/wb/deep/b2.bin", "x");
    is(scalar call('_slurp_bytes', "$T/wb/deep/b.bin"), "\0\1\2", 'binary round trip');
    is(scalar call('_slurp_bytes', "$T/wb/missing"), '', 'missing file slurps empty');
    write_file("$T/wb/empty", '');
    is(scalar call('_slurp_bytes', "$T/wb/empty"), '', 'empty file slurps empty');
    call('_write_binary', 'cov_simb_cwd.bin.tmp', 'x');
    ok(unlink('cov_simb_cwd.bin.tmp'), 'binary written to cwd-relative path');
    eval { call('_write_binary', "$T/wb/deep", 'z') };
    like($@, qr/cannot write/, 'unwritable binary path dies');
    eval { call('_write_json', "$T/wb/deep", {}) };
    like($@, qr/cannot write/, 'unwritable json path dies');
}

# ---- _module_uses_xs
{
    write_file("$T/xs/A.pm", "package A; use XSLoader; 1;");
    write_file("$T/xs/B.pm", "package B; 1;");
    write_file("$T/xs/B.so", "x");
    write_file("$T/xs/C.pm", "package C; 1;");
    ok(scalar call('_module_uses_xs', "$T/xs/A.pm"), 'XSLoader means xs');
    ok(scalar call('_module_uses_xs', "$T/xs/B.pm"), 'sibling shared object means xs');
    ok(!scalar call('_module_uses_xs', "$T/xs/C.pm"), 'plain module');
}

# ---- namespace helpers
is(scalar call('_normalize_namespace', undef), '', 'undef namespace');
is(scalar call('_normalize_namespace', ' ::A::B:: '), 'A::B', 'namespace trimmed');
is(scalar call('_replace_runtime_namespace', '', 'My::App'), '', 'empty bytes returned as is');
is(scalar call('_replace_runtime_namespace', 'x', undef), 'x', 'undef namespace returns bytes');
is(scalar call('_replace_runtime_namespace', 'x', ''), 'x', 'empty namespace returns bytes');
is(scalar call('_replace_runtime_namespace', "use __PAX_RUNTIME_LEGACY_NAMESPACE__::Foo; require '__PAX_RUNTIME_LEGACY_NAMESPACE__/Foo.pm';", 'My::App'),
    "use My::App::Foo; require 'My/App/Foo.pm';", 'marker is replaced in both the package and the path form');
is(scalar call('_replace_runtime_namespace', "Old::NS::Foo and Old/NS/Foo.pm", 'My::App', 'Old::NS'),
    "My::App::Foo and My/App/Foo.pm", 'explicit legacy namespace replaced');
is(scalar call('_replace_runtime_namespace', "Old::NS::Foo Old::NS::Bar Old::NS::Baz", 'My::App'),
    "My::App::Foo My::App::Bar My::App::Baz", 'legacy namespace inferred');
is(scalar call('_replace_runtime_namespace', "Old::NS::Foo Old::NS::Bar", 'Old::NS', 'Old::NS'),
    "Old::NS::Foo Old::NS::Bar", 'same namespace left alone');
is(scalar call('_replace_runtime_namespace', "nothing to see", 'My::App'), 'nothing to see', 'no namespace to infer');
is(scalar call('_infer_legacy_runtime_namespace', ''), '', 'infer from empty');
is(scalar call('_infer_legacy_runtime_namespace', 'A::B A::B::C X::Y'), 'A::B', 'most common prefix wins');
is(scalar call('_infer_legacy_runtime_namespace', 'plain words'), '', 'nothing to infer');

done_testing;
