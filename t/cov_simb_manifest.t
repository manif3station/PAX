use strict;
use warnings;
use Test::More;
use Cwd ();
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneImage;

=pod

=head1 NAME

t/cov_simb_manifest.t - coverage for runtime manifest and runtime file selection

=head1 DESCRIPTION

Builds tiny fake perl trees (core, arch, site and vendor style inc roots) and a fake
perl executable, then calls _expand_runtime_module_files, _runtime_selected_files and
_runtime_manifest to check which files become runtime payloads and in which order.

=head1 WHY IT EXISTS

Inc-root selection, runtime payload de-duplication and namespace replacement decide the
content of every standalone binary, and the full build is too slow to cover each branch.

=cut

my $T = tempdir('pax-cov-simb-man-XXXXXX', TMPDIR => 1, CLEANUP => 1);
open STDERR, '>', File::Spec->devnull;
local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /uninitialized/ };

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

# rp(path)
# Resolves a path the way the module under test does.
# Input: path. Output: absolute path.
sub rp { return Cwd::abs_path($_[0]) || $_[0] }

# rel_list(base, paths)
# Strips the fixture base directory from absolute paths and sorts them.
# Input: base dir and paths. Output: sorted relative path list.
sub rel_list {
    my ($base, @paths) = @_;
    my $abs_base = rp($base);
    return sort map { my $p = $_; $p =~ s{^\Q$abs_base\E/}{}; $p } @paths;
}

# ---- _expand_runtime_module_files
{
    my $inc = "$T/ex/inc";
    write_file("$inc/Fake/Dep.pm", "package Fake::Dep;\nuse Dep::Two;\nuse strict;\nrequire Missing::Mod;\n1;\n");
    write_file("$inc/Fake/Other.pm", "package Fake::Other; 1;\n");
    write_file("$inc/Dep/Two.pm", "package Dep::Two;\nuse Fake::Dep;\n1;\n");
    write_file("$inc/auto/Fake/Dep/Dep.so", "so");
    write_file("$inc/Plain.pl", "use Fake::Other;\n");
    write_file("$inc/blob.so", "so");
    local @INC = ($inc);
    my @got = PAX::StandaloneImage::_expand_runtime_module_files(
        inc_dirs => [$inc],
        seed_files => [ undef, '/nonexistent/aa/bb/x.pm', "$inc/Fake/Dep.pm", "$inc/Fake/Dep.pm", "$inc/blob.so", "$inc/Plain.pl" ],
    );
    is_deeply([ rel_list($inc, @got) ], [qw(Dep/Two.pm Fake/Dep.pm Fake/Other.pm Plain.pl auto/Fake/Dep/Dep.so blob.so)], 'expansion follows families, declared modules and xs files');
    is_deeply([ PAX::StandaloneImage::_expand_runtime_module_files() ], [], 'no arguments, no files');
    is_deeply([ rel_list($inc, PAX::StandaloneImage::_expand_runtime_module_files(seed_files => ["$inc/Fake/Other.pm"])) ], [qw(Dep/Two.pm Fake/Dep.pm Fake/Other.pm)], 'missing inc_dirs tolerated');
}

# ---- _sibling_data_files
{
    my $dir = "$T/sd/pkg";
    write_file("$dir/M.pm", "1;");
    write_file("$dir/data.txt", "d");
    write_file("$dir/.hidden", "h");
    write_file("$dir/doc.pod", "p");
    write_file("$dir/native.so", "s");
    make_path("$dir/subdir");
    write_file("$T/sd/rootlevel/R.pm", "1;");
    write_file("$T/sd/rootlevel/ignored.txt", "x");
    open my $big, '>', "$dir/big.bin" or die;
    truncate $big, 3_000_000;
    close $big;
    my @found = PAX::StandaloneImage::_sibling_data_files(
        [ "$dir/M.pm", "$dir/M.pm", "$dir/skip.txt", '/nonexistent/cc/dd/X.pm', "$T/sd/rootlevel/R.pm" ],
        [ '/nonexistent/aa/bb', "$T/sd/rootlevel" ],
    );
    is_deeply([ rel_list($T, @found) ], ['sd/pkg/data.txt'], 'only small sibling data files are returned');
}

# ---- _runtime_selected_files
{
    my $inc = "$T/sel/inc";
    my $out = "$T/sel/outside";
    write_file("$inc/Selfam/Dep.pm", "package Selfam::Dep; 1;\n");
    write_file("$inc/Selfam/data.txt", "data");
    write_file("$inc/Xs/Mod.pm", "package Xs::Mod; 1;\n");
    write_file("$inc/auto/Xs/Mod/Mod.so", "so");
    write_file("$inc/auto/Xs/Mod/Mod.bs", "bs");
    write_file("$inc/Hy/Brid.pm", "package Hy::Brid; 1;\n");
    write_file("$inc/Probe/Found.pm", "package Probe::Found; 1;\n");
    write_file("$out/Out/Side.pm", "package Out::Side; 1;\n");
    my $helper = write_file("$T/sel/helper/PAX/Helper.pm", "package PAX::Helper; 1;\n");
    local @INC = ($inc);
    no warnings 'redefine';
    local *PAX::StandaloneImage::_pax_runtime_helper_module_files = sub { return ($helper) };
    local *PAX::StandaloneImage::_pax_runtime_helper_modules = sub { return ( 'Selfam::Dep', 'Absent::One' ) };
    my @probe_args;
    local *PAX::StandaloneImage::_probe_loaded_runtime_files = sub { @probe_args = @_; return ("$inc/Probe/Found.pm") };

    my $deps = [
        { class => 'bundled_pure_perl', module => 'Selfam::Dep', source_path => "$inc/Selfam/Dep.pm" },
        { class => 'bundled_xs', module => 'Xs::Mod', source_path => "$inc/Xs/Mod.pm" },
        { class => 'bundled_xs', module => 'Xs::Gone', source_path => "$inc/Xs/Gone.pm" },
        { class => 'bundled_xs', module => 'Out::Side', source_path => "$out/Out/Side.pm" },
        { class => 'bundled_xs' },
        { class => 'bundled_xs', module => 'No::Source' },
        { module => '' },
        {},
        { class => 'compiled_dependency', packaging => 'hybrid_compiled_pcu_v1', module => 'Hy::Brid', source_path => "$inc/Hy/Brid.pm" },
        { class => 'compiled_dependency', packaging => 'hybrid_compiled_pcu_v1', module => 'Hy::NoSource' },
        { class => 'compiled_dependency', packaging => 'other', module => 'Co::Mp', source_path => "$inc/Co/Mp.pm" },
        { class => 'compiled_dependency', module => 'Co::NoPackaging', source_path => "$inc/Co/No.pm" },
    ];
    my @files = PAX::StandaloneImage::_runtime_selected_files(
        dependencies => $deps,
        lib_dirs => ["$T/sel/libs"],
        inc_dirs => [$inc],
        exclude_files => [ "$inc/Selfam/Dep.pm", "$inc/Hy/Brid.pm", '/nonexistent/aa/bb/x.pm' ],
    );
    is_deeply([ rel_list($T, @files) ],
        [ rel_list($T, "$inc/Selfam/data.txt", "$inc/Hy/Brid.pm", "$inc/Xs/Mod.pm", "$inc/auto/Xs/Mod/Mod.bs", "$inc/auto/Xs/Mod/Mod.so", "$inc/Probe/Found.pm", "$out/Out/Side.pm", $helper) ],
        'selected files honour exclusions, force lists and xs siblings');
    ok((grep { $_ eq 'Hy::Brid' } @{ $probe_args[1] }), 'hybrid dependency module is probed');
    ok(!(grep { $_ eq 'Co::Mp' } @{ $probe_args[1] }), 'other compiled dependency is not probed');
    is_deeply($probe_args[3], ["$T/sel/libs"], 'lib dirs passed to the probe');

    # Minimal call with defaults
    my @min = PAX::StandaloneImage::_runtime_selected_files();
    is_deeply([ rel_list($T, @min) ], [ rel_list($T, "$inc/Selfam/data.txt", "$inc/Selfam/Dep.pm", "$inc/Probe/Found.pm", $helper) ], 'defaults select helper modules only');

    my @no_inc = PAX::StandaloneImage::_runtime_selected_files(dependencies => [ { class => 'bundled_xs', module => 'Xs::Mod', source_path => "$inc/Xs/Mod.pm" } ]);
    ok((grep { $_ eq "$inc/Xs/Mod.pm" } @no_inc), 'xs dependency without inc dirs keeps its own source');
    ok(!(grep { m{Mod\.so\z} } @no_inc), 'no related xs files without inc dirs');

    # No modules at all
    local *PAX::StandaloneImage::_pax_runtime_helper_modules = sub { return () };
    is_deeply([ PAX::StandaloneImage::_runtime_selected_files() ], [], 'no modules, no files');
}

# ---- _runtime_manifest
write_file("$T/m/perl-fake", "#!/bin/sh\nexit 0\n", 0755);
{
    my $core = "$T/m/lib/perl5/5.38.0";
    my $arch = "$core/x86_64-linux-gnu";
    my $site = "$T/m/lib/site_perl/5.38.0";
    my $vend = "$T/m/share/perl5";
    my $outside = "$T/m/outside";
    for my $root ($core, $site, $vend) {
        write_file("$root/Manfam/Dep.pm", "package Manfam::Dep; 1; # $root\n");
    }
    write_file("$core/XSLoader.pm", "package XSLoader; 1;\n");
    write_file("$core/Manfam/Dep.txt", "not code\n");
    write_file("$core/CORE/libperl.so", "fake core lib\n");
    write_file("$arch/Arch/Only.pm", "package Arch::Only; 1;\n");
    write_file("$arch/auto/Manfam/Dep/Dep.so", "fake so\n");
    write_file("$site/Site/Only.pm", "package Site::Only; 1;\n");
    write_file("$vend/Vend/Only.pm", "package Vend::Only; 1;\n");
    write_file("$outside/Outm/Side.pm", "package Outm::Side; 1;\n");
    write_file("$outside/Hym/Brid.pm", "package Hym::Brid; 1;\n");
    my $skip_dir = "$T/m/skipped";
    make_path($skip_dir);
    my $deps = [
        { class => 'bundled_pure_perl', module => 'Manfam::Dep', source_path => "$core/Manfam/Dep.pm" },
        { class => 'bundled_xs', module => 'Outm::Side', source_path => "$outside/Outm/Side.pm" },
        { class => 'compiled_dependency', packaging => 'hybrid_compiled_pcu_v1', module => 'Hym::Brid', source_path => "$outside/Hym/Brid.pm" },
        { class => 'compiled_dependency', packaging => 'hybrid_compiled_pcu_v1', module => 'Hym::NoSource' },
        { class => 'compiled_dependency', module => 'Hym::NoPackaging', source_path => "$outside/Hym/Brid.pm" },
        { module => 'Hym::NoClass' },
    ];

    my $manifest;
    {
        local $^X = "$T/m/perl-fake";
        local @INC = (sub { return }, $core, $arch, $site, $vend, $skip_dir);
        $manifest = PAX::StandaloneImage::_runtime_manifest(
            dependencies => $deps,
            exclude_dirs => [$skip_dir],
            exclude_files => ["$core/Manfam/Dep.txt"],
            lib_dirs => [],
            app_namespace => 'My::App',
            app_legacy_namespace => 'PAX',
        );
    }
    is($manifest->{perl_binary}, rp("$T/m/perl-fake"), 'fake perl binary used');
    is($manifest->{perl_binary_logical_path}, 'bin/perl', 'bundled perl logical path');
    my @logical = map { $_->{logical_path} } @{ $manifest->{payloads} };
    ok((grep { $_ eq 'bin/perl' } @logical), 'perl binary payload');
    ok((grep { m{\Alib/libperl\.so\z} } @logical), 'core libperl copied as runtime lib');
    ok((grep { m{\Ainc/\d+/PAX/StandaloneRuntime\.pm\z} } @logical), 'runtime helper payload present');
    my %by_logical = map { $_->{logical_path} => $_ } @{ $manifest->{payloads} };
    my ($helper_rt) = grep { m{PAX/StandaloneRuntime\.pm\z} } @logical;
    ok($by_logical{$helper_rt}{bytes} !~ /__PAX_RUNTIME_LEGACY_NAMESPACE__/, 'runtime helper namespace marker replaced');
    ok($by_logical{$helper_rt}{bytes} =~ /My::App::JSON::json_decode/, 'runtime helper uses the app namespace');
    my @fake_dep = grep { m{\Ainc/\d+/Manfam/Dep\.pm\z} } @logical;
    is(scalar(@fake_dep), 1, 'same module in several roots is shipped once');
    ok((grep { m{/Site/Only\.pm\z} } @logical), 'site tree shipped');
    ok((grep { m{/Vend/Only\.pm\z} } @logical), 'vendor tree shipped');
    ok((grep { m{/Arch/Only\.pm\z} } @logical), 'arch tree shipped');
    ok((grep { m{/Outm/Side\.pm\z} } @logical) ? 0 : 1, 'selected files outside every inc root are skipped');
    ok(scalar(@{ $manifest->{bundled_inc_roots} }) >= 4, 'several inc roots recorded');
    like($manifest->{runtime_hash}, qr/\A[0-9a-f]{64}\z/, 'runtime hash is sha256');

    # no module is selected: whole inc trees are shipped
    my $empty_inc = "$T/m/empty/inc";
    write_file("$empty_inc/Lonely/Mod.pm", "package Lonely::Mod; 1;\n");
    write_file("$empty_inc/Lonely/skip.txt", "skip me\n");
    my $m2;
    {
        local $^X = "$T/m/perl-fake";
        local @INC = ($empty_inc);
        $m2 = PAX::StandaloneImage::_runtime_manifest(exclude_files => ["$empty_inc/Lonely/skip.txt"], mode => 'bundled_perl');
    }
    my @l2 = map { $_->{logical_path} } @{ $m2->{payloads} };
    ok((grep { m{\Ainc/\d+/Lonely/Mod\.pm\z} } @l2), 'whole tree shipped when nothing was selected');
    ok(!(grep { m{skip\.txt\z} } @l2), 'excluded file not shipped');

    # a perl path that does not resolve and helper files that do not exist
    {
        no warnings 'redefine';
        local *PAX::StandaloneImage::_pax_runtime_helper_module_files = sub { return ('/nonexistent/aa/bb/Helper.pm') };
        local $^X = '/nonexistent/aa/bb/perl';
        local @INC = ($empty_inc);
        my $m4 = PAX::StandaloneImage::_runtime_manifest();
        is($m4->{perl_binary}, '/nonexistent/aa/bb/perl', 'unresolvable perl path is kept as given');
        ok((grep { $_->{logical_path} eq 'bin/perl' && $_->{size} == 0 } @{ $m4->{payloads} }), 'unreadable perl becomes an empty payload');
    }

    # host perl mode ships helpers only
    my $m3 = PAX::StandaloneImage::_runtime_manifest(mode => 'host_perl', dependencies => $deps);
    ok(!defined $m3->{perl_binary}, 'host mode has no perl binary');
    ok(!defined $m3->{perl_binary_logical_path}, 'host mode has no perl logical path');
    ok(!(grep { $_->{logical_path} eq 'bin/perl' } @{ $m3->{payloads} }), 'host mode ships no perl');
    ok((grep { $_->{logical_path} =~ m{PAX/StandaloneRuntime\.pm\z} } @{ $m3->{payloads} }), 'host mode ships the runtime helper');
}

done_testing;
