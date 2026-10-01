use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::AppImage;

=pod

=head1 NAME

t/cov_mia_appimage.t - coverage tests for PAX::AppImage

=head1 DESCRIPTION

Builds app images from fabricated entrypoints, libraries and assets, using fake
C compilers on a controlled PATH so every launcher outcome is deterministic.

=head1 WHY IT EXISTS

Covers every branch of image construction, asset manifests, preload discovery,
source hashing and launcher compilation without needing a real toolchain.

=cut

my $tmp = tempdir('pax-cov-mia-appimage-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($path, $text, $mode)
# Writes a fixture file (creating parents) and optionally chmods it.
# Input: path, bytes, optional mode. Output: path.
sub write_file {
    my ($path, $text, $mode) = @_;
    my ($dir) = $path =~ m{\A(.*)/[^/]+\z};
    make_path($dir) if defined $dir && !-d $dir;
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    chmod $mode, $path if defined $mode;
    return $path;
}

# fake_bin($dir, $name, $body)
# Creates an executable shell script used as a fake compiler.
# Input: directory, command name, shell body. Output: dir.
sub fake_bin {
    my ($dir, $name, $body) = @_;
    write_file("$dir/$name", "#!/bin/sh\n$body\n", 0755);
    return $dir;
}

# --- new
{
    local $ENV{PAX_APP_ROOT} = '/env/root';
    is(PAX::AppImage->new(root => '/explicit')->{root}, '/explicit', 'new honours explicit root');
    is(PAX::AppImage->new->{root}, '/env/root', 'new falls back to PAX_APP_ROOT');
    delete $ENV{PAX_APP_ROOT};
    is(PAX::AppImage->new->{root}, '.pax/apps', 'new falls back to the default root');
}

# --- small helpers
is(PAX::AppImage::_default_name('/x/my app!.pl'), 'my-app-.pl', '_default_name sanitises the file name');
is(PAX::AppImage::_default_name('/x/dir/'), 'pax-app', '_default_name falls back when there is no file name');
is(PAX::AppImage->new(root => '/r')->path_for('n'), '/r/n/image.json', 'path_for joins root, name and image.json');
is(PAX::AppImage::_c_string(qq{a\\b"c}), q{"a\\\\b\\"c"}, '_c_string escapes backslash and quote');
is(PAX::AppImage::_safe_logical_path('../a/./b//c'), 'a/b/c', '_safe_logical_path drops unsafe segments');
is(PAX::AppImage::_logical_name('/x/y/z.txt'), 'z.txt', '_logical_name returns the basename');
is(PAX::AppImage::_slurp("$tmp/absent"), '', '_slurp returns empty for unreadable file');
is(PAX::AppImage::_slurp_bytes("$tmp/absent"), '', '_slurp_bytes returns empty for unreadable file');
is(PAX::AppImage::_slurp($tmp), '', '_slurp returns empty when the read itself fails (directory)');
is(PAX::AppImage::_slurp_bytes($tmp), '', '_slurp_bytes returns empty when the read itself fails (directory)');
is(PAX::AppImage::_asset_bytes([ { size => 3 }, { size => 4 } ]), 7, '_asset_bytes sums sizes');

# --- _which
{
    my $bin = fake_bin("$tmp/which-bin", 'tool', 'exit 0');
    local $ENV{PATH} = "$tmp/nowhere:$bin";
    is(PAX::AppImage::_which('tool'), "$bin/tool", '_which finds an executable on PATH');
    is(PAX::AppImage::_which('missing-tool'), undef, '_which returns undef when nothing matches');
    delete $ENV{PATH};
    is(PAX::AppImage::_which('tool'), undef, '_which tolerates an undefined PATH');
}

# --- _perl_files / _source_hash / preload discovery
my $lib = "$tmp/lib";
write_file("$lib/My/Mod.pm", "package My::Mod;\nuse strict;\nuse JSON::PP;\nrequire Text::Wrap;\n1;\n");
write_file("$lib/script.pl", "use Data::Dumper;\n");
write_file("$lib/plainname", "use File::Spec;\n");
write_file("$lib/has space.txt", "use Not::Included;\n");
{
    my @files = sort(PAX::AppImage::_perl_files([ $lib, "$tmp/no-such-lib" ]));
    is_deeply([ map { s/\A\Q$lib\E\///r } @files ], [ 'My/Mod.pm', 'script.pl' ],
        '_perl_files skips missing dirs and keeps only .pm/.pl paths');
}

my $entry = write_file("$tmp/app/main.pl", "use strict;\nuse warnings;\nuse List::Util;\nrequire POSIX;\n");
is_deeply(PAX::AppImage::_discover_preload_modules($entry, [$lib]),
    [ qw(Data::Dumper JSON::PP List::Util POSIX Text::Wrap) ],
    '_discover_preload_modules collects use/require, ignoring pragmas');

{
    my $h1 = PAX::AppImage::_source_hash($entry, [$lib], []);
    my $h2 = PAX::AppImage::_source_hash($entry, [$lib], undef);
    is($h1, $h2, '_source_hash treats undef assets as empty');
    like($h1, qr/\A[0-9a-f]{64}\z/, '_source_hash is a sha256 digest');
    my $h3 = PAX::AppImage::_source_hash("$tmp/app/gone.pl", [$lib], []);
    isnt($h3, $h1, '_source_hash skips non-files and changes with the file set');
    my $h4 = PAX::AppImage::_source_hash($entry, [$lib], [ { logical_path => 'a', sha256 => 'b' } ]);
    isnt($h4, $h1, '_source_hash incorporates asset digests');
}

# --- assets
my $asset_a = write_file("$tmp/assets/a.txt", "AAA");
my $asset_empty = write_file("$tmp/assets/empty.bin", "");
write_file("$tmp/adir/sub/b.txt", "BBBB");
write_file("$tmp/adir/a.txt", "dup");
{
    my $m = PAX::AppImage::_asset_manifest(
        [ $asset_a, $asset_empty, "$tmp/nodir/nonexistent", $asset_a ],
        [ "$tmp/adir", "$tmp/nodir/no-such-dir" ],
    );
    is_deeply([ map { $_->{logical_path} } @$m ], [ 'a.txt', 'empty.bin', 'sub/b.txt' ],
        '_asset_manifest dedupes logical names and skips unresolved paths and dirs');
    is($m->[0]{size}, 3, 'asset size recorded');
    is($m->[0]{bytes}, 'AAA', 'asset bytes recorded');
    my $table = PAX::AppImage::_asset_table_c($m);
    like($table, qr/pax_asset_count = 3;/, '_asset_table_c counts assets');
    like($table, qr/\{ 0x41, 0x41, 0x41 \}/, '_asset_table_c emits bytes');
    like($table, qr/\{ 0 \};/, '_asset_table_c emits a 0 placeholder for an empty asset');
    like(PAX::AppImage::_asset_table_c([]), qr/pax_asset_count = 0;/, '_asset_table_c handles no assets');
}

# --- launcher source
{
    my $src = PAX::AppImage::_launcher_source({
        socket_path => '/s/sock', entrypoint => '/e/main.pl', asset_root => '/a/root',
    });
    like($src, qr/int main\(/, '_launcher_source renders with missing lib_dirs/assets');
    like($src, qr{"/s/sock"}, 'socket path embedded');
    my $src2 = PAX::AppImage::_launcher_source({
        socket_path => '/s', entrypoint => '/e', asset_root => '/a', lib_dirs => [ '/l1', '/l2' ], assets => [],
    });
    like($src2, qr{"/l1:/l2"}, 'lib_dirs joined into PERL5LIB literal');
}

# --- _compile_launcher outcomes
{
    my $img_dir = "$tmp/img";
    make_path($img_dir);
    my %base = (socket_path => "$img_dir/s", entrypoint => '/e', asset_root => '/a', assets => [], lib_dirs => []);

    my $r = PAX::AppImage::_compile_launcher({ %base, launcher_path => "$tmp/no-dir/launcher" });
    is($r->{status}, 'not_built', 'unwritable launcher source -> not_built');
    like($r->{reason}, qr/cannot write launcher source/, 'reason names the write failure');

    {
        local $ENV{PATH} = "$tmp/empty-path";
        $r = PAX::AppImage::_compile_launcher({ %base, launcher_path => "$img_dir/l1" });
        is($r->{reason}, 'no C compiler available', 'no compiler on PATH');
    }
    {
        my $bin = fake_bin("$tmp/cc-fail", 'cc', 'exit 3');
        local $ENV{PATH} = $bin;
        $r = PAX::AppImage::_compile_launcher({ %base, launcher_path => "$img_dir/l2" });
        is($r->{reason}, 'C launcher compile failed', 'failing cc reported');
    }
    {
        my $bin = fake_bin("$tmp/cc-nox", 'cc', 'exit 0');
        local $ENV{PATH} = $bin;
        $r = PAX::AppImage::_compile_launcher({ %base, launcher_path => "$img_dir/l3" });
        is($r->{reason}, 'C launcher compile failed', 'cc success without an executable output is a failure');
    }
    {
        my $bin = fake_bin("$tmp/gcc-ok", 'gcc', 'while [ "$1" != "-o" ]; do shift; done; : > "$2"; /bin/chmod 755 "$2"');
        local $ENV{PATH} = $bin;
        $r = PAX::AppImage::_compile_launcher({ %base, launcher_path => "$img_dir/l4" });
        is_deeply($r, { status => 'built' }, 'gcc fallback produces a built launcher');
        ok(-x "$img_dir/l4", 'launcher executable exists');
    }
}

# --- build / load
{
    my $bin = fake_bin("$tmp/cc-build", 'cc', 'while [ "$1" != "-o" ]; do shift; done; : > "$2"; /bin/chmod 755 "$2"');
    local $ENV{PATH} = $bin;
    my $apps = PAX::AppImage->new(root => "$tmp/apps");
    my $res = $apps->build(
        entrypoint => $entry,
        name => 'named',
        lib_dirs => [ $lib, "$tmp/nodir/nonexistent-lib" ],
        assets => [$asset_a],
        asset_dirs => ["$tmp/adir"],
    );
    is($res->{status}, 'built', 'build reports built');
    is($res->{image}{name}, 'named', 'explicit name used');
    is($res->{image}{launcher_status}, 'built', 'launcher built via fake cc');
    ok(!exists $res->{image}{launcher_reason}, 'no reason when the launcher built');
    is($res->{image}{asset_count}, 2, 'asset count recorded');
    ok(-f $res->{config_path}, 'image.json written');
    my $loaded = $apps->load(name => 'named');
    is($loaded->{name}, 'named', 'load round-trips image.json');
    is($loaded->{launcher_status}, 'built', 'persisted launcher status');
    ok(grep({ $_ eq "$tmp/nodir/nonexistent-lib" } @{ $loaded->{lib_dirs} }), 'unresolvable lib dir kept verbatim');

    my $default = $apps->build(entrypoint => $entry);
    is($default->{image}{name}, 'main.pl', 'default name derived from entrypoint');
    is_deeply($default->{image}{assets}, [], 'no assets by default');

    local $ENV{PATH} = "$tmp/empty-path";
    my $nocc = $apps->build(entrypoint => $entry, name => 'nocc');
    is($nocc->{image}{launcher_status}, 'not_built', 'launcher not built without a compiler');
    is($nocc->{image}{launcher_reason}, 'no C compiler available', 'reason persisted');

    eval { $apps->build };
    like($@, qr/entrypoint required/, 'build requires an entrypoint');
    eval { $apps->build(entrypoint => "$tmp/nodir/nope.pl") };
    like($@, qr/entrypoint not found/, 'build rejects a missing entrypoint');
    eval { $apps->load };
    like($@, qr/name required/, 'load requires a name');
    eval { $apps->load(name => 'never-built') };
    like($@, qr/cannot read app image/, 'load fails for an unknown image');
}

# --- _write_json failure
eval { PAX::AppImage::_write_json("$tmp/no-dir/x.json", {}) };
like($@, qr/cannot write/, '_write_json dies when it cannot open the file');

done_testing;
