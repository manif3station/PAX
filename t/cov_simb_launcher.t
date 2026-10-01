use strict;
use warnings;

# Wraps the global chdir builtin before PAX::StandaloneImage compiles so a test can
# make the Nth chdir fail while armed; when disarmed every chdir is passed through.
our ($CHDIR_ARMED, $CHDIR_CALLS, $CHDIR_FAIL_ON);
BEGIN {
    *CORE::GLOBAL::chdir = sub (;$) {
        if ($CHDIR_ARMED) {
            $CHDIR_CALLS++;
            if ($CHDIR_CALLS == $CHDIR_FAIL_ON) {
                $! = 2;
                return 0;
            }
        }
        return @_ ? CORE::chdir($_[0]) : CORE::chdir();
    };
}

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

t/cov_simb_launcher.t - coverage for launcher generation and dependency unit scanning

=head1 DESCRIPTION

Exercises _compile_launcher with fake cc/objcopy shell scripts so every failure
branch is reached without a real C build, checks the generated launcher C source for
manifest-dependent fragments, and drives _pure_perl_dependency_units with a stub compiler.

=head1 WHY IT EXISTS

The launcher build and the dependency scan are the slowest and most failure-prone
steps of a build; their error branches are otherwise never run by the suite.

=cut

my $T = tempdir('pax-cov-simb-launch-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $S = 'PAX::StandaloneImage';
my $START_CWD = Cwd::getcwd();

# write_file($path, $text, $mode)
# Writes a fixture file (optionally chmod-ed), creating parent directories first.
# Input: path, text and optional mode. Output: the path.
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

# ---- fake toolchain
my $fake_objcopy = write_file("$T/bin/objcopy", <<'SH', 0755);
#!/bin/sh
for a; do last=$a; done
if [ "$last" = "$FAIL_OBJ" ]; then exit 1; fi
exit 0
SH
my $fake_cc = write_file("$T/bin/cc", <<'SH', 0755);
#!/bin/sh
case "$FAKE_CC_MODE" in
  fail) exit 1 ;;
  nofile) exit 0 ;;
esac
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then out=$2; fi
  shift
done
echo '#!/bin/sh' > "$out"
chmod 755 "$out"
exit 0
SH

# manifest(output)
# Builds a minimal manifest accepted by _compile_launcher and _launcher_source.
# Input: output path. Output: manifest hash reference.
sub manifest {
    my ($out) = @_;
    return {
        output_path => $out,
        code_units => [ { logical_path => 'e.pl', size => 1, bytes => 'x' } ],
        runtime_payloads => [],
        assets => [],
        entrypoint => { logical_path => 'e.pl' },
    };
}

# with_tools(cc, objcopy, code)
# Runs code with PAX::StandaloneImage::_which answering from the given tool paths.
# Input: cc path (or undef), objcopy path (or undef), code ref. Output: code's result.
sub with_tools {
    my ($cc, $objcopy, $code, %extra) = @_;
    no warnings 'redefine';
    local *PAX::StandaloneImage::_which = sub {
        my ($p) = @_;
        return $cc if $p eq 'cc';
        return $extra{gcc} if $p eq 'gcc';
        return $objcopy if $p eq 'objcopy';
        return;
    };
    return $code->();
}

# ---- successful build, parent creation, native payload default
{
    local $ENV{FAKE_CC_MODE} = 'ok';
    local $ENV{FAIL_OBJ} = '';
    my $out = "$T/ok/new/dir/launcher";
    my $r = with_tools($fake_cc, $fake_objcopy, sub { PAX::StandaloneImage::_compile_launcher(manifest($out)) });
    is_deeply($r, { status => 'built' }, 'fake toolchain builds the launcher');
    ok(-d "$T/ok/new/dir/.pax-launcher-build", 'build dir created');
    ok(-f "$T/ok/new/dir/launcher.c", 'launcher source written');
    my $m = manifest($out);
    $m->{native_payloads} = [ { logical_path => 'native/x', size => 1, bytes => 'n' } ];
    $r = with_tools($fake_cc, $fake_objcopy, sub { PAX::StandaloneImage::_compile_launcher($m) });
    is_deeply($r, { status => 'built' }, 'rebuild into an existing directory with native payloads');
    my $pkg = do { open my $fh, '<:raw', "$T/ok/new/dir/.pax-launcher-build/native.pkg" or die; local $/; <$fh> };
    like($pkg, qr/\APAXP\n1\nnative\/x\t1\n\nn\z/, 'native package written');

    # gcc is used when cc is absent
    $r = with_tools(undef, $fake_objcopy, sub { PAX::StandaloneImage::_compile_launcher(manifest($out)) }, gcc => $fake_cc);
    is_deeply($r, { status => 'built' }, 'gcc fallback is used');
}

# ---- failures
{
    my $out = "$T/fail/launcher";
    make_path("$T/fail/launcher.c");
    my $r = with_tools($fake_cc, $fake_objcopy, sub { PAX::StandaloneImage::_compile_launcher(manifest($out)) });
    like($r->{reason}, qr/cannot write launcher source/, 'unwritable launcher source is reported');
    is($r->{status}, 'not_built', 'status not_built');

    $out = "$T/fail2/launcher";
    $r = with_tools(undef, $fake_objcopy, sub { PAX::StandaloneImage::_compile_launcher(manifest($out)) });
    is($r->{reason}, 'no C compiler available', 'no cc and no gcc');
    $r = with_tools($fake_cc, undef, sub { PAX::StandaloneImage::_compile_launcher(manifest($out)) });
    is($r->{reason}, 'no objcopy available', 'no objcopy');

    for my $obj (qw(code.pkg.o runtime.pkg.o assets.pkg.o native.pkg.o)) {
        local $ENV{FAIL_OBJ} = $obj;
        local $ENV{FAKE_CC_MODE} = 'ok';
        (my $name = $obj) =~ s/\.o\z//;
        $r = with_tools($fake_cc, $fake_objcopy, sub { PAX::StandaloneImage::_compile_launcher(manifest($out)) });
        is($r->{status}, 'not_built', "objcopy failure for $name is not_built");
        like($r->{reason}, qr/\Aobjcopy \Q$name\E failed at /, "objcopy failure for $name keeps its die reason");
    }

    local $ENV{FAIL_OBJ} = '';
    {
        local $ENV{FAKE_CC_MODE} = 'fail';
        $r = with_tools($fake_cc, $fake_objcopy, sub { PAX::StandaloneImage::_compile_launcher(manifest($out)) });
        is($r->{status}, 'not_built', 'compiler failure is not_built');
        like($r->{reason}, qr/\Alauncher compile failed at /, 'compiler failure keeps its die reason');
    }
    {
        local $ENV{FAKE_CC_MODE} = 'nofile';
        unlink $out;
        $r = with_tools($fake_cc, $fake_objcopy, sub { PAX::StandaloneImage::_compile_launcher(manifest($out)) });
        is_deeply($r, { status => 'not_built', reason => 'standalone launcher compile failed' }, 'compiler that produces nothing');
    }
    {
        local $ENV{FAKE_CC_MODE} = 'ok';
        local ($CHDIR_ARMED, $CHDIR_CALLS, $CHDIR_FAIL_ON) = (1, 0, 1);
        $r = with_tools($fake_cc, $fake_objcopy, sub { PAX::StandaloneImage::_compile_launcher(manifest($out)) });
        is($r->{status}, 'not_built', 'chdir into build dir failure is not_built');
        like($r->{reason}, qr/\Acannot chdir to \S+\.pax-launcher-build: /, 'chdir failure keeps its die reason');
    }
    {
        local $ENV{FAKE_CC_MODE} = 'ok';
        {
            local ($CHDIR_ARMED, $CHDIR_CALLS, $CHDIR_FAIL_ON) = (1, 0, 2);
            $r = with_tools($fake_cc, $fake_objcopy, sub { PAX::StandaloneImage::_compile_launcher(manifest($out)) });
        }
        CORE::chdir($START_CWD);
        like($r->{reason}, qr/cannot restore cwd/, 'chdir back failure');
    }
}

# ---- _launcher_source
{
    my $min = PAX::StandaloneImage::_launcher_source({ entrypoint => { logical_path => 'e.pl' }, code_units => [] });
    like($min, qr/pax_runtime_inc_roots_count = 0;/, 'no inc roots');
    like($min, qr/pax_code_lib_roots_count = 0;/, 'no lib roots');
    like($min, qr/if \(0 && write_package_root/, 'no native package');
    like($min, qr/strcmp\("host_perl", "bundled_perl"\)/, 'default runtime mode');
    like($min, qr/strlen\(""\) > 0\)/, 'no fast version');

    my $m = manifest('/x');
    $m->{source_hash} = 'abc123';
    $m->{native_payloads} = [ { logical_path => 'n', size => 1, bytes => 'b' } ];
    $m->{runtime} = { mode => 'bundled_perl', perl_binary_logical_path => 'bin/perl', bundled_inc_roots => ['inc/000'] };
    $m->{lib_dirs} = ['lib/a'];
    $m->{code_units}[0]{bytes} = JSON::PP::encode_json({ version => '4.5' });
    $m->{code_units}[0]{source_bytes} = 'SECRETSOURCE';
    my $src = PAX::StandaloneImage::_launcher_source($m);
    like($src, qr/"abc123"/, 'source hash embedded');
    like($src, qr/if \(1 && write_package_root/, 'native package present');
    like($src, qr/strlen\("4.5"\) > 0/, 'fast version embedded');
    like($src, qr/"bin\/perl"/, 'perl logical path');
    like($src, qr/"inc\/000",/, 'inc root listed');
    like($src, qr/"lib\/a",/, 'lib root listed');
    like($src, qr/SECRETSOURCE/, 'inspect manifest keeps the source snapshot');
    is(scalar(() = $src =~ /SECRETSOURCE/g), 1, 'per-launch manifest drops the source snapshot');
}

# ---- _pure_perl_dependency_units
{
    package CovSimbCompiler;
    # new()
    # Builds the stub compiler.
    # Input: none. Output: object.
    sub new { return bless { calls => [] }, shift }
    # compile(%args)
    # Returns a canned compile result chosen by the module's file name.
    # Input: path/kind/logical_path. Output: result hash reference.
    sub compile {
        my ($self, %a) = @_;
        push @{ $self->{calls} }, $a{logical_path};
        my ($name) = $a{path} =~ m{/(\w+)\.pm\z};
        my %by = (
            Plain => {},
            Fallback => { packaging => 'source_payload_fallback' },
            HybridBad => { packaging => 'hybrid_compiled_pcu_v1', bytes => 'not json' },
            HybridArray => { packaging => 'hybrid_compiled_pcu_v1', bytes => '[1]' },
            HybridNoSubs => { packaging => 'hybrid_compiled_pcu_v1', bytes => '{}' },
            HybridEmptySubs => { packaging => 'hybrid_compiled_pcu_v1', bytes => '{"subs":[]}' },
            HybridSubs => { packaging => 'hybrid_compiled_pcu_v1', bytes => '{"subs":[{"name":"f"}]}' },
        );
        return { %{ $by{$name} || {} }, logical_path => $a{logical_path}, name => $name };
    }
}
{
    my $root = "$T/dep/root";
    for my $m (qw(Plain Fallback HybridBad HybridArray HybridNoSubs HybridEmptySubs HybridSubs SeenPath SeenModule)) {
        write_file("$root/$m.pm", "package $m; 1;\n");
    }
    write_file("$root/RuntimeOnly.pm", "package RuntimeOnly; use Exporter; 1;\n");
    my $unit = write_file("$T/dep/unit.pl", join('', map { "use $_;\n" } qw(strict Plain Missing RuntimeOnly Fallback HybridBad HybridArray HybridNoSubs HybridEmptySubs HybridSubs SeenPath SeenModule)));
    my $compiler = CovSimbCompiler->new;
    my %seen = ( abs_path_of("$root/SeenPath.pm") => 1 );
    my %seen_modules = ( SeenModule => 1 );
    my @units = PAX::StandaloneImage::_pure_perl_dependency_units({ source_path => $unit }, \%seen, \%seen_modules, $compiler, [$root]);
    is_deeply([ map { $_->{name} } @units ], [qw(Plain HybridBad HybridArray HybridSubs)], 'only units worth shipping are kept');
    is($units[0]{logical_path}, 'dependency/Plain.pm', 'logical path of dependency');
    ok($seen_modules{HybridSubs} && $seen_modules{Plain}, 'kept modules are recorded');
    ok(!$seen_modules{Fallback}, 'fallback module is not recorded');

    # A repeated module in the declared list is only compiled once.
    {
        no warnings 'redefine';
        local *PAX::StandaloneImage::_declared_modules = sub { return qw(Plain Plain) };
        my $c2 = CovSimbCompiler->new;
        my @u = PAX::StandaloneImage::_pure_perl_dependency_units({ source_path => $unit }, {}, {}, $c2, [$root]);
        is(scalar @u, 1, 'duplicate declaration yields one unit');
        is(scalar @{ $c2->{calls} }, 1, 'compiled once');
    }
}

# abs_path_of($path)
# Resolves a path the way the module under test does.
# Input: path. Output: absolute path.
sub abs_path_of { return Cwd::abs_path($_[0]) }

done_testing;
