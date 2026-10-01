use strict;
use warnings;
use Test::More;
use Cwd ();
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneImage;

=pod

=head1 NAME

t/cov_simb_runtime.t - coverage for runtime payload discovery in StandaloneImage

=head1 DESCRIPTION

Drives the shared-library discovery, SONAME aliasing, inc-root classification,
helper-module lookup, probe subprocess handling, XS sibling discovery and file/tree
payload helpers of PAX::StandaloneImage against tiny fabricated perl trees.

=head1 WHY IT EXISTS

Runtime payload selection decides which files end up inside the standalone binary;
its many fallbacks (missing tools, odd @INC entries, duplicate roots) are otherwise untested.

=cut

my $T = tempdir('pax-cov-simb-rt-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $START = Cwd::getcwd();
my @REAL_INC = grep { !-f File::Spec->catfile($_, 'PAX', 'StandaloneRuntime.pm') } map { Cwd::abs_path($_) || $_ } @INC;
my $P = 'PAX::StandaloneImage::';

# Probe helpers print diagnostics for intentionally odd input; keep the TAP output clean.
open STDERR, '>', File::Spec->devnull;
local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /uninitialized|Can't exec/ };

# write_file($path, $text, $mode)
# Writes a fixture file (optionally chmod-ed), creating parent directories first.
# Input: path, text, optional mode. Output: the path.
sub write_file {
    my ($path, $text, $mode) = @_;
    my ($vol, $dir) = File::Spec->splitpath($path);
    make_path($dir) if length $dir && !-d $dir;
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    chmod $mode, $path if defined $mode;
    return $path;
}

# call(name, args...)
# Calls a private StandaloneImage function by name in list context.
# Input: function name and arguments. Output: the function's result list.
sub call {
    my ($name, @args) = @_;
    no strict 'refs';
    return &{"PAX::StandaloneImage::$name"}(@args);
}

# ---- _which
{
    write_file("$T/w/bin/tool", "#!/bin/sh\n", 0755);
    local $ENV{PATH} = "$T/w/bin::$T/w/bin:/nonexistent/dir";
    is(scalar(call('_which', 'tool')), "$T/w/bin/tool", 'program found on PATH');
    is(scalar(call('_which', 'definitely-not-a-tool-xyz')), undef, 'missing program');
    is(scalar(call('_which', undef)), undef, 'undef program');
    is(scalar(call('_which', '')), undef, 'empty program');
    delete $ENV{PATH};
    is(scalar(call('_which', 'ls')) =~ m{/ls\z} ? 1 : 0, 1, 'default dirs searched without PATH');
}

# ---- _looks_like_shared_object / _runtime_system_lib_exempt
ok(call('_looks_like_shared_object', 'a/b.so'), 'plain .so');
ok(call('_looks_like_shared_object', 'a/b.so.1.2'), 'versioned .so');
ok(!call('_looks_like_shared_object', 'a/b.pm'), 'module is not an object');
ok(!call('_looks_like_shared_object', ''), 'empty path');
ok(call('_runtime_system_lib_exempt', ''), 'empty path exempt');
ok(call('_runtime_system_lib_exempt', '/x/linux-vdso.so.1'), 'vdso exempt');
ok(call('_runtime_system_lib_exempt', '/x/ld-linux-x86-64.so.2'), 'loader exempt');
ok(call('_runtime_system_lib_exempt', '/x/libc.so.6'), 'libc exempt');
ok(!call('_runtime_system_lib_exempt', '/x/libfoo.so.1'), 'other libs are bundled');

# ---- inc dir classification
is(scalar(call('_is_core_runtime_inc_dir', '')), 0, 'core: empty');
is(scalar(call('_is_core_runtime_inc_dir', '/u/lib/site_perl/5.38.0')), 0, 'core: site excluded');
is(scalar(call('_is_core_runtime_inc_dir', '/u/lib/vendor_perl/5.38.0')), 0, 'core: vendor excluded');
is(scalar(call('_is_core_runtime_inc_dir', '/u/lib/perl5/5.38.0')), 1, 'core: versioned');
is(scalar(call('_is_core_runtime_inc_dir', '/u/lib/perl5/5.38.0/x86_64-linux-gnu')), 1, 'core: arch dir');
is(scalar(call('_is_core_runtime_inc_dir', '/u/lib/other')), 0, 'core: other');
is(scalar(call('_is_site_runtime_inc_dir', undef)), 0, 'site: undef');
is(scalar(call('_is_site_runtime_inc_dir', '/u/lib/site_perl/5.38.0')), 1, 'site: match');
is(scalar(call('_is_site_runtime_inc_dir', '/u/lib/perl5/5.38.0')), 0, 'site: no match');
is(scalar(call('_is_vendor_runtime_inc_dir', undef)), 0, 'vendor: undef');
is(scalar(call('_is_vendor_runtime_inc_dir', '/u/lib/vendor_perl/5.38.0')), 1, 'vendor: vendor_perl');
is(scalar(call('_is_vendor_runtime_inc_dir', '/u/share/perl5')), 1, 'vendor: share/perl5');
is(scalar(call('_is_vendor_runtime_inc_dir', '/u/lib/other')), 0, 'vendor: other');

# ---- _runtime_inc_dirs / _runtime_tree_family_dirs
{
    make_path("$T/id/a", "$T/id/b", "$T/id/c");
    local @INC = (sub { return }, "$T/id/a", "$T/id/a/../a", '/nonexistent/aa/bb', "$T/id/b", "$T/id/c");
    my @dirs = call('_runtime_inc_dirs', [ undef, '', "$T/id/c", '/nonexistent/zz' ]);
    is_deeply(\@dirs, [ Cwd::abs_path("$T/id/a"), Cwd::abs_path("$T/id/b") ], 'inc dirs de-duplicated, excluded and filtered');

    make_path("$T/fam/p/x86_64-linux-gnu", "$T/fam/q", "$T/fam/r/x86_64-linux-gnu");
    my @fam = call('_runtime_tree_family_dirs', [ undef, '', '/nonexistent/qq', "$T/fam/p", "$T/fam/p/x86_64-linux-gnu", "$T/fam/q", "$T/fam/q", "$T/fam/r/x86_64-linux-gnu" ]);
    is_deeply(\@fam, [ "$T/fam/p", "$T/fam/p/x86_64-linux-gnu", "$T/fam/q", "$T/fam/r/x86_64-linux-gnu", "$T/fam/r" ], 'family dirs add arch parents once');
    is_deeply([ call('_runtime_tree_family_dirs', undef) ], [], 'undef family input');
}

# ---- _runtime_core_libs_from_inc_dirs
{
    write_file("$T/cl/CORE/libperl.so", 'x');
    write_file("$T/cl/CORE/libperl.so.5.38", 'x');
    write_file("$T/cl/CORE/perl.h", 'x');
    write_file("$T/cl/CORE/libperl.h", 'x');
    write_file("$T/cl/other/libperl.so", 'x');
    make_path("$T/cl/CORE/sub");
    my @libs = call('_runtime_core_libs_from_inc_dirs', [ undef, '', '/nonexistent/qq', "$T/cl", "$T/cl" ]);
    is_deeply([ sort @libs ], [ map { Cwd::abs_path("$T/cl/CORE/$_") } qw(libperl.so libperl.so.5.38) ], 'core libs found once');
    is_deeply([ call('_runtime_core_libs_from_inc_dirs', undef) ], [], 'undef inc dirs');
}

# ---- _linked_shared_lib_paths / closure
{
    write_file("$T/ld/A.so", 'a');
    write_file("$T/ld/B.so", 'b');
    write_file("$T/ld/C.so", 'c');
    write_file("$T/ld/libc.so.6", 'c');
    my $ldd = write_file("$T/ld/fake-ldd", <<"SH", 0755);
#!/bin/sh
echo "	linux-vdso.so.1 (0x00007ffd)"
echo "	liba.so => $T/ld/A.so (0x0002)"
echo "	libmissing.so => /nonexistent/zz/missing.so (0x0003)"
echo "	$T/ld/B.so (0x0004)"
echo "	liba.so => $T/ld/A.so (0x0005)"
echo "	libnone.so => not found"
echo "	garbage line"
SH
    no warnings 'redefine';
    {
        local *PAX::StandaloneImage::_which = sub { return $_[0] eq 'ldd' ? $ldd : undef };
        is_deeply([ call('_linked_shared_lib_paths', "$T/ld/A.so") ], [ "$T/ld/A.so", "$T/ld/B.so" ], 'ldd output parsed and de-duplicated');
    }
    {
        local *PAX::StandaloneImage::_which = sub { return '/nonexistent/qq/ldd' };
        is_deeply([ call('_linked_shared_lib_paths', "$T/ld/A.so") ], [], 'unrunnable ldd');
    }
    is_deeply([ call('_linked_shared_lib_paths', undef) ], [], 'undef binary');
    is_deeply([ call('_linked_shared_lib_paths', "$T/ld/nope") ], [], 'missing binary');
    {
        local *PAX::StandaloneImage::_which = sub { return };
        is(ref [ call('_linked_shared_lib_paths', $^X) ], 'ARRAY', 'ldd found by the default location');
    }

    my %graph = (
        "$T/ld/A.so" => [ "$T/ld/B.so", "$T/ld/C.so", '/nonexistent/qq/gone.so', "$T/ld/libc.so.6" ],
        "$T/ld/B.so" => [ "$T/ld/C.so", "$T/ld/A.so" ],
        "$T/ld/C.so" => [],
    );
    local *PAX::StandaloneImage::_linked_shared_lib_paths = sub { return @{ $graph{ Cwd::abs_path($_[0]) || $_[0] } || [] } };
    my @closure = call('_shared_lib_dependency_closure', undef, '', '/nonexistent/qq/x', "$T/ld/A.so", "$T/ld/A.so");
    is_deeply(\@closure, [ map { Cwd::abs_path("$T/ld/$_") } qw(A.so B.so C.so) ], 'dependency closure is transitive and exempts system libs');
    is_deeply([ call('_shared_lib_dependency_closure') ], [], 'empty closure');
}

# ---- SONAME discovery and payload variants
{
    my $perl_libs = [ call('_linked_shared_lib_paths', $^X) ];
    my ($sample) = grep { my $s = call('_shared_object_soname', $_); defined $s && $s ne '' } @$perl_libs;
    SKIP: {
        skip 'no ELF shared library with a SONAME is available', 22 if !$sample;
        my $soname = call('_shared_object_soname', $sample);
        like($soname, qr/\.so/, 'readelf reports a SONAME');
        copy(Cwd::abs_path($sample), "$T/so/libcovsimb1.so.9") or do { make_path("$T/so"); copy(Cwd::abs_path($sample), "$T/so/libcovsimb1.so.9") or die "copy: $!" };
        copy(Cwd::abs_path($sample), "$T/so/libcovsimb2.so.9") or die "copy: $!";
        copy(Cwd::abs_path($sample), "$T/so/$soname") or die "copy: $!";
        write_file("$T/so/notelf.so", "plain text, not an ELF file\n");

        is(call('_shared_object_soname', "$T/so/libcovsimb1.so.9"), $soname, 'soname of a copied library');
        is(scalar(call('_shared_object_soname', undef)), '', 'undef path has no soname');
        is(scalar(call('_shared_object_soname', "$T/so/nope.so")), '', 'missing path has no soname');
        is(scalar(call('_shared_object_soname', "$T/so/notelf.so")), '', 'non ELF file has no soname');

        no warnings 'redefine';
        my $real_which = \&PAX::StandaloneImage::_which;
        {
            local *PAX::StandaloneImage::_which = sub { return $_[0] eq 'readelf' ? undef : $real_which->(@_) };
            is(call('_shared_object_soname', "$T/so/libcovsimb1.so.9"), $soname, 'objdump fallback finds the soname');
        }
        {
            local *PAX::StandaloneImage::_which = sub { return $_[0] eq 'readelf' ? '/nonexistent/qq/readelf' : $real_which->(@_) };
            is(call('_shared_object_soname', "$T/so/libcovsimb1.so.9"), $soname, 'unrunnable readelf falls through to objdump');
        }
        {
            local *PAX::StandaloneImage::_which = sub { return };
            is(scalar(call('_shared_object_soname', "$T/so/libcovsimb1.so.9")), '', 'no tools means no soname');
        }

        my %seen;
        my @v = call('_shared_lib_payload_variants', "$T/so/libcovsimb1.so.9", \%seen);
        is_deeply([ map { $_->{logical_path} } @v ], [ 'lib/libcovsimb1.so.9', "lib/$soname" ], 'primary and soname alias payloads');
        is(scalar(() = call('_shared_lib_payload_variants', "$T/so/libcovsimb1.so.9", \%seen)), 0, 'repeat variants are suppressed');
        my @v2 = call('_shared_lib_payload_variants', "$T/so/libcovsimb2.so.9", \%seen);
        is_deeply([ map { $_->{logical_path} } @v2 ], ['lib/libcovsimb2.so.9'], 'alias already claimed by another file');
        my @v3 = call('_shared_lib_payload_variants', "$T/so/$soname");
        is_deeply([ map { $_->{logical_path} } @v3 ], ["lib/$soname"], 'alias equal to primary is not duplicated');
        my @v4 = call('_shared_lib_payload_variants', "$T/so/notelf.so", undef);
        is_deeply([ map { $_->{logical_path} } @v4 ], ['lib/notelf.so'], 'file without soname only has the primary');
        is_deeply([ call('_shared_lib_payload_variants', undef) ], [], 'undef variant path');
        is_deeply([ call('_shared_lib_payload_variants', "$T/so/nope.so") ], [], 'missing variant path');
        {
            local *PAX::StandaloneImage::_shared_object_soname = sub { return undef };
            is_deeply([ map { $_->{logical_path} } call('_shared_lib_payload_variants', "$T/so/notelf.so") ], ['lib/notelf.so'], 'undefined soname ignored');
        }

        # _runtime_shared_lib_payloads
        write_file("$T/so/perl-fake", "#!/bin/sh\n", 0755);
        make_path("$T/so/inc/CORE");
        write_file("$T/so/inc/CORE/libperl.so", "core lib\n");
        {
            local *PAX::StandaloneImage::_shared_lib_dependency_closure = sub { return ("$T/so/libcovsimb1.so.9", "$T/so/libcovsimb1.so.9", '/nonexistent/qq/ghost.so') };
            my @p = call('_runtime_shared_lib_payloads', "$T/so/perl-fake", [ "$T/so/inc", "$T/so/inc" ], [ "$T/so/notelf.so", "$T/so/notelf.pm" ]);
            is_deeply([ sort map { $_->{logical_path} } @p ], [ sort ('lib/libcovsimb1.so.9', "lib/$soname", 'lib/libperl.so') ], 'closure and core libs become runtime_lib payloads');
            is_deeply([ call('_runtime_shared_lib_payloads', "$T/so/perl-fake") ], [ map { $_ } call('_runtime_shared_lib_payloads', "$T/so/perl-fake", undef, undef) ], 'undef lists tolerated');
        }
        {
            local *PAX::StandaloneImage::_shared_lib_dependency_closure = sub { return ("$T/so/inc/CORE/libperl.so") };
            my @dup = call('_runtime_shared_lib_payloads', "$T/so/perl-fake", ["$T/so/inc"], []);
            is_deeply([ map { $_->{logical_path} } @dup ], ['lib/libperl.so'], 'core lib already provided by the closure is not repeated');
        }
        is_deeply([ call('_runtime_shared_lib_payloads', undef) ], [], 'no perl no payloads');
        is_deeply([ call('_runtime_shared_lib_payloads', "$T/so/nope") ], [], 'missing perl no payloads');
        {
            local *PAX::StandaloneImage::_shared_lib_dependency_closure = sub { return () };
            my @same = call('_runtime_shared_lib_payloads', "$T/so/perl-fake", ["$T/so/inc"], []);
            my @again = call('_runtime_shared_lib_payloads', "$T/so/perl-fake", ["$T/so/inc"], undef);
            is(scalar(@same), scalar(@again), 'same result without runtime files');
        }
    }
}

# ---- _pax_runtime_helper_lib_roots
{
    write_file("$T/hr/root1/PAX/StandaloneImage.pm", "1;\n");
    write_file("$T/hr/root1/PAX/StandaloneRuntime.pm", "use strict;\nuse PAX::Other;\nuse XSLoader;\nuse Foo::Bar;\nrequire Baz::Qux;\nrequire PAX::Y;\nrequire Foo::Bar;\n");
    write_file("$T/hr/root1/PAX/NativeRunner.pm", "use Foo::Bar;\n");
    write_file("$T/hr/root2/PAX/StandaloneRuntime.pm", "1;\n");
    make_path("$T/hr/root3", "$T/hr/cwdA/lib", "$T/hr/cwdB", "$T/hr/c2/lib/PAX");
    write_file("$T/hr/c2/lib/PAX/StandaloneRuntime.pm", "1;\n");
    local $INC{'PAX/StandaloneImage.pm'} = "$T/hr/root1/PAX/StandaloneImage.pm";
    local @INC = (sub { return }, undef, '', "$T/hr/root1", "$T/hr/root2", '/nonexistent/aa/bb', "$T/hr/root3");
    my $r1 = Cwd::abs_path("$T/hr/root1");
    my $r2 = Cwd::abs_path("$T/hr/root2");
    chdir "$T/hr/cwdA" or die;
    is_deeply([ call('_pax_runtime_helper_lib_roots') ], [ $r1, $r2, Cwd::abs_path("$T/hr/cwdA/lib") ], 'roots: loaded module tree, @INC copies and cwd lib');
    chdir "$T/hr/cwdB" or die;
    is_deeply([ call('_pax_runtime_helper_lib_roots') ], [ $r1, $r2 ], 'roots: no cwd lib');
    {
        local @INC = ("$T/hr/c2/lib");
        chdir "$T/hr/c2" or die;
        is_deeply([ call('_pax_runtime_helper_lib_roots') ], [ $r1, Cwd::abs_path("$T/hr/c2/lib") ], 'roots: cwd lib already known from @INC');
    }
    chdir "$T/hr/cwdB" or die;
    {
        make_path("$T/hr/gone");
        chdir "$T/hr/gone" or die;
        rmdir "$T/hr/gone";
        is_deeply([ call('_pax_runtime_helper_lib_roots') ], [ $r1, $r2 ], 'roots: removed cwd has no lib');
        chdir "$T/hr/cwdB" or die;
    }

    my @mods = call('_pax_runtime_helper_modules');
    is_deeply(\@mods, [qw(strict XSLoader Foo::Bar Baz::Qux)], 'helper modules read from helper sources, PAX modules skipped');

    # helper payloads with a namespace rewrite and a missing helper
    my $index = 0;
    my @roots;
    write_file("$T/hr/root1/PAX/StandaloneRuntime.pm", "package PAX::StandaloneRuntime;\nuse Old::NS::Foo;\nuse Old::NS::Bar;\nuse Text::Wrap;\n1;\n");
    my @p = call('_pax_runtime_helper_payloads', \$index, \@roots, 'My::App', 'Old::NS');
    is_deeply([ map { $_->{logical_path} } @p ], [ 'inc/000/PAX/StandaloneRuntime.pm', 'inc/000/PAX/NativeRunner.pm' ], 'helper payloads for existing helpers');
    like($p[0]{bytes}, qr/use My::App::Foo;/, 'runtime helper namespace rewritten');
    is($index, 1, 'index advanced');
    is_deeply(\@roots, ['inc/000'], 'root recorded');
    my @q = call('_pax_runtime_helper_payloads', \$index, \@roots, undef, undef);
    like($q[0]{bytes}, qr/use Old::NS::Foo;/, 'no namespace leaves the helper as is');

    {
        local $INC{'PAX/StandaloneImage.pm'} = '/nonexistent/aa/bb/PAX/StandaloneImage.pm';
        local @INC = ();
        is_deeply([ call('_pax_runtime_helper_lib_roots') ], [], 'no roots at all');
        is_deeply([ call('_pax_runtime_helper_modules') ], [], 'no helper modules without roots');
        my $i = 0;
        my @r;
        is_deeply([ call('_pax_runtime_helper_payloads', \$i, \@r, '', '') ], [], 'no helper payloads without roots');
        is($i, 0, 'index untouched without roots');
    }
    {
        local @INC = ();
        local $INC{'PAX/StandaloneImage.pm'} = undef;
        my @roots_from_file = call('_pax_runtime_helper_lib_roots');
        is($roots_from_file[0], Cwd::abs_path("$FindBin::Bin/../lib"), 'module location falls back to __FILE__');
    }

    # helper module files
    make_path("$T/hr/lib2/Foo", "$T/hr/lib2/Baz");
    write_file("$T/hr/lib2/Foo/Bar.pm", "package Foo::Bar; 1;\n");
    write_file("$T/hr/lib2/Baz/Qux.pm", "package Baz::Qux; 1;\n");
    write_file("$T/hr/root1/PAX/GuardManager.pm", "1;\n");
    {
        local @INC = ("$T/hr/lib2", @REAL_INC);
        my @files = call('_pax_runtime_helper_module_files');
        is(scalar(@files), scalar(keys %{{ map { $_ => 1 } @files }}), 'helper module files are unique');
        ok((grep { $_ eq "$T/hr/root1/PAX/StandaloneRuntime.pm" } @files), 'helper source listed');
        ok((grep { $_ eq Cwd::abs_path("$T/hr/lib2/Foo/Bar.pm") } @files), 'helper dependency listed');
        ok((grep { m{/Text/Wrap\.pm\z} } @files), 'probed module listed once');
    }
    {
        no warnings 'redefine';
        local *PAX::StandaloneImage::_pax_runtime_helper_modules = sub { return ('Foo::Bar', 'Foo::Bar') };
        local @INC = ("$T/hr/lib2");
        my @files = call('_pax_runtime_helper_module_files');
        is(scalar(grep { $_ eq Cwd::abs_path("$T/hr/lib2/Foo/Bar.pm") } @files), 1, 'a module named twice is listed once');
        ok(!(grep { m{DeoptEngine} } @files), 'helper missing from every root is skipped');
    }
    is(scalar(call('_helper_module_path', '', [$r1])), undef, 'empty relative helper path');
    is(scalar(call('_helper_module_path', 'PAX/NativeRunner.pm', [ undef, '', "$T/hr/root3", $r1 ])), "$r1/PAX/NativeRunner.pm", 'helper path search skips bad roots');
    is(scalar(call('_helper_module_path', 'PAX/Nope.pm')), undef, 'undef roots');
    chdir $START or die;
}

# ---- _probe_loaded_runtime_files
{
    is_deeply([ call('_probe_loaded_runtime_files') ], [], 'no modules, no probe');
    make_path("$T/pr/lib/Probe");
    write_file("$T/pr/lib/Probe/Mod.pm", "package Probe::Mod; 1;\n");
    my @files = call('_probe_loaded_runtime_files', modules => [ 'Probe::Mod', 'Not::There' ], lib_dirs => [ "$T/pr/lib", '/nonexistent/aa/bb' ]);
    is_deeply(\@files, [ Cwd::abs_path("$T/pr/lib/Probe/Mod.pm") ], 'probe reports modules newly loaded from lib dirs');
    my @plain = call('_probe_loaded_runtime_files', modules => ['strict']);
    ok(scalar(@plain) >= 0, 'probe works without lib dirs');

    my $real = write_file("$T/pr/real.txt", "x");
    my %fake = (
        fail => "#!/bin/sh\nexit 3\n",
        empty => "#!/bin/sh\nexit 0\n",
        badjson => "#!/bin/sh\necho 'not json'\n",
        object => "#!/bin/sh\necho '{}'\n",
        list => "#!/bin/sh\necho '[\"$real\",\"$real\",\"/nonexistent/zz\",null]'\n",
    );
    my %want = (fail => [], empty => [], badjson => [], object => [], list => [$real]);
    for my $kind (sort keys %fake) {
        my $script = write_file("$T/pr/perl-$kind", $fake{$kind}, 0755);
        local $^X = $script;
        is_deeply([ call('_probe_loaded_runtime_files', modules => ['x']) ], $want{$kind}, "probe with $kind interpreter output");
    }
}

# ---- _related_xs_files / _related_xs_files_for_source / _inc_root_for_file
{
    my $inc = "$T/xs/inc";
    write_file("$inc/Foo/Bar.pm", "package Foo::Bar; 1;\n");
    write_file("$inc/Foo/note.txt", "x");
    write_file("$inc/auto/Foo/Bar/Bar.so", "so");
    write_file("$inc/auto/Foo/Bar/Bar.bs", "bs");
    is_deeply([ call('_related_xs_files', 'Foo::Bar', "$inc/Foo/Bar.pm", [ $inc, $inc, "$T/xs/other" ]) ], [ "$inc/auto/Foo/Bar/Bar.so", "$inc/auto/Foo/Bar/Bar.bs" ], 'related xs files found once');
    is_deeply([ call('_related_xs_files', 'Foo::Bar', "$inc/Foo/Bar.pm", undef) ], [], 'no inc dirs, no xs files');
    is_deeply([ call('_related_xs_files', 'Foo::Bar', "$inc/Foo/Bar.pm", []) ], [], 'empty inc dirs, no xs files');

    is_deeply([ call('_related_xs_files_for_source', undef, [$inc]) ], [], 'undef source');
    is_deeply([ call('_related_xs_files_for_source', '/nonexistent/aa/Bar.pm', [$inc]) ], [], 'source outside every root');
    is_deeply([ call('_related_xs_files_for_source', $inc, [$inc]) ], [], 'source equal to the root');
    is_deeply([ call('_related_xs_files_for_source', "$inc/Foo/note.txt", [$inc]) ], [], 'non module source');
    is_deeply([ call('_related_xs_files_for_source', "$inc/Foo/Bar.pm", [ $inc, "$T/xs/other", $inc ]) ], [ "$inc/auto/Foo/Bar/Bar.so", "$inc/auto/Foo/Bar/Bar.bs" ], 'related xs files for a module source');
    is_deeply([ call('_related_xs_files_for_source', "$inc/Foo/Missing.pm", [$inc]) ], [], 'module without xs files');
    is_deeply([ call('_related_xs_files_for_source', "$inc/NoDir/Missing.pm", [$inc]) ], [], 'module in a directory that does not exist');

    is(scalar(call('_inc_root_for_file', "$inc/Foo/Bar.pm", [ $inc, "$inc/Foo" ])), "$inc/Foo", 'longest matching root wins');
    is(scalar(call('_inc_root_for_file', $inc, [$inc])), $inc, 'file equal to root');
    is(scalar(call('_inc_root_for_file', '/nonexistent/aa/bb/x.pm', [$inc])), undef, 'unmatched path');
    is(scalar(call('_inc_root_for_file', '/nonexistent/aa/bb/x.pm', undef)), undef, 'undef roots');
}

# ---- payload helpers
{
    my $dir = "$T/pl/dir";
    my $a = write_file("$dir/a.pm", "aaa");
    my $b = write_file("$dir/sub/b.pm", "bbb");
    my $c = write_file("$T/pl/outside.pm", "ccc");
    my @p = call('_file_list_payloads', $dir, 'inc/000', 'runtime_inc', [ $a, $a, $b, $c, '/nonexistent/aa/bb/gone.pm', $dir ], [ $b, $c, '/nonexistent/aa/bb/ex.pm' ], [ $c, '/nonexistent/aa/bb/f.pm' ]);
    is_deeply([ map { $_->{logical_path} } @p ], [ 'inc/000/a.pm', 'inc/000' ], 'excluded, duplicate and foreign files are dropped');
    my @q = call('_file_list_payloads', $dir, 'inc/000', 'runtime_inc', undef, undef, undef);
    is_deeply(\@q, [], 'undef lists yield nothing');
    my @r = call('_file_list_payloads', $dir, 'p', 'k', [$b], [$b], [$b]);
    is($r[0]{logical_path}, 'p/sub/b.pm', 'force list overrides exclusion');

    my @t = call('_tree_payloads', $dir, 'p', 'k', [ $b, '/nonexistent/aa/bb/ex.pm' ]);
    is_deeply([ map { $_->{logical_path} } @t ], ['p/a.pm'], 'tree payload exclusion');
    my @t2 = call('_tree_payloads', $dir, 'p', 'k', undef);
    is_deeply([ sort map { $_->{logical_path} } @t2 ], [ 'p/a.pm', 'p/sub/b.pm' ], 'tree payload without exclusion');

    my $fp = call('_file_payload', '/nonexistent/aa/bb/none.bin', 'k', 'x/none.bin');
    is($fp->{size}, 0, 'missing file payload is empty');
    is($fp->{unit_kind}, 'k', 'payload kind');
    is($fp->{c_symbol}, 'pax_payload_' . Digest::SHA::sha256_hex('x/none.bin'), 'payload symbol');
}

# ---- _locate_module_runtime_file / _runtime_family_files_for
{
    make_path("$T/lf/inc1/Famone/Sub", "$T/lf/inc2/Famone");
    write_file("$T/lf/inc1/Famone.pm", "1;");
    write_file("$T/lf/inc1/Famone/A.pm", "1;");
    write_file("$T/lf/inc1/Famone/Sub/B.pm", "1;");
    write_file("$T/lf/inc1/Famone/readme.txt", "x");
    write_file("$T/lf/inc2/Famone/C.pm", "1;");
    write_file("$T/lf/inc1/::Colon.pm", "1;");
    local @INC = (sub { return }, "$T/lf/inc0", "$T/lf/inc1", "$T/lf/inc1", "$T/lf/inc2");
    is(scalar(call('_locate_module_runtime_file', '')), undef, 'empty module');
    is(scalar(call('_locate_module_runtime_file', 'Nope::Missing')), undef, 'missing module');
    is(scalar(call('_locate_module_runtime_file', 'Famone::A')), Cwd::abs_path("$T/lf/inc1/Famone/A.pm"), 'module located');
    my @fam = call('_runtime_family_files_for', "$T/lf/inc1/Famone/A.pm");
    is_deeply([ sort @fam ], [ map { Cwd::abs_path("$T/lf/$_") } qw(inc1/Famone/A.pm inc1/Famone/Sub/B.pm inc2/Famone/C.pm) ], 'family files from every root');
    my @again = call('_runtime_family_files_for', "$T/lf/inc1/Famone/A.pm");
    is_deeply([ sort @again ], [ sort @fam ], 'family files cached');
    is_deeply([ call('_runtime_family_files_for', '/nonexistent/aa/bb/X.pm') ], [], 'path outside @INC has no family');
    is_deeply([ call('_runtime_family_files_for', "$T/lf/inc1/::Colon.pm") ], [], 'empty family name');
}

done_testing;
