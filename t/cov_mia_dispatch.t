use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneDispatch;

=pod

=head1 NAME

t/cov_mia_dispatch.t - coverage tests for PAX::StandaloneDispatch

=head1 DESCRIPTION

Runs C<run_i64> against fabricated standalone images whose "binary" is a shell
script that extracts a prepared payload (fake native executable, fake bundled
perl, stub runtime module), covering native, guard-deopt, native-failure and
fallback paths.

=head1 WHY IT EXISTS

The dispatcher shells out to the packaged binary and bundled perl; stand-in
scripts keep every branch testable in-process and hermetic.

=cut

my $tmp = tempdir('pax-cov-mia-dispatch-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($path, $text, $mode)
# Writes a fixture file (creating parents) and applies the given mode.
# Input: path, text, mode. Output: path.
sub write_file {
    my ($path, $text, $mode) = @_;
    my ($dir) = $path =~ m{\A(.*)/[^/]+\z};
    make_path($dir) if defined $dir && !-d $dir;
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    chmod $mode, $path;
    return $path;
}

my $counter = 0;

# make_image(%opts)
# Builds a fake image: a payload dir, a stand-in "binary" that copies the
# payload into the extraction dir, and the image hash describing it.
# Input: native_body, perl_body, mode, extract_exit. Output: image hash.
sub make_image {
    my (%o) = @_;
    my $id = ++$counter;
    my $payload = "$tmp/payload$id";
    make_path($payload);
    write_file("$payload/native/add", $o{native_body} // "#!/bin/sh\necho \$((\$1 + \$2))\n", 0644);
    write_file("$payload/runtime/bin/perl", $o{perl_body} // "#!/bin/sh\necho 42\n", 0644);
    write_file("$payload/code/bin/main.pl", "1;\n", 0644);
    my $binary = "$tmp/binary$id";
    my $exit = $o{extract_exit} // 0;
    write_file($binary, "#!/bin/sh\n"
        . "if [ \"\$1\" = \"--pax-standalone-extract\" ]; then\n"
        . "  if [ $exit -ne 0 ]; then echo 'extract exploded' >&2; exit $exit; fi\n"
        . "  /bin/mkdir -p \"\$2\" && /bin/cp -R '$payload'/. \"\$2\"/ || exit 9\n"
        . "  exit 0\n"
        . "fi\nexit 5\n", 0755);
    make_path("$tmp/standalone$id");
    return {
        output_path => $binary,
        standalone_dir => "$tmp/standalone$id",
        entrypoint => { logical_path => 'bin/main.pl' },
        runtime_epochs => { package_symbols => 1, method_resolution => 1, loaded_modules => 1 },
        runtime => { mode => 'bundled_perl', perl_binary_logical_path => 'bin/perl' },
        native_dispatch => [ {
            region_id => 'r1',
            region_name => 'main::add',
            executable_logical_path => 'native/add',
            guards => [ { id => 'g1', invalidation_key => 'package_symbols' } ],
            deopt => { safepoint => 'r1:entry' },
        } ],
        lib_dirs => [],
    };
}

# --- construction with defaults and explicit collaborators
{
    my $d = PAX::StandaloneDispatch->new;
    isa_ok($d->{image_store}, 'PAX::StandaloneImage');
    isa_ok($d->{native_runner}, 'PAX::NativeRunner');
    my $d2 = PAX::StandaloneDispatch->new(image_store => 'S', native_runner => 'N');
    is_deeply([ @{$d2}{qw(image_store native_runner)} ], [ 'S', 'N' ], 'explicit collaborators are kept');
}

my $d = PAX::StandaloneDispatch->new;

# --- argument validation and image loading
eval { $d->run_i64(region_name => 'add') };
like($@, qr/name required/, 'run_i64 needs an image or a name');
eval { $d->run_i64(image => make_image()) };
like($@, qr/region_name required/, 'run_i64 needs a region name');
{
    my $img = make_image();
    my $loaded;
    my $store = bless {}, 'Cov::Mia::Store';
    no warnings 'once';
    local *Cov::Mia::Store::load = sub { my ($s, %a) = @_; $loaded = $a{name}; return $img };
    my $dd = PAX::StandaloneDispatch->new(image_store => $store);
    my $r = $dd->run_i64(name => 'stored', region_name => 'add', left => 2, right => 3);
    is($loaded, 'stored', 'image loaded through the image store by name');
    is($r->{status}, 'native', 'loaded image dispatches natively');
}

# --- native path (non-executable payload bits restored by the dispatcher)
{
    my $r = $d->run_i64(image => make_image(), region_name => 'add', left => 2, right => 3);
    is($r->{status}, 'native', 'native dispatch succeeded');
    is($r->{execution_model}, 'standalone_packaged_native', 'native execution model');
    is($r->{result}{value}, 5, 'native result computed');
    is($r->{region_name}, 'main::add', 'region name reported');
    is($r->{guard}{status}, 'native_allowed', 'guards allowed native execution');

    my $q = $d->run_i64(image => make_image(), region_name => 'main::add', left => 4, right => 5);
    is($q->{result}{value}, 9, 'fully qualified region names resolve; arguments honoured');

    my $z = $d->run_i64(image => make_image(), region_name => 'add');
    is($z->{result}{value}, 0, 'missing operands default to zero');
}

# --- region lookup misses
{
    my $img = make_image();
    $img->{native_dispatch} = [ { region_id => 'x' }, { region_name => 'other' } ];
    my $r = $d->run_i64(image => $img, region_name => 'add');
    is($r->{status}, 'fallback', 'unknown region falls back');
    is($r->{execution_model}, 'standalone_region_missing', 'missing region model');
    like($r->{reason}, qr/requested region not found: add/, 'reason names the region');
    delete $img->{native_dispatch};
    is($d->run_i64(image => $img, region_name => 'add')->{status}, 'fallback', 'image without native_dispatch falls back');
}

# --- guard failure -> deopt through bundled perl
{
    my $r = $d->run_i64(image => make_image(), region_name => 'add', left => 1, right => 1, invalidate => ['package_symbols']);
    is($r->{status}, 'deopt', 'invalidated epoch deoptimises');
    is($r->{execution_model}, 'standalone_bundled_perl_fallback', 'deopt runs the perl fallback');
    is($r->{guard}{status}, 'deopt', 'guard result is deopt');
    is($r->{result}{status}, 'ok', 'fallback perl exited cleanly');
    is($r->{result}{value}, 42, 'fallback perl value parsed');
    is($r->{result}{reason}, 'perl_region_fallback', 'fallback reason');
    ok(ref $r->{deopt}, 'deopt frame present');
}

# --- native binary failing falls back; failing perl reports an error
{
    my $img = make_image(native_body => "#!/bin/sh\nexit 4\n", perl_body => "#!/bin/sh\necho 'not a number'\necho oops >&2\nexit 3\n");
    my $r = $d->run_i64(image => $img, region_name => 'add', left => 1, right => 2);
    is($r->{status}, 'fallback', 'failed native execution falls back');
    is($r->{result}{status}, 'error', 'failing perl is an error');
    is($r->{result}{exit}, 3, 'exit status captured');
    is($r->{result}{reason}, 'perl_region_execution_failed', 'failure reason');
    is($r->{result}{value}, undef, 'non-numeric output yields no value');
    like($r->{result}{stderr}, qr/oops/, 'stderr captured');
    is($r->{result}{stdout}, 'not a number', 'stdout captured with its trailing newline chomped');
    ok($r->{deopt}, 'a deopt frame is reconstructed for the fallback');
}

# --- region without a native executable skips native dispatch
{
    my $img = make_image();
    delete $img->{native_dispatch}[0]{executable_logical_path};
    delete $img->{native_dispatch}[0]{guards};
    delete $img->{native_dispatch}[0]{deopt};
    delete $img->{runtime_epochs};
    my $r = $d->run_i64(image => $img, region_name => 'add');
    is($r->{status}, 'fallback', 'no executable -> fallback');
    is($r->{result}{value}, 42, 'fallback result returned');
}

# --- host perl with a stub runtime module, lib roots, PERL5LIB and env plumbing
{
    my $img = make_image();
    my $id = $counter;
    write_file("$tmp/payload$id/code/lib/PAX/StandaloneRuntime.pm",
        "package PAX::StandaloneRuntime;\n"
      . "# run(\%args)\n# Stub runtime: defines main::add and records the environment.\n"
      . "sub run { my (\$c, \%a) = \@_; no strict 'refs'; *{'main::add'} = sub { return \$_[0] + \$_[1] + length(\$ENV{PAX_EMBEDDED_ASSET_ROOT}) * 0 + (\$ENV{PAX_STANDALONE_TMPDIR} ? 100 : 0) }; return 0; }\n1;\n", 0644);
    $img->{runtime} = { mode => 'host_perl', bundled_inc_roots => ['rt/lib'] };
    $img->{lib_dirs} = ['lib'];
    $img->{native_dispatch}[0]{executable_logical_path} = 'native/missing';
    my $r = $d->run_i64(image => $img, region_name => 'add', left => 2, right => 3);
    is($r->{status}, 'fallback', 'host perl fallback after missing native executable');
    is($r->{result}{status}, 'ok', 'host perl ran the stub runtime');
    is($r->{result}{value}, 105, 'region sub ran with PERL5LIB and standalone env set');
}

# --- extraction failure
{
    my $img = make_image(extract_exit => 7);
    eval { $d->run_i64(image => $img, region_name => 'add') };
    like($@, qr/standalone extraction failed for .*extract exploded/s, 'extraction failure is fatal and carries stderr');
}

# --- helper edge cases
{
    my $paths = PAX::StandaloneDispatch::_runtime_paths(
        { entrypoint => { logical_path => 'a/b.pl' }, standalone_dir => '/s', runtime => {} }, '/x');
    is($paths->{perl_exec}, 'perl', 'host perl is used without a bundled runtime');
    is($paths->{perl5lib}, '', 'no lib roots -> empty PERL5LIB');
    is($paths->{entrypoint}, '/x/code/a/b.pl', 'entrypoint path under the code root');

    my $bundled = PAX::StandaloneDispatch::_runtime_paths(
        { entrypoint => { logical_path => 'a/b.pl' }, standalone_dir => '/s', runtime => { mode => 'bundled_perl' }, lib_dirs => ['l'] }, '/x');
    is($bundled->{perl_exec}, '/x/runtime/bin/perl', 'bundled perl defaults to bin/perl');
    is($bundled->{perl5lib}, '/x/code/l', 'lib dirs rooted under the code dir');

    # no executable for a bundled perl that does not exist: chmod is skipped quietly
    PAX::StandaloneDispatch::_restore_executable_bits(
        { runtime => { mode => 'bundled_perl' }, native_dispatch => [ { executable_logical_path => 'n/x' }, { } ] },
        { perl_exec => "$tmp/no-such-perl", extract_dir => $tmp },
    );
    pass('_restore_executable_bits tolerates missing files');
}

# --- stubbed collaborators for the defensive fallbacks
{
    no warnings qw(redefine once);
    {
        local *PAX::StandaloneImage::new = sub { return 0 };
        local *PAX::NativeRunner::new = sub { return 0 };
        my $odd = PAX::StandaloneDispatch->new;
        is_deeply([ @{$odd}{qw(image_store native_runner)} ], [ 0, 0 ], 'constructor keeps falsy default collaborators');
    }

    my $store = bless {}, 'Cov::Mia::EmptyStore';
    local *Cov::Mia::EmptyStore::load = sub { return undef };
    my $dd = PAX::StandaloneDispatch->new(image_store => $store);
    is($dd->run_i64(name => 'ghost', region_name => 'add')->{execution_model}, 'standalone_region_missing', 'a store returning nothing yields a missing-region fallback');

    my $runner = bless {}, 'Cov::Mia::Runner';
    local *Cov::Mia::Runner::run_i64_binary = sub { return {} };
    my $d3 = PAX::StandaloneDispatch->new(native_runner => $runner);
    my $r = $d3->run_i64(image => make_image(), region_name => 'add', left => 1, right => 1);
    is($r->{status}, 'fallback', 'runner result without a status counts as a native failure');

    local *PAX::StandaloneDispatch::_run_perl_region = sub { return {} };
    my $r2 = $d3->run_i64(image => make_image(), region_name => 'add', left => 1, right => 1);
    is($r2->{status}, 'fallback', 'fallback without a reason still reconstructs a frame');
    is_deeply($r2->{result}, {}, 'stubbed fallback result returned');
}

# --- unreadable pipes: readline fails (stubbed open3 hands back directory handles)
{
    no warnings 'redefine';
    require POSIX;
    local *PAX::StandaloneDispatch::open3 = sub {
        open $_[0], '<', '/dev/null' or die "cannot open /dev/null: $!";
        open $_[1], '<', $tmp or die "cannot open dir handle: $!";
        open $_[2], '<', $tmp or die "cannot open dir handle: $!";
        my $pid = fork();
        POSIX::_exit(0) if defined $pid && $pid == 0;
        return $pid;
    };
    my $img = make_image();
    my $r = $d->run_i64(image => $img, region_name => 'add', invalidate => ['package_symbols']);
    is($r->{result}{stdout}, '', 'unreadable stdout becomes empty');
    is($r->{result}{stderr}, '', 'unreadable stderr becomes empty');
    is($r->{result}{status}, 'ok', 'clean exit still reported');
}

# --- _run_perl_region without a PERL5LIB value, and helper edge cases
{
    my $img = make_image();
    my $extract = "$tmp/extract-direct";
    make_path($extract);
    write_file("$extract/perl", "#!/bin/sh\necho 7\n", 0755);
    my $r = PAX::StandaloneDispatch::_run_perl_region(
        paths => { perl_exec => "$extract/perl", entrypoint => 'e.pl', assets_root => $extract, manifest_path => "$extract/m", extract_dir => $extract },
        region => { region_name => 'add' }, left => 1, right => 2,
    );
    is($r->{value}, 7, 'undefined PERL5LIB leaves the environment alone');

    PAX::StandaloneDispatch::_restore_executable_bits({ runtime => {} }, { perl_exec => "$extract/perl", extract_dir => $extract });
    pass('_restore_executable_bits tolerates an image with no runtime mode or native regions');
}

done_testing;
