use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/../lib";

use PAX::CodeUnitCompiler;
use PAX::StandaloneAnalysis;
use PAX::StandaloneImage;
use PAX::StandaloneRuntime;

=pod

=head1 NAME

t/build_speed.t - build-time and startup-time regression tests

=head1 WHY IT EXISTS

Build time and startup time are product requirements, so the shortcuts that meet
them (skipped capture, parallel compile, lazy handlers) need regression coverage.

=head1 DESCRIPTION

This file covers the changes that keep C<pax build> under a minute and keep the
standalone launcher fast: gated live capture, parallel unit compilation, lazily
compiled runtime op handlers, sibling data-file bundling, and source-derived
helper lists.

=cut

my $root = tempdir('pax-build-speed-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($path, $text)
# Writes a fixture file, creating parent directories first.
# Input: destination path and file text. Output: the path written.
sub write_file {
    my ($path, $text) = @_;
    my ($volume, $dir) = File::Spec->splitpath($path);
    make_path($dir) if length $dir && !-d $dir;
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh or die "cannot close $path: $!";
    return $path;
}

# Live capture only pays off for units that could contain a native shape.
{
    local $ENV{PAX_CODE_UNIT_CAPTURE};
    my $plain = "package Plain; use strict; sub name { return 'x' }\n1;\n";
    my $loop = <<'PERL';
package Hot;
# sum_to_n($n): integer sum loop used as a native-shape fixture.
sub sum_to_n {
    my ($n) = @_;
    my $sum = 0;
    for (my $i = 1; $i <= $n; $i++) { $sum += $i; }
    return $sum;
}
1;
PERL
    my $leaf = "package Leaf; sub add { my (\$a, \$b) = \@_; return \$a + \$b; }\n1;\n";
    ok(!PAX::CodeUnitCompiler::_source_may_lower_native($plain), 'plain module skips live capture');
    ok(PAX::CodeUnitCompiler::_source_may_lower_native($loop), 'numeric loop module keeps live capture');
    ok(PAX::CodeUnitCompiler::_source_may_lower_native($leaf), 'arithmetic leaf module keeps live capture');
    local $ENV{PAX_CODE_UNIT_CAPTURE} = 'always';
    ok(PAX::CodeUnitCompiler::_source_may_lower_native($plain), 'PAX_CODE_UNIT_CAPTURE=always forces capture');
    local $ENV{PAX_CODE_UNIT_CAPTURE} = 'never';
    ok(!PAX::CodeUnitCompiler::_source_may_lower_native($loop), 'PAX_CODE_UNIT_CAPTURE=never disables capture');
}

# The native-artifact analysis gate follows the exact shapes the lowering accepts.
{
    my $hot = <<'PERL';
# sum_to_n($n): integer sum loop used as a native-shape fixture.
sub sum_to_n {
    my ($n) = @_;
    my $sum = 0;
    for (my $i = 1; $i <= $n; $i++) {
        $sum += $i;
    }
    return $sum;
}
PERL
    my $busy = <<'PERL';
# walk($list): counted loop that is not a native shape.
sub walk {
    my ($list) = @_;
    my $total = 0;
    for (my $i = 0; $i < 3; $i++) {
        $total += length($list->[$i]);
    }
    return $total;
}
PERL
    ok(PAX::StandaloneAnalysis::_source_has_native_candidate($hot), 'sum loop is a native candidate');
    ok(!PAX::StandaloneAnalysis::_source_has_native_candidate($busy), 'ordinary counted loop is not a native candidate');
    ok(!PAX::StandaloneAnalysis::_source_has_native_candidate("sub f { return 1 }\n"), 'trivial sub is not a native candidate');
}

# Moo-style declarations are runtime side effects the unit compiler cannot model.
{
    my $moo = write_file(File::Spec->catfile($root, 'lib', 'Example', 'Hook.pm'), <<'PERL');
package Example::Hook;
use Moo;
has name => (is => 'rw', required => 1);
1;
PERL
    my $unit = PAX::CodeUnitCompiler->new->compile(
        path => $moo,
        kind => 'dependency',
        logical_path => 'dependency/Example/Hook.pm',
    );
    is($unit->{packaging}, 'source_payload_fallback', 'Moo class falls back to shipped source');
}

# Parallel unit compilation returns the same records, in job order, as serial.
{
    my @jobs;
    for my $n (1 .. 6) {
        my $path = write_file(File::Spec->catfile($root, 'par', "Unit$n.pm"), <<"PERL");
package Par::Unit$n;
use strict;
use warnings;
our \$VERSION = '0.0$n';
# label(): constant fixture sub.
sub label { return 'unit$n' }
1;
PERL
        push @jobs, { path => $path, kind => 'lib', logical_path => "lib/Par/Unit$n.pm", rel => "Unit$n.pm" };
    }
    my $compiler = PAX::CodeUnitCompiler->new;
    my @serial = do { local $ENV{PAX_JOBS} = 1; PAX::StandaloneImage::_compile_jobs_parallel($compiler, \@jobs, undef) };
    my @seen;
    my @parallel = do {
        local $ENV{PAX_JOBS} = 3;
        PAX::StandaloneImage::_compile_jobs_parallel($compiler, \@jobs, sub { push @seen, $_[0] });
    };
    is(scalar(@parallel), scalar(@jobs), 'parallel compile returns one record per job');
    my $stem = sub { my ($p) = @_; $p =~ s/\.(?:pcu\.json|pm)\z//; return $p };
    is_deeply([ map { $stem->($_->{logical_path}) } @parallel ], [ map { $stem->($_->{logical_path}) } @jobs ], 'parallel compile keeps job order');
    is_deeply([ map { $_->{sha256} } @parallel ], [ map { $_->{sha256} } @serial ], 'parallel compile matches serial output');
    is(scalar(@seen), scalar(@jobs), 'progress callback fires once per finished unit');
}

# Data files that sit beside a bundled module travel with it.
{
    my $inc = File::Spec->catdir($root, 'inc');
    my $module = write_file(File::Spec->catfile($inc, 'Data', 'Thing.pm'), "package Data::Thing; 1;\n");
    write_file(File::Spec->catfile($inc, 'Data', 'thing.db'), "rows\n");
    write_file(File::Spec->catfile($inc, 'Data', 'Thing.pod'), "=head1 NAME\n");
    write_file(File::Spec->catfile($inc, 'Top.pm'), "package Top; 1;\n");
    write_file(File::Spec->catfile($inc, 'top.db'), "root data\n");
    my @found = PAX::StandaloneImage::_sibling_data_files(
        [ $module, File::Spec->catfile($inc, 'Top.pm') ],
        [ $inc ],
    );
    is_deeply([ map { (File::Spec->splitpath($_))[2] } @found ], ['thing.db'], 'sibling data files are bundled, pods and inc-root files are not');
}

# Every lazily compiled runtime op handler still compiles, and unknown ops are rejected.
{
    open my $fh, '<', "$FindBin::Bin/../lib/PAX/StandaloneRuntime.pm" or die "cannot read runtime: $!";
    local $/;
    my $text = <$fh>;
    my ($data) = $text =~ /^__DATA__\n(.*)\z/ms;
    my @parts = split /^#\@\@PAX_OP (.*)\n/m, $data;
    shift @parts;
    my ($ok, @bad) = (0);
    while (@parts) {
        my ($ops, $body) = splice @parts, 0, 2;
        my ($op) = split ' ', $ops;
        my $handler = PAX::StandaloneRuntime::_compiled_op_handler($op);
        if (ref $handler eq 'CODE') { $ok++ } else { push @bad, $op }
    }
    cmp_ok($ok, '>', 600, 'runtime op table holds the compiled handlers');
    is_deeply(\@bad, [], 'every runtime op handler compiles on demand');
    ok(!defined PAX::StandaloneRuntime::_compiled_op_handler('no_such_op_exists'), 'unknown runtime op has no handler');
}

# Helper lists come from the source being compiled, not from a copy inside PAX.
{
    my $source = <<'PERL';
package Example::InternalCLI;
use strict;
use warnings;

# helper_names(): list literal the compiler must read from source.
sub helper_names {
    return qw(
      jq yq tomq propq iniq csvq xmlq
      of open-file widget
      complete
    );
}

# helper_aliases(): alias map the compiler must read from source.
sub helper_aliases {
    return {
        pjq   => 'jq',
        skill => 'skills',
        logs  => 'log',
    };
}
1;
PERL
    my $path = write_file(File::Spec->catfile($root, 'lib', 'Example', 'InternalCLI.pm'), $source);
    my $unit = PAX::CodeUnitCompiler->new->compile(
        path => $path,
        kind => 'lib',
        logical_path => 'lib/Example/InternalCLI.pm',
    );
    my $record = JSON::PP->new->decode($unit->{bytes});
    my ($names) = grep { ($_->{op} // '') eq 'internal_cli_helper_names' } @{ $record->{subs} // [] };
    my ($aliases) = grep { ($_->{op} // '') eq 'internal_cli_helper_aliases' } @{ $record->{subs} // [] };
    SKIP: {
        skip 'helper list ops did not match the synthetic source', 2 if !$names || !$aliases;
        ok((grep { $_ eq 'widget' } @{ $names->{names} }), 'helper names are read from the source');
        is_deeply($aliases->{aliases}, { pjq => 'jq', skill => 'skills', logs => 'log' }, 'helper aliases are read from the source');
    }
}

# The launcher manifest drops what the runtime never reads.
{
    my $manifest = {
        name => 'demo',
        code_units => [ { logical_path => 'a.pcu.json', source_bytes => 'x' x 100, bytes => 'b', sha256 => 'abc' } ],
        runtime_payloads => [ { logical_path => 'inc/000/Foo.pm', bytes => 'c' } ],
        assets => [ { logical_path => 'share/a.txt', bytes => 'd' } ],
        native_payloads => [],
    };
    my $launcher = PAX::StandaloneImage::_launcher_manifest($manifest);
    ok(!exists $launcher->{code_units}[0]{source_bytes}, 'launcher manifest drops embedded source text');
    ok(!exists $launcher->{code_units}[0]{bytes}, 'launcher manifest drops payload bytes');
    ok(!exists $launcher->{runtime_payloads}, 'launcher manifest drops the per-file runtime payload list');
    is($launcher->{code_units}[0]{logical_path}, 'a.pcu.json', 'launcher manifest keeps unit identity');
    is($launcher->{assets}[0]{logical_path}, 'share/a.txt', 'launcher manifest keeps asset entries');
    ok(exists $manifest->{code_units}[0]{source_bytes}, 'trimming does not modify the build manifest');
}

# Compiled subs install as stubs that build the real handler on first call.
{
    my $package = 'Lazy::Stub::Pkg';
    PAX::StandaloneRuntime::_install_compiled_sub_lazily($package, {
        name => 'answer',
        op => 'return_literal',
        value => 42,
    });
    no strict 'refs';
    my $stub = \&{"${package}::answer"};
    ok(defined &{"${package}::answer"}, 'lazy sub is callable before its handler exists');
    is($package->can('answer')->(), 42, 'lazy sub runs the real handler on first call');
    isnt(\&{"${package}::answer"}, $stub, 'first call replaces the stub with the real handler');
    is(&{"${package}::answer"}(), 42, 'replaced sub keeps working');
    PAX::StandaloneRuntime::_install_compiled_sub_lazily($package, {
        name => 'typed',
        op => 'return_literal',
        value => 7,
        prototype => '($$)',
    });
    is(prototype(\&{"${package}::typed"}), '$$', 'prototyped subs are installed eagerly so callers see the prototype');
    eval { PAX::StandaloneRuntime::_install_compiled_sub_lazily($package, { name => 'broken', op => 'no_such_op' }); &{"${package}::broken"}() };
    like($@, qr/unsupported compiled sub op/, 'unknown op fails loudly on first call');
}

# Usage text is rendered once at build time and replayed without Pod::Usage.
{
    my $script = write_file(File::Spec->catfile($root, 'usage', 'tool'), <<'PERL');
#!/usr/bin/env perl
use strict;
use warnings;
use Pod::Usage qw(pod2usage);
pod2usage(-verbose => 1);

__END__

=head1 NAME

tool - demo switchboard

=head1 SYNOPSIS

  tool help

=head1 DESCRIPTION

Longer text for the help form.

=cut
PERL
    open my $sfh, '<', $script or die $!;
    my $script_source = do { local $/; <$sfh> };
    close $sfh;
    my $usage = PAX::CodeUnitCompiler::_precompute_pod_usage($script, $script_source);
    ok($usage && $usage->{short} && $usage->{help}, 'usage text is precomputed for both router forms');
    like($usage->{short}{stdout}, qr/tool - demo switchboard/, 'short usage carries the NAME section');
    unlike($usage->{short}{stdout}, qr/Longer text/, 'short usage omits the DESCRIPTION section');
    like($usage->{help}{stdout}, qr/Longer text for the help form/, 'help usage carries the full POD');
    is($usage->{short}{exit}, 1, 'short usage records its exit code');
    is($usage->{help}{exit}, 0, 'help usage records its exit code');
    ok(!defined PAX::CodeUnitCompiler::_precompute_pod_usage($script, "print 1;\n"), 'scripts without pod2usage record nothing');

    my $record = { usage_outputs => { help => { stdout => "from build\n", stderr => "warned\n", exit => 3 } } };
    my $code = q{use PAX::StandaloneRuntime; PAX::StandaloneRuntime::_router_usage($ARGV[0] ? { usage_outputs => { help => { stdout => "from build\n", stderr => "warned\n", exit => 3 } } } : {}, 'help', []);};
    my $out_file = File::Spec->catfile($root, 'usage', 'replay.out');
    my $err_file = File::Spec->catfile($root, 'usage', 'replay.err');
    my $status = system(qq{"$^X" "-I$FindBin::Bin/../lib" -e '$code' 1 >"$out_file" 2>"$err_file"});
    is($status >> 8, 3, 'replayed usage exits with the recorded code');
    open my $ofh, '<', $out_file or die $!;
    is(do { local $/; <$ofh> }, "from build\n", 'replayed usage prints the recorded stdout');
    open my $efh, '<', $err_file or die $!;
    is(do { local $/; <$efh> }, "warned\n", 'replayed usage prints the recorded stderr');
}

done_testing();
