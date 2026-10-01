use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneImage;

=pod

=head1 NAME

t/cov_sima_source_plan.t - coverage for rebuild-from-binary source recovery

=head1 DESCRIPTION

Covers C<_standalone_source_plan> and the helpers that recover an entrypoint,
library roots and source roots from a previously built standalone binary's
manifest: inspect/extract subprocess wrappers, source-tree materialisation and
manifest root resolution.

=head1 WHY IT EXISTS

Rebuilding from a binary is only reachable with a real standalone executable in
the normal suite. These tests use small shell scripts as stand-in binaries and
stubbed inspect/extract helpers so every branch can be reached quickly.

=cut

my $root = tempdir('pax-cov-sima-plan-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($path, $text, $mode)
# Writes a fixture file, creating parent directories first, optionally chmod-ing it.
# Input: destination path, text, optional mode. Output: the path written.
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

# plain script detection
{
    my $script = write_file("$root/s.pl", "#!/bin/sh\nexit 0\n", 0755);
    my $binary = write_file("$root/b.bin", "BINARY-DATA-NOT-SHEBANG", 0755);
    is(PAX::StandaloneImage::_looks_like_plain_script_entrypoint($script), 1, 'shebang is a script');
    is(PAX::StandaloneImage::_looks_like_plain_script_entrypoint($binary), 0, 'non-shebang is not a script');
    is(PAX::StandaloneImage::_looks_like_plain_script_entrypoint("$root/missing"), 0, 'missing file is not a script');
}

# inspect and extract subprocess wrappers
{
    my $good = write_file("$root/inspect-ok", <<'SH', 0755);
#!/bin/sh
if [ "$1" = "--pax-standalone-inspect" ]; then
  echo '{"name":"x"}'
  exit 0
fi
if [ "$1" = "--pax-standalone-extract" ]; then
  mkdir -p "$2/code" && echo done > "$2/code/marker"
  exit 0
fi
exit 3
SH
    my $bad = write_file("$root/inspect-bad", "#!/bin/sh\necho oops\nexit 4\n", 0755);
    is(PAX::StandaloneImage::_standalone_inspect_json($good), qq({"name":"x"}\n), 'inspect output returned');
    is(PAX::StandaloneImage::_standalone_inspect_json($bad), '', 'failed inspect gives empty string');
    is(PAX::StandaloneImage::_standalone_inspect_json("$root/does-not-exist"), '', 'unexecutable inspect gives empty string');

    my $dest = tempdir('ex-XXXXXX', DIR => $root, CLEANUP => 1);
    is(PAX::StandaloneImage::_standalone_extract_quietly($good, $dest), 1, 'extract succeeds');
    ok(-f "$dest/code/marker", 'extract ran the helper');
    is(PAX::StandaloneImage::_standalone_extract_quietly($bad, $dest), 0, 'failed extract reports 0');
    is(PAX::StandaloneImage::_standalone_extract_quietly("$root/does-not-exist", $dest), 0, 'missing binary reports 0');
}

# payload path helpers
{
    is(PAX::StandaloneImage::_extract_payload_path('/r', 'code', 'a//b/c.pm'), '/r/code/a/b/c.pm', 'logical path split');
    is(PAX::StandaloneImage::_extract_payload_path('/r', 'code', undef), '/r/code', 'undef logical path');
    write_file("$root/ex/code/a/b.pm", "1;\n");
    is(PAX::StandaloneImage::_extracted_manifest_path("$root/ex", 'code', 'a/b.pm'), "$root/ex/code/a/b.pm", 'existing extracted file');
    is(PAX::StandaloneImage::_extracted_manifest_path("$root/ex", 'code', 'a/nope.pm'), '', 'missing extracted file');
}

# entrypoint materialisation
{
    my $ex = "$root/mat";
    make_path($ex);
    is(PAX::StandaloneImage::_materialize_entrypoint_source($ex, {}), '', 'no bytes gives empty');
    is(PAX::StandaloneImage::_materialize_entrypoint_source($ex, { source_bytes => '' }), '', 'empty bytes gives empty');

    my $p1 = PAX::StandaloneImage::_materialize_entrypoint_source($ex, { source_bytes => "print 1;\n", source_path => '/a/tool.pl' });
    is($p1, "$ex/source-entrypoint/tool.pl", 'named after source path');
    is(do { open my $fh, '<', $p1 or die; local $/; <$fh> }, "print 1;\n", 'bytes written');
    my $p2 = PAX::StandaloneImage::_materialize_entrypoint_source($ex, { source_bytes => "x\n", logical_path => 'entrypoint/tool.script.json' });
    is($p2, "$ex/source-entrypoint/tool.pl", 'wrapper suffix rewritten to .pl');
    my $p3 = PAX::StandaloneImage::_materialize_entrypoint_source($ex, { source_bytes => "x\n", logical_path => 'entrypoint/tool.dispatch.json' });
    is($p3, "$ex/source-entrypoint/tool.pl", 'dispatch suffix rewritten');
    my $p4 = PAX::StandaloneImage::_materialize_entrypoint_source($ex, { source_bytes => "x\n", logical_path => 'entrypoint/plainname' });
    is($p4, "$ex/source-entrypoint/plainname.pl", 'extensionless name gets .pl');
    my $p5 = PAX::StandaloneImage::_materialize_entrypoint_source($ex, { source_bytes => "x\n" });
    is($p5, "$ex/source-entrypoint/entrypoint.pl", 'default name');
    make_path("$ex/source-entrypoint/blocked.pl");
    is(PAX::StandaloneImage::_materialize_entrypoint_source($ex, { source_bytes => "x\n", source_path => '/a/blocked.pl' }), '', 'unwritable destination gives empty');
}

# common parent
{
    is(PAX::StandaloneImage::_common_source_parent(), '', 'no paths');
    is(PAX::StandaloneImage::_common_source_parent(undef, ''), '', 'blank paths ignored');
    is(PAX::StandaloneImage::_common_source_parent('/a/b/c.pl'), '/a/b', 'single path');
    is(PAX::StandaloneImage::_common_source_parent('/a/b/c.pl', '/a/b/d/e.pl', '/a/f.pl'), '/a', 'shared prefix');
    is(PAX::StandaloneImage::_common_source_parent('a/x.pl', 'b/y.pl', 'c/z.pl'), '', 'nothing shared');
    is(PAX::StandaloneImage::_common_source_parent('/a/b/long/c.pl', '/a/b.pl'), '/a', 'shorter second path');
    is(PAX::StandaloneImage::_common_source_parent('/a/b.pl', '/a/b/long/c.pl'), '/a', 'shorter first path');
}

# manifest root resolution
{
    my $manifest = {
        code_units => [
            { logical_path => '', source_path => '/x/y.pm', unit_kind => 'lib' },
            { logical_path => 'lib/a.pm', source_path => '', unit_kind => 'lib' },
            { logical_path => 'lib/skip.pm', source_path => '/x/other/skip.pm', unit_kind => 'source' },
            { logical_path => 'other/Foo.pm', source_path => '/x/other/Foo.pm', unit_kind => 'lib' },
            { logical_path => 'lib/', source_path => '/x/empty.pm', unit_kind => 'lib' },
            { logical_path => 'lib/Deep/Mod/Thing.pm', source_path => '/proj/lib/Deep/Mod/Thing.pm', unit_kind => 'lib' },
            { logical_path => 'lib/Top.pm', source_path => '/proj2/lib/Top.pm' },
        ],
    };
    is(PAX::StandaloneImage::_manifest_source_root_for_logical($manifest, 'lib', 'lib'), '/proj/lib', 'multi-part relative path');
    is(PAX::StandaloneImage::_manifest_source_root_for_logical($manifest, 'lib', 'source'), '/x/other', 'kind filter and single part');
    is(PAX::StandaloneImage::_manifest_source_root_for_logical($manifest, 'lib', undef), '/x/other', 'undef kind matches all');
    is(PAX::StandaloneImage::_manifest_source_root_for_logical($manifest, 'lib', ''), '/x/other', 'empty kind matches all');
    is(PAX::StandaloneImage::_manifest_source_root_for_logical($manifest, 'nothing', 'lib'), undef, 'unknown root');
    is(PAX::StandaloneImage::_manifest_source_root_for_logical({}, 'lib', 'lib'), undef, 'no units');
    is(PAX::StandaloneImage::_manifest_source_root_for_logical({ code_units => [ {}, { logical_path => 'lib/A/B.pm' }, { source_path => '/x.pm' } ] }, 'lib', 'lib'), undef, 'units missing keys');
    is(PAX::StandaloneImage::_manifest_source_root_for_logical({ code_units => [ { logical_path => 'lib/A/B.pm', source_path => 'A/B.pm', unit_kind => 'lib' } ] }, 'lib', 'lib'), undef, 'relative source path that collapses to nothing');

    is(PAX::StandaloneImage::_original_source_root_for_logical($manifest, 'nothing', 'lib'), undef, 'original root missing');
    is(PAX::StandaloneImage::_original_source_root_for_logical($manifest, 'lib', 'lib'), undef, 'original root not on disk');
    my $disk_manifest = {
        lib_dirs => ['lib/real', '', undef, 'lib/real', 'lib/gone', 'lib/ghost'],
        code_units => [
            { logical_path => 'lib/real/A.pm', source_path => "$root/orig/lib/A.pm", unit_kind => 'lib' },
            { logical_path => 'lib/gone/B.pm', source_path => "$root/orig/gone/B.pm", unit_kind => 'lib' },
        ],
    };
    make_path("$root/orig/lib");
    is(PAX::StandaloneImage::_original_source_root_for_logical($disk_manifest, 'lib/real', 'lib'), "$root/orig/lib", 'original root on disk');
    is_deeply(PAX::StandaloneImage::_original_manifest_roots($disk_manifest, 'lib_dirs', 'lib'), ["$root/orig/lib"], 'original roots deduplicated and filtered');
    is_deeply(PAX::StandaloneImage::_original_manifest_roots({}, 'lib_dirs', 'lib'), [], 'no roots');
}

# extracted roots
{
    make_path("$root/exr/code/lib/App", "$root/exr/code/src");
    is_deeply(
        PAX::StandaloneImage::_extracted_manifest_roots("$root/exr", 'code', ['lib/App', '', undef, 'lib/App', 'lib/missing', 'src']),
        ["$root/exr/code/lib/App", "$root/exr/code/src"],
        'extracted roots deduplicated and existing only',
    );
    is_deeply(PAX::StandaloneImage::_extracted_manifest_roots("$root/exr", 'code', undef), [], 'undef roots');
}

# materialised roots
{
    my $manifest = {
        lib_dirs => ['lib/p', '', undef, 'lib/none', 'lib/outside', 'lib/missing', 'lib/p'],
        code_units => [
            { logical_path => 'lib/p/A.pm', source_path => '/src/proj/p/A.pm', unit_kind => 'lib' },
            { logical_path => 'lib/outside/B.pm', source_path => '/elsewhere/outside/B.pm', unit_kind => 'lib' },
            { logical_path => 'lib/missing/C.pm', source_path => '/src/proj/missing/C.pm', unit_kind => 'lib' },
        ],
    };
    make_path("$root/rb/p");
    my $roots = PAX::StandaloneImage::_materialized_manifest_roots($manifest, 'lib_dirs', 'lib', '/src/proj', "$root/rb");
    is_deeply($roots, ["$root/rb/p"], 'only existing, inside, unique roots survive');
    # an original root equal to the source root maps onto the rebuild root itself
    my $same = {
        lib_dirs => ['lib/top'],
        code_units => [ { logical_path => 'lib/top/T.pm', source_path => '/src/proj/T.pm', unit_kind => 'lib' } ],
    };
    is_deeply(PAX::StandaloneImage::_materialized_manifest_roots($same, 'lib_dirs', 'lib', '/src/proj', "$root/rb"), ["$root/rb"], 'root equal to source root maps to the rebuild root');
    is_deeply(PAX::StandaloneImage::_materialized_manifest_roots({}, 'lib_dirs', 'lib', '/src/proj', "$root/rb"), [], 'no roots');
}

# manifest source tree materialisation
{
    my $ex = "$root/tree";
    make_path($ex);
    my $manifest = {
        lib_dirs => ['lib/lib'],
        source_roots => ['src/tools'],
        code_units => [
            { unit_kind => 'lib', source_path => '/proj/lib/Mod/A.pm', source_bytes => "package Mod::A;\n1;\n" },
            { unit_kind => 'lib', source_path => '/proj/lib/Mod/A.pm', source_bytes => "dup\n" },
            { unit_kind => 'source', source_path => '/proj/tools/t.pl', source_bytes => "print 2;\n" },
            { unit_kind => 'dependency', source_path => '/proj/dep/D.pm', source_bytes => "ignored\n" },
            { unit_kind => 'lib', source_path => '/proj/lib/Empty.pm', source_bytes => '' },
            { unit_kind => 'lib', source_path => '', source_bytes => 'nopath' },
            { source_path => '/proj/none.pm', source_bytes => 'nokind' },
        ],
        entrypoint => { source_path => '/proj/bin/run.pl', source_bytes => "print 3;\n" },
    };
    # logical roots map onto original directories through unit logical paths
    $manifest->{code_units}[0]{logical_path} = 'lib/lib/Mod/A.pm';
    $manifest->{code_units}[2]{logical_path} = 'src/tools/t.pl';
    my $result = PAX::StandaloneImage::_materialize_manifest_source_tree($ex, $manifest);
    is($result->{entrypoint}, "$ex/rebuild-source/bin/run.pl", 'entrypoint materialised');
    is(do { open my $fh, '<', "$ex/rebuild-source/lib/Mod/A.pm" or die; local $/; <$fh> }, "package Mod::A;\n1;\n", 'first writer wins');
    ok(-f "$ex/rebuild-source/tools/t.pl", 'source unit written');
    ok(!-e "$ex/rebuild-source/dep", 'dependency units skipped');
    is_deeply($result->{lib_dirs}, ["$ex/rebuild-source/lib"], 'lib roots resolved');
    is_deeply($result->{source_roots}, ["$ex/rebuild-source/tools"], 'source roots resolved');

    # entrypoint also listed as a unit is only written once
    my $dupe = {
        code_units => [ { unit_kind => 'entrypoint', source_path => '/p/main.pl', source_bytes => "1;\n" } ],
        entrypoint => { source_path => '/p/main.pl', source_bytes => "1;\n" },
    };
    my $ex2 = "$root/tree2";
    make_path($ex2);
    my $r2 = PAX::StandaloneImage::_materialize_manifest_source_tree($ex2, $dupe);
    is($r2->{entrypoint}, "$ex2/rebuild-source/main.pl", 'entrypoint unit materialised once');

    is_deeply(PAX::StandaloneImage::_materialize_manifest_source_tree($ex2, {}), {}, 'empty manifest');
    is_deeply(
        PAX::StandaloneImage::_materialize_manifest_source_tree($ex2, { entrypoint => { source_path => '/p/a.pl', source_bytes => '' } }),
        {}, 'entrypoint without bytes',
    );
    is_deeply(
        PAX::StandaloneImage::_materialize_manifest_source_tree($ex2, { entrypoint => { source_path => '', source_bytes => 'x' } }),
        {}, 'entrypoint without path',
    );
    is_deeply(
        PAX::StandaloneImage::_materialize_manifest_source_tree($ex2, {
            code_units => [ { unit_kind => 'lib', source_path => 'a/x.pm', source_bytes => 'x' } ],
            entrypoint => { source_path => 'b/y.pl', source_bytes => 'y' },
        }),
        {}, 'no common source parent',
    );
    is_deeply(
        PAX::StandaloneImage::_materialize_manifest_source_tree($ex2, {
            code_units => [ { unit_kind => 'lib', source_path => '/p/lib/x.pm', source_bytes => 'x' } ],
        }),
        {}, 'no entrypoint among the units',
    );

    my $ex3 = "$root/tree3";
    make_path("$ex3/rebuild-source/blocked.pl");
    is_deeply(
        PAX::StandaloneImage::_materialize_manifest_source_tree($ex3, {
            entrypoint => { source_path => '/p/blocked.pl', source_bytes => 'x' },
        }),
        {}, 'unwritable destination aborts',
    );
}

# _standalone_source_plan with stubbed inspect/extract helpers
{
    my $binary = write_file("$root/plan/bin.exe", "NOT-A-SHEBANG", 0755);
    my $inspect = '';
    my $extract_ok = 1;
    my $extract_hook = sub { };
    no warnings 'redefine';
    local *PAX::StandaloneImage::_standalone_inspect_json = sub { return $inspect };
    local *PAX::StandaloneImage::_standalone_extract_quietly = sub { $extract_hook->($_[1]); return $extract_ok };
    use warnings 'redefine';

    is_deeply(PAX::StandaloneImage::_standalone_source_plan(undef), {}, 'undef entrypoint');
    is_deeply(PAX::StandaloneImage::_standalone_source_plan("$root/plan/none"), {}, 'missing entrypoint');
    write_file("$root/plan/noexec", "NOT-A-SHEBANG", 0644);
    is_deeply(PAX::StandaloneImage::_standalone_source_plan("$root/plan/noexec"), {}, 'non-executable entrypoint');
    my $script = write_file("$root/plan/script.pl", "#!/bin/sh\n", 0755);
    is_deeply(PAX::StandaloneImage::_standalone_source_plan($script), {}, 'plain script entrypoint');

    $inspect = '';
    is_deeply(PAX::StandaloneImage::_standalone_source_plan($binary), {}, 'empty inspect output');
    $inspect = 'not json at all';
    is_deeply(PAX::StandaloneImage::_standalone_source_plan($binary), {}, 'invalid json');
    $inspect = '[1,2]';
    is_deeply(PAX::StandaloneImage::_standalone_source_plan($binary), {}, 'non-hash json');
    $inspect = JSON::PP::encode_json({ name => 'x' });
    $extract_ok = 0;
    is_deeply(PAX::StandaloneImage::_standalone_source_plan($binary), {}, 'extract failure');
    $extract_ok = 1;

    # materialised source tree path
    my $asset = write_file("$root/plan/asset.txt", "a\n");
    $inspect = JSON::PP::encode_json({
        name => 'rebuilt',
        runtime => { mode => 'host_perl' },
        app => { name => 'Rebuilt', namespace => 'Re::Built', compat => { legacy_namespace => 'Re::Old' }, entrypoint_env => 'RE_ENV', entrypoint_fallback => 'fb', command => 'cmd' },
        asset_count => 1,
        assets => [ { source_path => $asset }, { source_path => "$root/plan/gone.txt" }, { source_path => '' }, {} ],
        lib_dirs => ['lib/lib'],
        source_roots => [],
        code_units => [
            { unit_kind => 'lib', logical_path => 'lib/lib/M.pm', source_path => '/orig/lib/M.pm', source_bytes => "1;\n" },
        ],
        entrypoint => { source_path => '/orig/bin/app.pl', source_bytes => "print 1;\n" },
    });
    my $plan = PAX::StandaloneImage::_standalone_source_plan($binary);
    like($plan->{entrypoint}, qr{/rebuild-source/bin/app\.pl\z}, 'materialised entrypoint');
    is($plan->{name}, 'rebuilt', 'name from manifest');
    is_deeply($plan->{assets}, [$asset], 'only existing assets kept');
    is(scalar(@{ $plan->{asset_dirs} }), 1, 'asset dir recorded');
    is($plan->{runtime_mode}, 'host_perl', 'runtime mode');
    is($plan->{app_legacy_namespace}, 'Re::Old', 'legacy namespace');
    is($plan->{app_command}, 'cmd', 'command');
    is(scalar(@{ $plan->{lib_dirs} }), 1, 'lib dirs materialised');

    # materialised flow without asset sections
    $inspect = JSON::PP::encode_json({
        name => 'noassets', runtime => {}, app => {}, lib_dirs => [], source_roots => [],
        code_units => [ { unit_kind => 'lib', source_path => '/orig/lib/M.pm', source_bytes => "1;\n" }, { unit_kind => 'lib', source_bytes => "orphan" } ],
        entrypoint => { source_path => '/orig/bin/app.pl', source_bytes => "print 1;\n" },
    });
    $plan = PAX::StandaloneImage::_standalone_source_plan($binary);
    is_deeply($plan->{assets}, [], 'no assets section');
    is_deeply($plan->{asset_dirs}, [], 'no asset count');

    # no source bytes: entrypoint source still on disk, original roots resolved
    make_path("$root/orig2/lib");
    my $entry_on_disk = write_file("$root/orig2/bin/app.pl", "print 1;\n");
    $inspect = JSON::PP::encode_json({
        name => 'ondisk',
        runtime => { mode => 'bundled_perl' },
        app => {},
        asset_count => 0,
        lib_dirs => ['lib/lib'],
        source_roots => ['src/tools'],
        code_units => [
            { unit_kind => 'lib', logical_path => 'lib/lib/M.pm', source_path => "$root/orig2/lib/M.pm" },
        ],
        entrypoint => { source_path => $entry_on_disk, logical_path => 'entrypoint/app.pl' },
    });
    $plan = PAX::StandaloneImage::_standalone_source_plan($binary);
    is($plan->{entrypoint}, $entry_on_disk, 'entrypoint taken from the original path');
    is_deeply($plan->{lib_dirs}, ["$root/orig2/lib"], 'original lib dirs');
    is_deeply($plan->{source_roots}, [], 'no source roots');
    is_deeply($plan->{asset_dirs}, [], 'no asset dirs without assets');
    is_deeply($plan->{assets}, [], 'no assets');

    # same shape with assets present and both original roots on disk
    make_path("$root/orig2/tools");
    write_file("$root/orig2/tools/t.pl", "1;\n");
    my $asset2 = write_file("$root/orig2/asset.bin", "x");
    $inspect = JSON::PP::encode_json({
        name => 'ondisk2', runtime => {}, app => {}, asset_count => 2,
        assets => [ { source_path => $asset2 }, { source_path => "$root/orig2/gone" }, { source_path => '' }, {} ],
        lib_dirs => ['lib/lib'], source_roots => ['src/tools'],
        code_units => [
            { unit_kind => 'lib', logical_path => 'lib/lib/M.pm', source_path => "$root/orig2/lib/M.pm" },
            { unit_kind => 'source', logical_path => 'src/tools/t.pl', source_path => "$root/orig2/tools/t.pl" },
        ],
        entrypoint => { source_path => $entry_on_disk },
    });
    $plan = PAX::StandaloneImage::_standalone_source_plan($binary);
    is_deeply($plan->{assets}, [$asset2], 'existing assets kept');
    is(scalar(@{ $plan->{asset_dirs} }), 1, 'asset dir for counted assets');
    is_deeply($plan->{source_roots}, ["$root/orig2/tools"], 'original source roots');

    # entrypoint path recorded but absent, no bytes, no extracted copy
    $inspect = JSON::PP::encode_json({
        name => 'absent', runtime => {}, app => {},
        entrypoint => { source_path => "$root/orig2/gone.pl", logical_path => 'entrypoint/gone.pl' },
    });
    is_deeply(PAX::StandaloneImage::_standalone_source_plan($binary), {}, 'recorded entrypoint path is missing');

    # entrypoint source only in the manifest bytes (no usable source path)
    $inspect = JSON::PP::encode_json({
        name => 'bytes', runtime => {}, app => {},
        entrypoint => { source_bytes => "print 9;\n", logical_path => 'entrypoint/b.script.json' },
    });
    $plan = PAX::StandaloneImage::_standalone_source_plan($binary);
    like($plan->{entrypoint}, qr{/source-entrypoint/b\.pl\z}, 'entrypoint materialised from bytes');
    is_deeply($plan->{lib_dirs}, [], 'no lib dirs');

    # entrypoint found in the extracted code tree; roots from the extraction
    $inspect = JSON::PP::encode_json({
        name => 'extracted', runtime => {}, app => {},
        lib_dirs => ['lib/App'], source_roots => ['src/s'],
        entrypoint => { logical_path => 'entrypoint/e.pl' },
    });
    $extract_hook = sub {
        my ($dir) = @_;
        write_file("$dir/code/entrypoint/e.pl", "print 1;\n");
        make_path("$dir/code/lib/App", "$dir/code/src/s");
    };
    $plan = PAX::StandaloneImage::_standalone_source_plan($binary);
    like($plan->{entrypoint}, qr{/code/entrypoint/e\.pl\z}, 'entrypoint from extracted code tree');
    like($plan->{lib_dirs}[0], qr{/code/lib/App\z}, 'extracted lib dir');
    like($plan->{source_roots}[0], qr{/code/src/s\z}, 'extracted source root');
    $extract_hook = sub { };

    # nothing usable at all
    $inspect = JSON::PP::encode_json({ name => 'none', runtime => {}, app => {}, entrypoint => { logical_path => 'entrypoint/none.pl' } });
    is_deeply(PAX::StandaloneImage::_standalone_source_plan($binary), {}, 'no recoverable entrypoint');
    $inspect = JSON::PP::encode_json({ name => 'none', runtime => {}, app => {} });
    is_deeply(PAX::StandaloneImage::_standalone_source_plan($binary), {}, 'no entrypoint section');
}

# naming and metadata helpers
{
    is(PAX::StandaloneImage::_default_name('/a/b/My Tool.pl'), 'My-Tool', 'name sanitised');
    is(PAX::StandaloneImage::_default_name('/'), 'pax-standalone', 'empty name falls back');
    is(PAX::StandaloneImage::_entrypoint_default_command('/a/b/run.pl'), 'run', 'command from file');
    is(PAX::StandaloneImage::_entrypoint_default_command('/'), 'pax', 'empty command falls back');
    is(PAX::StandaloneImage::_entrypoint_default_command(undef), 'pax', 'undef command falls back');

    my $meta = PAX::StandaloneImage::_app_metadata();
    is($meta->{name}, 'pax-standalone', 'default app name');
    is($meta->{command}, 'pax', 'default command');
    is($meta->{entrypoint_env}, '', 'default env');
    is($meta->{entrypoint_fallback}, 'pax', 'default fallback');
    is($meta->{compat}{legacy_namespace}, '', 'default legacy namespace');
    $meta = PAX::StandaloneImage::_app_metadata(image_name => '');
    is($meta->{name}, '', 'empty image name used as is');
    $meta = PAX::StandaloneImage::_app_metadata(image_name => 'img', entrypoint => '/x/tool.pl', app_namespace => ' Ns ');
    is($meta->{name}, 'img', 'app name defaults to image name');
    is($meta->{command}, 'tool', 'command from entrypoint');
    is($meta->{compat}{legacy_namespace}, $meta->{compat}{namespace}, 'legacy namespace defaults to namespace');
    $meta = PAX::StandaloneImage::_app_metadata(
        image_name => 'img', app_name => 'N', app_command => 'c', app_entrypoint_env => 'E',
        app_entrypoint_fallback => 'F', app_legacy_namespace => 'L::Old', app_namespace => 'N::New',
    );
    is_deeply(
        [ @{$meta}{qw(name command entrypoint_env entrypoint_fallback)}, @{ $meta->{compat} }{qw(namespace legacy_namespace)} ],
        [ 'N', 'c', 'E', 'F', 'N::New', 'L::Old' ],
        'explicit metadata kept',
    );

    is(PAX::StandaloneImage::_safe_dir_abs(undef), '', 'undef dir');
    is(PAX::StandaloneImage::_safe_dir_abs(''), '', 'empty dir');
    is(PAX::StandaloneImage::_safe_dir_abs("$root/plan/x.pl"), "$root/plan", 'resolved dir');
    is(PAX::StandaloneImage::_safe_dir_abs("$root/no/such/dir/x.pl"), "$root/no/such/dir", 'unresolvable dir kept as is');
}

done_testing;
