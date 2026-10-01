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

=pod

=head1 NAME

t/cov_cuca_compile.t - compile() decision-tree coverage for the code-unit compiler

=head1 WHY IT EXISTS

C<PAX::CodeUnitCompiler::compile> chooses between compiled, hybrid and source
fallback units through many size, coverage and capture gates. Each gate needs a
module that lands on both sides of it, and the live-capture gates need a stubbed
capture result so they run in-process.

=head1 DESCRIPTION

Every scenario writes a small module or script into a temporary directory, runs
it through C<compile>, and asserts the packaging, fallback reason and the decoded
record. Live capture is replaced by a stub returning a hand-made capture
structure, and the timeout wrapper is exercised with stubbed capture calls.

=cut

{
    package Demo::FalseError;
    use overload 'bool' => sub { 0 }, '""' => sub { 'false error' };
}

{
    package Demo::TiedSig;
    # TIEHASH() builds the tied signal table stand-in.
    # Input: class name. Output: blessed object.
    sub TIEHASH { return bless {}, shift }
    # FETCH() reports every handler slot as unset.
    # Input: object and key. Output: undef.
    sub FETCH { return undef }
    # STORE() runs any handler it is given at once, as if the signal were already pending.
    # Input: object, key and value. Output: nothing useful.
    sub STORE { my ($self, $key, $value) = @_; $value->() if ref($value) eq 'CODE'; return }
    # EXISTS() reports every handler slot as present.
    # Input: object and key. Output: 1.
    sub EXISTS { return 1 }
    # DELETE() ignores deletions.
    # Input: object and key. Output: undef.
    sub DELETE { return undef }
}

my $root = tempdir('pax-cov-cuca-compile-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $compiler = PAX::CodeUnitCompiler->new;
my $counter = 0;

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

# build($source, $kind)
# Writes a module source to a fresh path and compiles it.
# Input: module source and unit kind (default lib). Output: (unit, path).
sub build {
    my ($source, $kind) = @_;
    $kind ||= 'lib';
    my $path = write_file(File::Spec->catfile($root, 'unit' . ++$counter, 'lib', 'Demo', 'Unit.pm'), $source);
    my $unit = $compiler->compile(path => $path, kind => $kind, logical_path => "lib/unit$counter/Demo/Unit.pm");
    return ($unit, $path);
}

# record($unit)
# Decodes the JSON payload of a compiled unit.
# Input: unit hash. Output: decoded record.
sub record {
    my ($unit) = @_;
    return JSON::PP->new->decode($unit->{bytes});
}

# many_subs($prefix, $count)
# Produces source for several subs the recognisers cannot compile.
# Input: name prefix and count. Output: perl source text.
sub many_subs {
    my ($prefix, $count) = @_;
    return join '', map { "sub ${prefix}_$_ { my (\$value) = \@_; return length(\$value) . 'x'; }\n" } 1 .. $count;
}

# argument validation
{
    local $@;
    eval { $compiler->compile(kind => 'lib', logical_path => 'x') };
    like($@, qr/path required/, 'compile requires a path');
    eval { $compiler->compile(path => 'x', logical_path => 'x') };
    like($@, qr/kind required/, 'compile requires a kind');
    eval { $compiler->compile(path => 'x', kind => 'lib') };
    like($@, qr/logical_path required/, 'compile requires a logical path');
    my $missing = $compiler->compile(path => File::Spec->catfile($root, 'no', 'such', 'file.pm'), kind => 'lib', logical_path => 'lib/no.pm');
    is($missing->{fallback_reason}, 'missing_package_declaration', 'an unreadable path reads as an empty source and falls back');

    no warnings 'redefine';
    local *PAX::CodeUnitCompiler::abs_path = sub { return undef };
    my $unresolved = $compiler->compile(path => '', kind => 'lib', logical_path => 'lib/empty.pm');
    is($unresolved->{source_path}, '', 'an empty unresolvable path is kept as given');
    is($unresolved->{fallback_reason}, 'missing_package_declaration', 'an empty path has no package');
}

# entrypoint shapes
{
    my $router = write_file(File::Spec->catfile($root, 'router.pl'), <<'PERL');
#!/usr/bin/perl
use strict;
use warnings;
use Pod::Usage qw(pod2usage);

my $cmd = shift @ARGV || '';
if ( $cmd eq '' ) {
    pod2usage( -verbose => 1, -exitval => 1 );
}
if ( $cmd eq 'version' ) {
    require Demo::App;
    print $Demo::App::VERSION, "\n";
    exit 0;
}
print STDERR Demo::Suggest->new()->unknown_command_message($cmd);
exit 1;

sub _prime_command_result_env {
    return 1;
}

__END__

=head1 NAME

router - demo

=head1 SYNOPSIS

router [command]

=cut
PERL
    my $unit = $compiler->compile(path => $router, kind => 'entrypoint', logical_path => 'entrypoint/router');
    is($unit->{packaging}, 'compiled_cli_router_pcu_v1', 'a cli router entrypoint compiles to a router unit');
}

# module-level fallbacks
{
    my ($unit) = build("# no package here\nsub x { return 1; }\n1;\n");
    is($unit->{fallback_reason}, 'missing_package_declaration', 'a module without a package falls back');

    ($unit) = build("package Demo::Moo;\nuse Moo;\nhas name => (is => 'ro');\n1;\n");
    is($unit->{fallback_reason}, 'unsupported_class_builder_dsl', 'class-builder modules fall back');

    ($unit) = build("package Demo::Moo;\nuse Moo;\nsub name { return 'x'; }\n1;\n");
    isnt($unit->{fallback_reason} // '', 'unsupported_class_builder_dsl', 'use Moo without declarations is not a builder module');

    ($unit) = build("package Demo::Plain;\nsub name { return 'x'; }\n1;\n");
    isnt($unit->{fallback_reason} // '', 'unsupported_class_builder_dsl', 'a module without a builder import is not a builder module');

    ($unit) = build("package Demo::Init;\nour \$count = (\$other // 0) + 1;\nsub one { return 1; }\n1;\n");
    is($unit->{fallback_reason}, 'unsupported_initializer_pattern', 'an unsupported initializer falls back');

    ($unit) = build("package Demo::Exp;\nour \@EXPORT_OK = qw(one);\nsub one { return 1; }\n1;\n");
    is($unit->{fallback_reason}, 'unsupported_exporter_contract', 'exporter contracts fall back');

    ($unit) = build("package Demo::Bare;\nour \$VERSION = '1.0';\n1;\n");
    is($unit->{packaging}, 'compiled_pcu_v1', 'a module without subs compiles to an initializer-only unit');
    is_deeply(record($unit)->{subs}, [], 'initializer-only unit carries no subs');
}

# dependency units
{
    my ($unit) = build("package Demo::Dep;\nsub one { return 1; }\nsub two { return 2; }\n1;\n", 'dependency');
    is($unit->{packaging}, 'compiled_pcu_v1', 'a dependency whose subs all compile is a compiled unit');
    is(scalar @{ record($unit)->{subs} }, 2, 'both literal subs are compiled');

    ($unit) = build("package Demo::Dep;\nsub one { return 1; }\n" . many_subs('hard', 2) . "1;\n", 'dependency');
    is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'a dependency with a few residual subs is hybrid');
    is_deeply([ sort @{ $unit->{unsupported_subs} } ], [ 'Demo::Dep::hard_1', 'Demo::Dep::hard_2' ], 'residual subs are listed');

    ($unit) = build("package Demo::Dep;\n" . many_subs('hard', 9) . "1;\n", 'dependency');
    is($unit->{packaging}, 'source_payload_fallback', 'a dependency with mostly residual subs keeps its source');
    is($unit->{fallback_reason}, 'hybrid_coverage_too_low', 'low coverage is the recorded reason');
    is($unit->{fallback_detail}, 'supported=0 unsupported=9', 'coverage detail counts both sides');
}

# lazy hybrid selection for large modules
{
    local $ENV{PAX_CODE_UNIT_MAX_CAPTURE_SUBS} = 1;
    my ($unit) = build("package Demo::Lazy;\nsub one { return 1; }\nsub two { return 2; }\n1;\n");
    is($unit->{packaging}, 'compiled_pcu_v1', 'a large module whose subs all compile is a compiled unit');

    ($unit) = build("package Demo::Lazy;\nsub one { return 1; }\n" . many_subs('hard', 2) . "1;\n");
    is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'a large module with some residual subs is hybrid');

    ($unit) = build("package Demo::Lazy;\n" . many_subs('hard', 9) . "1;\n");
    is($unit->{fallback_reason}, 'hybrid_coverage_too_low', 'a large module with mostly residual subs falls back');
}

# lazy selection by source size
{
    local $ENV{PAX_CODE_UNIT_MAX_CAPTURE_BYTES} = 40;
    my ($unit) = build("package Demo::Big;\nsub one { return 1; }\n1;\n");
    is($unit->{packaging}, 'compiled_pcu_v1', 'source size above the byte budget selects the lazy path');

    ($unit) = build("package Demo::Big;\n\n=pod\n\nsub ghost\n\n=cut\n\n1;\n");
    is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'a large module whose only sub lives in pod is an empty hybrid');
    is_deeply(record($unit)->{unsupported_subs}, [], 'the pod-only sub is not tracked');
}

# capture skipped (no native-loop shape in the source)
{
    local $ENV{PAX_CODE_UNIT_CAPTURE};
    my ($unit) = build("package Demo::Skip;\nsub one { return 1; }\n1;\n");
    is($unit->{packaging}, 'compiled_pcu_v1', 'a skipped capture still compiles source-recognised subs');

    ($unit) = build("package Demo::Skip;\nsub one { return 1; }\n" . many_subs('hard', 2) . "1;\n");
    is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'a skipped capture keeps residual subs hybrid');

    ($unit) = build("package Demo::Skip;\n" . many_subs('hard', 9) . "1;\n");
    is($unit->{fallback_reason}, 'hybrid_coverage_too_low', 'a skipped capture with mostly residual subs falls back');

    ($unit) = build("package Demo::Skip;\n\n=pod\n\nsub ghost\n\n=cut\n\n1;\n");
    is($unit->{fallback_reason}, 'capture_failed', 'a module with no real subs and no capture falls back as capture_failed');
}

# capture timeout wrapper
{
    my @calls;
    no warnings 'redefine';
    local *PAX::CodeUnitCompiler::_capture_live_unit = sub { push @calls, $_[0]; return { status => 'ok', path => $_[0] } };
    {
        local $ENV{PAX_CODE_UNIT_CAPTURE_TIMEOUT} = -1;
        my $result = PAX::CodeUnitCompiler::_capture_with_timeout('/neg/path.pm', 'lib');
        is($result->{path}, '/neg/path.pm', 'a negative timeout captures without an alarm');
    }
    {
        local $ENV{PAX_CODE_UNIT_CAPTURE_TIMEOUT} = 0;
        my $result = PAX::CodeUnitCompiler::_capture_with_timeout('/some/path.pm', 'lib');
        is($result->{path}, '/some/path.pm', 'a zero timeout captures without an alarm');
    }
    {
        local $ENV{PAX_CODE_UNIT_CAPTURE_TIMEOUT};
        my $result = PAX::CodeUnitCompiler::_capture_with_timeout('/dep/path.pm', 'dependency');
        is($result->{status}, 'ok', 'dependency units use the short default timeout');
        $result = PAX::CodeUnitCompiler::_capture_with_timeout('/lib/path.pm', 'lib');
        is($result->{status}, 'ok', 'library units use the long default timeout');
        $result = PAX::CodeUnitCompiler::_capture_with_timeout('/lib/path.pm');
        is($result->{status}, 'ok', 'a missing kind uses the long default timeout');
    }
    {
        local $ENV{PAX_CODE_UNIT_CAPTURE_TIMEOUT} = '';
        my $result = PAX::CodeUnitCompiler::_capture_with_timeout('/lib/empty.pm', 'lib');
        is($result->{status}, 'ok', 'an empty timeout setting falls back to the default');
    }
    {
        local $ENV{PAX_CODE_UNIT_CAPTURE_TIMEOUT} = 3;
        local *PAX::CodeUnitCompiler::_capture_timeout_supported = sub { 0 };
        my $result = PAX::CodeUnitCompiler::_capture_with_timeout('/lib/noalarm.pm', 'lib');
        is($result->{path}, '/lib/noalarm.pm', 'platforms without alarm capture directly');
    }
    {
        local $ENV{PAX_CODE_UNIT_CAPTURE_TIMEOUT} = 3;
        local *PAX::CodeUnitCompiler::_capture_live_unit = sub { kill 'ALRM', $$; select(undef, undef, undef, 0.2); return { status => 'ok' } };
        my $result = PAX::CodeUnitCompiler::_capture_with_timeout('/lib/slow.pm', 'lib');
        is($result->{status}, 'capture_timeout', 'an alarm during capture yields a timeout status');
        like($result->{error}, qr/capture timeout/, 'the timeout error text is recorded');
    }
    {
        local $ENV{PAX_CODE_UNIT_CAPTURE_TIMEOUT} = 3;
        local *PAX::CodeUnitCompiler::_capture_live_unit = sub { die 0 };
        my $result = PAX::CodeUnitCompiler::_capture_with_timeout('/lib/boom.pm', 'lib');
        is($result->{status}, 'capture_timeout', 'a failing capture is reported through the timeout status');
    }
    {
        local $ENV{PAX_CODE_UNIT_CAPTURE_TIMEOUT} = 3;
        local *PAX::CodeUnitCompiler::_capture_live_unit = sub { die bless({}, 'Demo::FalseError') };
        my $result = PAX::CodeUnitCompiler::_capture_with_timeout('/lib/object.pm', 'lib');
        is($result->{status}, 'capture_timeout', 'a false-valued exception still reports a timeout status');
        is($result->{error}, 'capture_failed', 'a false-valued exception is replaced by the generic failure text');
    }
    ok(PAX::CodeUnitCompiler::_capture_timeout_supported(), 'alarm is supported on this platform');
    {
        delete local $SIG{ALRM};
        is(PAX::CodeUnitCompiler::_capture_timeout_supported(), 0, 'a platform without an ALRM slot reports no alarm support');
    }
    {
        tie %SIG, 'Demo::TiedSig';
        my $supported = PAX::CodeUnitCompiler::_capture_timeout_supported();
        untie %SIG;
        is($supported, 0, 'a handler slot that fires while it is probed reports no alarm support');
    }
}

# live capture entry point
{
    no warnings 'redefine';
    my @seen;
    local *PAX::Capture::capture = sub { my ($self, $path) = @_; push @seen, [ $self->{mode}, $path ]; return { status => 'ok' } };
    my $result = PAX::CodeUnitCompiler::_capture_live_unit('/some/file.pm');
    is($result->{status}, 'ok', 'live capture delegates to the capture engine');
    is_deeply(\@seen, [ [ 'live', '/some/file.pm' ] ], 'live capture uses live mode on the given path');
}

# capture-driven compilation with a stubbed capture result
{
    local $ENV{PAX_CODE_UNIT_CAPTURE} = 'always';
    my $capture;
    my $capture_path;
    no warnings 'redefine';
    local *PAX::CodeUnitCompiler::_capture_with_timeout = sub { $capture_path = $_[0]; return $capture };

    # sub_entry($name, %extra)
    # Builds one captured sub optree record pointing at the unit under test.
    # Input: fully qualified sub name and extra fields. Output: optree hash.
    my $sub_entry = sub {
        my ($name, %extra) = @_;
        return { name => $name, closure_descriptor => { file => $capture_path }, %extra };
    };
    my $ok = sub { return { status => 'ok', capture => { sub_optrees => [ @_ ] } } };

    my $source = "package Demo::Cap;\nsub one { return 1; }\nsub add { my (\$a, \$b) = \@_; return \$a + \$b; }\nsub jj { return jenc(\$_[0]); }\n1;\n";
    my ($unit, $path);

    # The path the stub sees is only known after the file is written, so write first.
    my $prepare = sub {
        my ($src) = @_;
        $path = write_file(File::Spec->catfile($root, 'cap' . ++$counter, 'Demo', 'Cap.pm'), $src);
        $capture_path = $path;
        return $path;
    };
    my $run = sub {
        my ($src, $make_capture, $kind) = @_;
        $prepare->($src);
        $capture = $make_capture->();
        return $compiler->compile(path => $path, kind => $kind || 'lib', logical_path => "lib/cap$counter/Demo/Cap.pm");
    };

    $unit = $run->($source, sub {
        $ok->(
            $sub_entry->('Demo::Cap::one'),
            $sub_entry->('Demo::Cap::add', native_shape => { kind => 'i64_binary_leaf', op => 'add' }),
            $sub_entry->('Demo::Cap::jj'),
            { name => 'Demo::Cap::alien', closure_descriptor => { file => '/elsewhere/Alien.pm' } },
            { name => 'Other::Pkg::one', closure_descriptor => { file => $capture_path } },
            { name => 'Demo::Cap::nofile', closure_descriptor => {} },
            { closure_descriptor => { file => $capture_path } },
        );
    });
    is($unit->{packaging}, 'compiled_pcu_v1', 'captured subs that all compile give a compiled unit');
    my %ops = map { $_->{name} => $_->{op} } @{ record($unit)->{subs} };
    is_deeply(\%ops, { one => 'return_literal', add => 'native_shape_sub', jj => 'call_named_with_first_arg' }, 'captured subs use native, literal and source recognisers');

    $unit = $run->($source, sub { $ok->($sub_entry->('Demo::Cap::one')) });
    is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'declared subs the capture did not list are compiled from source when recognised');
    is(scalar @{ record($unit)->{subs} }, 2, 'the literal and call subs are present');
    is_deeply($unit->{unsupported_subs}, [ 'Demo::Cap::add' ], 'the arithmetic sub needs the native shape and stays residual');

    $unit = $run->("package Demo::Cap;\nsub one { return 1; }\nsub two { return 2; }\n1;\n", sub { $ok->($sub_entry->('Demo::Cap::one')) });
    is($unit->{packaging}, 'compiled_pcu_v1', 'an unlisted but recognised sub keeps the unit compiled');
    is(scalar @{ record($unit)->{subs} }, 2, 'both subs are present');

    my $with_residual = "package Demo::Cap;\nsub one { return 1; }\n" . many_subs('hard', 2) . "1;\n";
    $unit = $run->($with_residual, sub { $ok->($sub_entry->('Demo::Cap::one'), $sub_entry->('Demo::Cap::hard_1')) });
    is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'a captured but unsupported sub makes the unit hybrid');
    is_deeply([ sort @{ $unit->{unsupported_subs} } ], [ 'Demo::Cap::hard_1', 'Demo::Cap::hard_2' ], 'captured and unlisted residual subs are both tracked');

    my $mostly_residual = "package Demo::Cap;\nsub one { return 1; }\n" . many_subs('hard', 9) . "1;\n";
    $unit = $run->($mostly_residual, sub { $ok->($sub_entry->('Demo::Cap::one')) });
    is($unit->{fallback_reason}, 'hybrid_coverage_too_low', 'compiled plus many residual subs falls back to source');
    is($unit->{fallback_detail}, 'supported=1 unsupported=9', 'the capture path reports the coverage detail');

    my $only_residual = "package Demo::Cap;\n" . many_subs('hard', 2) . "1;\n";
    $unit = $run->($only_residual, sub { $ok->() });
    is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'residual subs with no initializers and no compiled subs are hybrid');
    is(scalar @{ record($unit)->{subs} }, 0, 'the hybrid carries no compiled subs');

    my $too_many_residual = "package Demo::Cap;\n" . many_subs('hard', 9) . "1;\n";
    $unit = $run->($too_many_residual, sub { $ok->() });
    is($unit->{fallback_reason}, 'hybrid_coverage_too_low', 'only residual subs beyond the budget fall back to source');
    is($unit->{fallback_detail}, 'supported=0 unsupported=9', 'the empty-capture detail counts residual subs');

    my $ghost = "package Demo::Cap;\n\n=pod\n\nsub ghost\n\n=cut\n\n1;\n";
    $unit = $run->($ghost, sub { $ok->() });
    is($unit->{fallback_reason}, 'no_supported_compiled_content', 'a module with nothing to compile falls back');

    my $with_init = "package Demo::Cap;\nour \$VERSION = '1.0';\n" . many_subs('hard', 2) . "1;\n";
    $unit = $run->($with_init, sub { $ok->() });
    is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'initializers with only residual subs and an empty capture are hybrid');
    is_deeply([ sort @{ $unit->{unsupported_subs} } ], [ 'Demo::Cap::hard_1', 'Demo::Cap::hard_2' ], 'every declared sub stays residual');

    my $with_init_many = "package Demo::Cap;\nour \$VERSION = '1.0';\n" . many_subs('hard', 9) . "1;\n";
    $unit = $run->($with_init_many, sub { $ok->() });
    is($unit->{fallback_reason}, 'hybrid_coverage_too_low', 'initializers with many residual subs and an empty capture fall back');

    $unit = $run->($with_init, sub { { status => 'ok', capture => {} } });
    is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'a capture without sub optrees is treated as empty');

    # A capture that fails: source-recognised subs still make a compiled unit.
    $unit = $run->("package Demo::Cap;\nsub one { return 1; }\n1;\n", sub { { status => 'capture_timeout' } });
    is($unit->{packaging}, 'compiled_pcu_v1', 'a failed capture still compiles when every sub is recognised');

    $unit = $run->("package Demo::Cap;\nsub one { return 1; }\n" . many_subs('hard', 2) . "1;\n", sub { { status => 'capture_timeout' } });
    is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'a failed capture with residual subs is hybrid');

    $unit = $run->("package Demo::Cap;\n" . many_subs('hard', 9) . "1;\n", sub { {} });
    is($unit->{fallback_reason}, 'hybrid_coverage_too_low', 'a capture without a status counts as failed and falls back on low coverage');

    $unit = $run->($ghost, sub { { status => 'capture_timeout' } });
    is($unit->{fallback_reason}, 'capture_failed', 'a failed capture with no declared subs reports capture_failed');

    # initializers plus a source-recognised sub and an empty capture
    $unit = $run->("package Demo::Cap;\nour \$VERSION = '1.0';\nsub one { return 1; }\n1;\n", sub { $ok->() });
    is($unit->{packaging}, 'compiled_pcu_v1', 'initializers with a source-compiled sub and an empty capture stay compiled');
    is(scalar @{ record($unit)->{subs} }, 1, 'the source-compiled sub is kept');

    # initializers with only a pod-hidden sub
    $unit = $run->("package Demo::Cap;\nour \$VERSION = '1.0';\n\n=pod\n\nsub ghost\n\n=cut\n\n1;\n", sub { $ok->() });
    is($unit->{packaging}, 'compiled_pcu_v1', 'initializers with no real subs compile to an initializer-only unit');
    is(scalar @{ record($unit)->{subs} }, 0, 'no subs are recorded');

    # An explicit undef from the source recogniser counts as unsupported.
    {
        local *PAX::CodeUnitCompiler::_compile_declared_sub_from_source = sub { return (undef) };
        $unit = $run->("package Demo::Cap;\nsub one { return 1; }\n1;\n", sub { { status => 'capture_timeout' } });
        is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'undef recogniser results leave the sub residual');
        is_deeply($unit->{unsupported_subs}, [ 'Demo::Cap::one' ], 'the residual sub is tracked');
    }

    # Source-compiled records without a full name are ignored by the merge step.
    {
        local *PAX::CodeUnitCompiler::_compile_declared_sub_from_source = sub { return { name => 'one', op => 'return_literal' } };
        $unit = $run->("package Demo::Cap;\nsub one { return 1; }\n1;\n", sub { $ok->() });
        is($unit->{packaging}, 'hybrid_compiled_pcu_v1', 'nameless source records cannot cover a declared sub');
        is_deeply($unit->{unsupported_subs}, [ 'Demo::Cap::one' ], 'the declared sub stays residual');
    }
}

# per-sub compile helpers
{
    my $source = "package Demo::Sub;\nsub fixed { return 7; }\n1;\n";
    is(PAX::CodeUnitCompiler::_compile_sub({}, $source), undef, '_compile_sub needs a name');
    is(PAX::CodeUnitCompiler::_compile_sub({ name => 'plain' }, $source), undef, '_compile_sub needs a qualified name');
    my $literal = PAX::CodeUnitCompiler::_compile_sub({ name => 'Demo::Sub::fixed' }, $source);
    is($literal->{op}, 'return_literal', '_compile_sub falls through to literal subs');
    is($literal->{value}, 7, 'the literal value is carried');
    my $shaped = PAX::CodeUnitCompiler::_compile_sub({ name => 'Demo::Sub::sum', native_shape => { kind => 'i64_sum_loop' } }, "package Demo::Sub;\nsub sum(\$) { return 1; }\n");
    is($shaped->{op}, 'native_shape_sub', '_compile_sub keeps native shaped subs');
    is($shaped->{prototype}, '($)', 'native shaped subs carry the source prototype');
    my $masked = PAX::CodeUnitCompiler::_compile_sub({ name => 'Demo::Sub::mix', native_shape => { kind => 'i64_masked_mix_accum_loop' } }, $source);
    is($masked->{op}, 'native_shape_sub', 'masked mix loops are native shaped subs');
    my $other_shape = PAX::CodeUnitCompiler::_compile_sub({ name => 'Demo::Sub::fixed', native_shape => { kind => 'other' } }, $source);
    is($other_shape->{op}, 'return_literal', 'unknown native shapes are ignored');
    my $kindless_shape = PAX::CodeUnitCompiler::_compile_sub({ name => 'Demo::Sub::fixed', native_shape => {} }, $source);
    is($kindless_shape->{op}, 'return_literal', 'native shapes without a kind are ignored');
    is(PAX::CodeUnitCompiler::_compile_sub({ name => 'Demo::Sub::unknown' }, $source), undef, '_compile_sub rejects unrecognised subs');
    my $custom = PAX::CodeUnitCompiler::_compile_sub({ name => 'Demo::Plat::is_windows' }, "package Demo::Plat;\nsub is_windows {\n    return \$OS_NAME eq 'MSWin32' ? 1 : 0;\n}\n1;\n");
    is($custom->{op}, 'global_eq_literal_bool', '_compile_sub prefers source-derived custom ops');
}

# prototype propagation
{
    my $with_proto = PAX::CodeUnitCompiler::_compile_declared_sub_from_source("package Demo::P;\nsub fixed(\$\$) { return 7; }\n1;\n", 'Demo::P::fixed');
    is($with_proto->{prototype}, '($$)', 'compiled records pick up the source prototype');
    my $without = PAX::CodeUnitCompiler::_compile_declared_sub_from_source("package Demo::P;\nsub fixed { return 7; }\n1;\n", 'Demo::P::fixed');
    ok(!defined $without->{prototype}, 'a sub without a prototype stays without one');
    is(PAX::CodeUnitCompiler::_compile_declared_sub_from_source("package Demo::P;\nsub hard { my \$x = shift; \$x * 2 }\n1;\n", 'Demo::P::hard'), undef, 'an unsupported sub yields no record');

    my $custom_proto = PAX::CodeUnitCompiler::_compile_declared_sub_from_source("package Demo::P;\nsub is_windows() {\n    return \$OS_NAME eq 'MSWin32' ? 1 : 0;\n}\n1;\n", 'Demo::P::is_windows');
    is($custom_proto->{prototype}, '()', 'a record that already carries a prototype keeps it');

    no warnings 'redefine';
    {
        local *PAX::CodeUnitCompiler::_sub_prototype_from_source = sub { return '' };
        my $empty = PAX::CodeUnitCompiler::_compile_declared_sub_from_source("package Demo::P;\nsub fixed { return 7; }\n1;\n", 'Demo::P::fixed');
        ok(!defined $empty->{prototype}, 'an empty prototype string is not recorded');
    }
    {
        local *PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped = sub { return [ 'not', 'a', 'hash' ] };
        my $odd = PAX::CodeUnitCompiler::_compile_declared_sub_from_source('package Demo::P;', 'Demo::P::x');
        is_deeply($odd, [ 'not', 'a', 'hash' ], 'non-hash records are returned untouched');
    }
    {
        local *PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped = sub { return { name => 'x' } };
        my $odd = PAX::CodeUnitCompiler::_compile_declared_sub_from_source('package Demo::P;', 'Demo::P::');
        is_deeply($odd, { name => 'x' }, 'a full name without a short part leaves the record unchanged');
    }
}

# page document special case and the literal fallback
{
    my $page_source = <<'PERL';
package Demo::PageDocument;
sub _decode_stash_section {
    my ($text) = @_;
    return json_decode($text);
}
sub _parse_legacy_sections {
    return 1;
}
1;
PERL
    my $record = PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped($page_source, 'Demo::PageDocument::_decode_stash_section');
    is($record->{op}, 'page_document_decode_stash_section', 'the page document decoder is recognised');
    is($record->{trim_method}, 'Demo::PageDocument::_trim', 'its trim method is package scoped');

    ($record) = (PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped($page_source, 'Demo::PageDocument::_other'));
    ok(!$record, 'other subs of the page document package are not recognised');

    my $short = PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped("package Demo::PageDocument;\nsub _decode_stash_section { return \"x\"; }\n1;\n", 'Demo::PageDocument::_decode_stash_section');
    is($short->{op}, 'return_literal', 'without the neighbouring parser the decoder falls to the literal recogniser');

    ok(!PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped('x', 'unqualified'), 'an unqualified name is rejected');

    my $literal = PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped("package Demo::L;\nsub n { return 3; }\n1;\n", 'Demo::L::n');
    is($literal->{op}, 'return_literal', 'integer literal subs are recognised');
    is($literal->{value_type}, 'integer', 'integer literal type is recorded');
    my $string = PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped("package Demo::L;\nsub s { return \"a\\\"b\\nc\"; }\n1;\n", 'Demo::L::s');
    is($string->{value}, "a\"b\nc", 'string literals are unescaped');
}

# class builder detection and native capture gating
{
    is(PAX::CodeUnitCompiler::_uses_class_builder_dsl("use Moo;\nhas name => (is => 'ro');\n"), 1, 'Moo declarations are detected');
    is(PAX::CodeUnitCompiler::_uses_class_builder_dsl("use Moose;\nsub x { 1 }\n"), 0, 'a builder import alone is not enough');
    is(PAX::CodeUnitCompiler::_uses_class_builder_dsl("use strict;\nhas x => 1;\n"), 0, 'declarations without a builder import are ignored');

    local $ENV{PAX_CODE_UNIT_CAPTURE};
    is(PAX::CodeUnitCompiler::_source_may_lower_native("sub x { 1 }"), 0, 'plain subs do not need capture');
    is(PAX::CodeUnitCompiler::_source_may_lower_native('for (my $i = 0; $i < 3; $i++) { }'), 1, 'a c-style numeric loop needs capture');
    is(PAX::CodeUnitCompiler::_source_may_lower_native('return $a + $b;'), 1, 'a binary arithmetic return needs capture');
    {
        local $ENV{PAX_CODE_UNIT_CAPTURE} = 'always';
        is(PAX::CodeUnitCompiler::_source_may_lower_native('x'), 1, 'always forces capture');
    }
    {
        local $ENV{PAX_CODE_UNIT_CAPTURE} = 'never';
        is(PAX::CodeUnitCompiler::_source_may_lower_native('for (my $i = 0; $i < 3; $i++) { }'), 0, 'never disables capture');
    }
}

# entry command recogniser
{
    my $entry = <<'PERL';
package Demo::Which;
sub _dashboard_entry_command {
    my $name = $ENV{DEMO_ENTRY} || 'demo';
    return $name;
}
1;
PERL
    my $record = PAX::CodeUnitCompiler::_custom_sub_from_source($entry, '_dashboard_entry_command', 'Demo::Which', 'Demo::Which::_dashboard_entry_command');
    is($record->{op}, 'app_entry_command', 'an entry command sub with an env fallback is recognised');
    is($record->{entrypoint_env}, 'DEMO_ENTRY', 'the env variable is read from the body');
    is($record->{entrypoint_fallback}, 'demo', 'the fallback command is read from the body');

    my $plain_source = "package Demo::Which;\nsub _other_entry_command {\n    return 'plain';\n}\n1;\n";
    my $plain = PAX::CodeUnitCompiler::_custom_sub_from_source($plain_source, '_other_entry_command', 'Demo::Which', 'Demo::Which::_other_entry_command');
    ok(!$plain, 'an entry-command-named sub without an env fallback is not an entry command');
    ok(!PAX::CodeUnitCompiler::_custom_sub_from_source($entry, 'absent_sub', 'Demo::Which', 'Demo::Which::absent_sub'), 'a sub that is not in the source is not recognised');
}

done_testing();
