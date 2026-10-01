use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::NativeRunner;
use PAX::Tier1;
use PAX::Backend::Tier2LLVM;

=pod

=head1 NAME

t/cov_mib_native.t - coverage tests for the native runner and the Tier 1 / Tier 2 backends

=head1 WHY IT EXISTS

PAX::NativeRunner, PAX::Tier1 and PAX::Backend::Tier2LLVM contain error paths
(missing compiler, failing compiler, unwritable output) that normal builds never
reach. This file drives them with fake compilers and stubbed hash functions so
that every branch and condition is exercised hermetically.

=head1 DESCRIPTION

Fake C compilers are small shell scripts written into a temporary directory and
selected through C<$ENV{CC}>. The hash function used to name artifacts is
overridden locally so an unwritable artifact path can be pre-created as a
directory.

=cut

my $root = tempdir('pax-cov-mib-native-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_exec($name, $text)
# Writes an executable helper script into the temp root.
# Input: file name and script text. Output: absolute script path.
sub write_exec {
    my ($name, $text) = @_;
    my $path = File::Spec->catfile($root, $name);
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    chmod 0755, $path;
    return $path;
}

# --- PAX::NativeRunner ------------------------------------------------------
{
    my $runner = PAX::NativeRunner->new;
    like($runner->run_i64_binary->{reason}, qr/missing or not executable/, 'undef path is an error');
    my $plain = File::Spec->catfile($root, 'plain.txt');
    open my $fh, '>', $plain or die $!;
    close $fh;
    is($runner->run_i64_binary(path => $plain)->{status}, 'error', 'non-executable path is an error');

    my $adder = write_exec('adder.sh', "#!/bin/sh\necho \$((\$1 + \$2))\n");
    my $ok = $runner->run_i64_binary(path => $adder, left => 4, right => 5);
    is($ok->{status}, 'ok', 'executable succeeds');
    is($ok->{value}, 9, 'value parsed from stdout');
    is($ok->{exit}, 0, 'exit status zero');
    my $defaults = $runner->run_i64_binary(path => $adder);
    is($defaults->{value}, 0, 'undefined operands default to zero');

    my $failing = write_exec('failing.sh', "#!/bin/sh\necho oops >&2\necho text\nexit 3\n");
    my $bad = $runner->run_i64_binary(path => $failing, left => 1, right => 2);
    is($bad->{status}, 'error', 'non-zero exit is an error');
    is($bad->{exit}, 3, 'exit code reported');
    is($bad->{stderr}, "oops\n", 'stderr captured');
    ok(!defined $bad->{value}, 'non-numeric stdout has no value');

    # Closed pipes read as undef and fall back to empty strings.
    no warnings 'redefine';
    local *PAX::NativeRunner::open3 = sub {
        my $pid = fork;
        die "fork failed: $!" if !defined $pid;
        if (!$pid) { exit 0 }
        for my $i (1, 2) {
            open my $closed, '<', \ 'x' or die $!;
            close $closed;
            $_[$i] = $closed;
        }
        open my $in, '>', File::Spec->devnull or die $!;
        $_[0] = $in;
        return $pid;
    };
    my $quiet = do { local $SIG{__WARN__} = sub { }; $runner->run_i64_binary(path => $adder) };
    is($quiet->{stdout}, '', 'closed stdout reads as empty');
    is($quiet->{stderr}, '', 'closed stderr reads as empty');
    is($quiet->{status}, 'ok', 'stubbed child exit is ok');
}

# --- PAX::Backend::Tier2LLVM ------------------------------------------------
{
    my $out = File::Spec->catdir($root, 'll');
    is(PAX::Backend::Tier2LLVM->new->{out_dir}, '.pax/native', 'Tier2 default out_dir');
    is(PAX::Backend::Tier2LLVM->new->{enabled}, 1, 'Tier2 enabled by default');
    my $off = PAX::Backend::Tier2LLVM->new(enabled => 0, out_dir => $out);
    my $on = PAX::Backend::Tier2LLVM->new(enabled => 'yes', out_dir => $out);
    is($off->metadata->{status}, 'disabled_by_configuration', 'disabled metadata');
    is($on->metadata->{status}, 'enabled', 'enabled metadata');
    is($off->emit_module({})->{status}, 'disabled', 'disabled emit');

    is($on->emit_module({ region_id => 'r' })->{status}, 'fallback', 'no shape falls back');
    is($on->module_for({})->{reason}, 'no LLVM lowering for this guarded SSA shape', 'fallback reason');

    {
        no warnings 'redefine';
        local *PAX::Backend::Tier2LLVM::module_for = sub { {} };
        is_deeply($on->emit_module({}), {}, 'module without status is returned unchanged');
    }

    my %ops = (add => 'add nsw', subtract => 'sub nsw', multiply => 'mul nsw', greater_than => 'icmp sgt', other => 'ret i64 0');
    for my $op (sort keys %ops) {
        my $m = $on->module_for({ region_id => 'a"b\\c', region_name => 'n"m\\x', native_shape => { kind => 'i64_binary_leaf', op => $op } });
        is($m->{status}, 'llvm_ir', "binary $op lowers");
        like($m->{ir}, qr/\Q$ops{$op}\E/, "binary $op body");
        like($m->{ir}, qr/region_id: a\\"b\\\\c/, 'region id escaped');
        like($m->{ir}, qr/region_name: n\\"m\\\\x/, 'region name escaped');
    }
    like($on->module_for({ source => { native_shape => { kind => 'i64_binary_leaf' } } })->{ir}, qr/ret i64 0/, 'missing op lowers to zero');
    like($on->module_for({ native_shape => { kind => 'i64_sum_loop' } })->{ir}, qr/done_sum/, 'sum loop');
    like($on->module_for({ native_shape => { kind => 'i64_masked_mix_accum_loop' } })->{ir}, qr/ashr/, 'masked mix loop');

    my $artifact = $on->emit_module({ region_id => 'x', region_name => 'y', native_shape => { kind => 'i64_sum_loop' } });
    is($artifact->{status}, 'llvm_ir_artifact', 'artifact emitted');
    ok(-f $artifact->{path}, 'artifact file exists');
    my $again = $on->emit_module({ native_shape => { kind => 'i64_sum_loop' } });
    is($again->{status}, 'llvm_ir_artifact', 'unnamed region emits');

    no warnings 'redefine';
    local *PAX::Backend::Tier2LLVM::sha256_hex = sub { 'fixedid' };
    make_path(File::Spec->catdir($out, 'fixedid.ll'));
    my $blocked = $on->emit_module({ native_shape => { kind => 'i64_sum_loop' } });
    is($blocked->{status}, 'fallback', 'unwritable module falls back');
    like($blocked->{reason}, qr/cannot write LLVM IR module/, 'unwritable reason');
}

# --- PAX::Tier1 -------------------------------------------------------------
{
    my $t1 = PAX::Tier1->new;
    is($t1->{backend}, 'portable-fallback', 'default backend');
    is($t1->{out_dir}, '.pax/native', 'default out_dir');
    my $custom = PAX::Tier1->new(backend => 'b', out_dir => 'o');
    is_deeply([@$custom{qw(backend out_dir)}], [qw(b o)], 'explicit backend and out_dir');

    # Compiler discovery.
    my $bindir = File::Spec->catdir($root, 'bin');
    make_path($bindir);
    my $fake_gcc = File::Spec->catfile($bindir, 'gcc');
    open my $gfh, '>', $fake_gcc or die $!;
    close $gfh;
    chmod 0755, $fake_gcc;
    {
        local $ENV{CC} = 'my-cc';
        is(PAX::Tier1::_cc(), 'my-cc', 'CC wins');
    }
    {
        local $ENV{CC} = '';
        local $ENV{PATH} = $bindir;
        is(PAX::Tier1::_cc(), $fake_gcc, 'gcc found when cc missing');
        is(PAX::Tier1::_native_backend_available(), 1, 'backend available with gcc');
    }
    {
        my $fake_cc = File::Spec->catfile($bindir, 'cc');
        open my $cfh, '>', $fake_cc or die $!;
        close $cfh;
        chmod 0755, $fake_cc;
        local $ENV{PATH} = "/nonexistent-pax-dir:$bindir";
        delete local $ENV{CC};
        is(PAX::Tier1::_cc(), $fake_cc, 'cc preferred over gcc');
        unlink $fake_cc;
    }
    {
        delete local $ENV{CC};
        delete local $ENV{PATH};
        ok(!PAX::Tier1::_cc(), 'no compiler without PATH');
        is(PAX::Tier1::_native_backend_available(), 0, 'backend unavailable without compiler');
        my $unit = { region_id => 'rid' };
        my $fallback = $t1->compile($unit);
        is($fallback->{status}, 'fallback_artifact', 'no toolchain falls back');
        is($fallback->{entry_kind}, 'interpreter_bridge', 'fallback entry kind');
        is($fallback->{region_id}, 'rid', 'fallback region id');
    }

    # C source selection.
    my $src = PAX::Tier1::_c_source_for_region({});
    is($src->{entry_kind}, 'native_probe_trampoline', 'unknown shape is a probe trampoline');
    like($src->{source}, qr/strlen\("unknown"\)/, 'unknown region id');
    is(PAX::Tier1::_c_source_for_region({ source => { native_shape => { kind => 'i64_sum_loop', op => 'sum' } } })->{entry_kind}, 'native_i64_loop', 'nested shape');
    like(PAX::Tier1::_c_translation_unit('a"b\\c', 'return 1;'), qr/strlen\("a\\"b\\\\c"\)/, 'region id escaped in C');
    is(PAX::Tier1::_c_binary_expr(), 'return 0;', 'undef op returns zero');
    is(PAX::Tier1::_c_binary_expr('bogus'), 'return 0;', 'unknown op returns zero');
    like(PAX::Tier1::_c_binary_expr($_->[0]), $_->[1], "C expr for $_->[0]") for
        ['add', qr/left \+ right/], ['subtract', qr/left - right/], ['multiply', qr/left \* right/], ['greater_than', qr/left > right/];

    my $have_cc = do { delete local $ENV{CC}; PAX::Tier1::_cc() };
    SKIP: {
        skip 'no C compiler available', 12 if !$have_cc;
        my $out = File::Spec->catdir($root, 'native');
        my $real = PAX::Tier1->new(out_dir => $out);

        my $leaf = $real->compile({ region_id => 'r1', region_name => 'main::add', native_shape => { kind => 'i64_binary_leaf', op => 'add', smoke_left => 2, smoke_right => 3, smoke_expected => 5 } });
        is($leaf->{status}, 'native_artifact', 'leaf compiled');
        is($leaf->{entry_kind}, 'native_i64_leaf', 'leaf kind');
        ok($leaf->{native_test}{passed}, 'leaf smoke test passed');
        ok(-x $leaf->{executable_path}, 'leaf executable exists');
        is($leaf->{tier2_artifact}{status}, 'llvm_ir_artifact', 'tier2 artifact attached');

        my $defaulted = $real->compile({ region_id => 'r2', native_shape => { kind => 'i64_binary_leaf', op => 'add' } });
        is($defaulted->{native_test}{expected}, '5', 'smoke defaults used');
        ok($defaulted->{native_test}{passed}, 'default smoke passes');

        my $wrong = $real->compile({ region_id => 'r3', native_shape => { kind => 'i64_binary_leaf', op => 'multiply', smoke_left => 2, smoke_right => 3, smoke_expected => 7 } });
        ok(!$wrong->{native_test}{passed}, 'wrong expectation fails the smoke test');

        my $sum = $real->compile({ region_id => 'r4', native_shape => { kind => 'i64_sum_loop', op => 'sum_to_n', smoke_left => 10, smoke_right => 0, smoke_expected => 55 } });
        ok($sum->{native_test}{passed}, 'sum loop passes');
        my $mix = $real->compile({ region_id => 'r5', native_shape => { kind => 'i64_masked_mix_accum_loop', op => 'm', smoke_left => 8, smoke_right => 0, smoke_expected => 364 } });
        ok($mix->{native_test}{passed}, 'masked mix loop passes');
        my $sub = $real->compile({ region_id => 'r6', native_shape => { kind => 'i64_binary_leaf', op => 'subtract' } });
        is($sub->{native_test}{actual}, '-1', 'subtract default smoke');
        my $probe = $real->compile({ region_id => 'r7' });
        is($probe->{entry_kind}, 'native_probe_trampoline', 'probe artifact');
        ok(!defined $probe->{executable_path}, 'probe has no executable');
    }

    # Failing and partial fake compilers.
    my $out2 = File::Spec->catdir($root, 'native2');
    my $leafunit = { region_id => 'f1', native_shape => { kind => 'i64_binary_leaf', op => 'add' } };
    {
        local $ENV{CC} = write_exec('cc-fail.sh', "#!/bin/sh\nexit 1\n");
        my $r = PAX::Tier1->new(out_dir => $out2)->compile($leafunit);
        is($r->{status}, 'fallback_artifact', 'failing compiler falls back');
        like($r->{reason}, qr/failed to emit/, 'failing compiler reason');
    }
    {
        local $ENV{CC} = write_exec('cc-nofile.sh', "#!/bin/sh\nexit 0\n");
        my $r = PAX::Tier1->new(out_dir => $out2)->compile($leafunit);
        is($r->{status}, 'fallback_artifact', 'compiler producing no library falls back');
    }
    {
        # Succeeds for the shared library, fails for the standalone executable.
        local $ENV{CC} = write_exec('cc-half.sh', "#!/bin/sh\ncase \"\$*\" in *-shared*) while [ \$# -gt 0 ]; do [ \"\$1\" = -o ] && : > \"\$2\"; shift; done; exit 0;; esac\nexit 1\n");
        my $r = PAX::Tier1->new(out_dir => $out2)->compile($leafunit);
        is($r->{status}, 'native_artifact', 'library-only artifact');
        ok(!defined $r->{native_test}, 'no smoke test without executable');
        ok(!defined $r->{executable_path}, 'no executable path');
    }
    {
        # Succeeds without producing the executable.
        local $ENV{CC} = write_exec('cc-noexe.sh', "#!/bin/sh\ncase \"\$*\" in *-shared*) while [ \$# -gt 0 ]; do [ \"\$1\" = -o ] && : > \"\$2\"; shift; done;; esac\nexit 0\n");
        my $r = PAX::Tier1->new(out_dir => $out2)->compile($leafunit);
        ok(!defined $r->{native_test}, 'missing executable yields no smoke test');
    }
    {
        # Unwritable source path.
        local $ENV{CC} = write_exec('cc-ok.sh', "#!/bin/sh\nexit 0\n");
        no warnings 'redefine';
        local *PAX::Tier1::sha256_hex = sub { 'fixedid' };
        make_path(File::Spec->catdir($out2, 'fixedid.c'));
        my $r = PAX::Tier1->new(out_dir => $out2)->compile($leafunit);
        is($r->{status}, 'fallback_artifact', 'unwritable source falls back');
        like($r->{reason}, qr/cannot write native source/, 'unwritable source reason');
    }
}

done_testing;
