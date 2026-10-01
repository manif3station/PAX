use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();
use Symbol ();
use IO::Socket::UNIX ();
use lib "$FindBin::Bin/../lib";

use PAX::CodeUnitCompiler;

=pod

=head1 NAME

t/cov_cuce_helpers.t - direct coverage of the CodeUnitCompiler helper tail

=head1 WHY IT EXISTS

The helper functions at the end of C<PAX::CodeUnitCompiler> (class-tail
scanners, sub-body extraction, initializer parsing, native-shape recognizers,
CLI router, dispatch and service unit builders, hybrid record builder) carry many
small branches. This file drives each branch directly and through C<compile()>
on synthetic sources in temporary directories.

=head1 DESCRIPTION

Every case uses hermetic fixtures under a File::Temp directory and in-process
calls so Devel::Cover sees the executed code.

=cut

my $root = tempdir('pax-cov-cuce-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $C = 'PAX::CodeUnitCompiler';

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

# decode($unit)
# Decodes the JSON payload of a compiled unit record.
# Input: unit hash. Output: decoded record hash.
sub decode {
    my ($unit) = @_;
    return JSON::PP->new->decode($unit->{bytes});
}

my $compiler = $C->new;

# ---- class-tail scanners -------------------------------------------------
is($C->can('_requires_class_tail')->(undef, 'X'), 0, 'requires_class_tail: undef body');
is(PAX::CodeUnitCompiler::_requires_class_tail('require A;', undef), 0, 'requires_class_tail: undef tail');
is(PAX::CodeUnitCompiler::_requires_class_tail("x\n  require Foo::Bar;\n", 'Bar'), 1, 'requires_class_tail: match');
is(PAX::CodeUnitCompiler::_requires_class_tail("require Foo::Baz;\n", 'Bar'), 0, 'requires_class_tail: no match');

is(PAX::CodeUnitCompiler::_sibling_class('A::B', undef), 'A::B', 'sibling_class: undef class');
is(PAX::CodeUnitCompiler::_sibling_class('A::B', ''), 'A::B', 'sibling_class: empty class');
is(PAX::CodeUnitCompiler::_sibling_class(undef, 'C'), undef, 'sibling_class: undef package');
is(PAX::CodeUnitCompiler::_sibling_class('', 'C'), '', 'sibling_class: empty package');
is(PAX::CodeUnitCompiler::_sibling_class('A::B', 'C::D'), 'A::C::D', 'sibling_class: nested');
is(PAX::CodeUnitCompiler::_sibling_class('Solo', 'C'), 'C', 'sibling_class: rootless package');

is(PAX::CodeUnitCompiler::_related_class_from_source('', 'A::B', '', undef), 'A::B', 'related: undef class');
is(PAX::CodeUnitCompiler::_related_class_from_source('', 'A::B', '', ''), 'A::B', 'related: empty class');
is(PAX::CodeUnitCompiler::_related_class_from_source('', 'A::B', 'X::Y::Cls->go(1);', 'Cls', methods => ['go']),
    'X::Y::Cls', 'related: qualified in body');
is(PAX::CodeUnitCompiler::_related_class_from_source('Q::Cls::z();', 'A::B', undef, 'Cls'),
    'Q::Cls', 'related: qualified in source with undef body');
is(PAX::CodeUnitCompiler::_related_class_from_source("use M::Cls;\n", 'A::B', 'nothing', 'Cls'),
    'M::Cls', 'related: imported');
is(PAX::CodeUnitCompiler::_related_class_from_source('', 'A::B', '', 'Cls'), 'A::Cls', 'related: sibling fallback');

is(PAX::CodeUnitCompiler::_qualified_class_in_scope(undef, 'C', []), undef, 'qualified: undef scope');
is(PAX::CodeUnitCompiler::_qualified_class_in_scope('x', undef, []), undef, 'qualified: undef class');
is(PAX::CodeUnitCompiler::_qualified_class_in_scope('x', '', []), undef, 'qualified: empty class');
is(PAX::CodeUnitCompiler::_qualified_class_in_scope('A::C->run (1)', 'C', [undef, '', 'run']), 'A::C', 'qualified: method hit');
is(PAX::CodeUnitCompiler::_qualified_class_in_scope('A::C->other(1)', 'C', ['run']), 'A::C', 'qualified: method miss, bare class');
is(PAX::CodeUnitCompiler::_qualified_class_in_scope('A::C', 'C', undef), 'A::C', 'qualified: no methods');
is(PAX::CodeUnitCompiler::_qualified_class_in_scope('A::C', 'C', []), 'A::C', 'qualified: empty methods');
is(PAX::CodeUnitCompiler::_qualified_class_in_scope('nothing', 'C', []), undef, 'qualified: none');

# ---- sub extraction ------------------------------------------------------
is(PAX::CodeUnitCompiler::_extract_sub_body('sub a { 1 }', 'b'), undef, 'sub body: missing sub');
is(PAX::CodeUnitCompiler::_extract_sub_body('sub a { 1 { }', 'a'), undef, 'sub body: unterminated');
is(PAX::CodeUnitCompiler::_extract_sub_body('sub a { { 1 } 2 }', 'a'), ' { 1 } 2 ', 'sub body: nested');
is(PAX::CodeUnitCompiler::_extract_sub_source('sub a { 1 }', 'b'), undef, 'sub source: missing sub');
is(PAX::CodeUnitCompiler::_extract_sub_source('sub a { 1 { }', 'a'), undef, 'sub source: unterminated');
is(PAX::CodeUnitCompiler::_extract_sub_source("sub a { { 1 } } \t;\nx", 'a'), "sub a { { 1 } } \t;", 'sub source: nested with semicolon');
is(PAX::CodeUnitCompiler::_extract_sub_source("sub a { 1 } x", 'a'), 'sub a { 1 } ', 'sub source: trailing blanks no semicolon');
is(PAX::CodeUnitCompiler::_extract_sub_source("sub a { 1 }", 'a'), 'sub a { 1 }', 'sub source: ends at eof');
is(PAX::CodeUnitCompiler::_sub_prototype_from_source('sub a($$) { 1 }', 'a'), '($$)', 'prototype present');
is(PAX::CodeUnitCompiler::_sub_prototype_from_source('sub a { 1 }', 'a'), undef, 'prototype absent');
is(PAX::CodeUnitCompiler::_sub_prototype_from_source('sub b { 1 }', 'a'), undef, 'prototype missing sub');

is(PAX::CodeUnitCompiler::_bootstrap_source("use strict;\n=pod\n\nx\n\n=cut\nmy \$x;\nsub a { 1 }\n"), "use strict;\nmy \$x;\n", 'bootstrap stops at first sub');
is(PAX::CodeUnitCompiler::_bootstrap_source("use strict;\n"), "use strict;\n", 'bootstrap without subs');

# ---- initializers --------------------------------------------------------
{
    my $src = <<'PERL';
package P::Q;
use strict;
use warnings;
use Some::Mod qw(a b);
use Other::Mod;
require Req::Mod;
our $S1 = "a\"b\\c\nd";
our $S2 = 'x\'y\\z\n';
our $N1 = 42;
our $N2 = -1.5;
our @A1 = ('a', "b", 3, qw(x y), qw/p q/, map { sprintf 'n%d', $_ } 1 .. 3, map { sprintf 'm%d!', $_ } 3 .. 1);
our @A2 = qw(one two);
our @A3 = qw/three four/;
our $CNT = ($CNT // 0) + 2;
sub x { 1 }
PERL
    my @ops = PAX::CodeUnitCompiler::_compile_initializers($src, 'P::Q');
    my %by = map { ($_->{symbol} // $_->{module}) => $_ } @ops;
    is($by{'Some::Mod'}{args}[1], 'b', 'initializer: use args');
    is($by{'Req::Mod'}{op}, 'require_module', 'initializer: require');
    is($by{'P::Q::S1'}{value}, "a\"b\\c\nd", 'initializer: dq string');
    is($by{'P::Q::S2'}{value}, "x'y\\z\n", 'initializer: sq string');
    is($by{'P::Q::N1'}{value_type}, 'integer', 'initializer: integer');
    is($by{'P::Q::N2'}{value_type}, 'number', 'initializer: number');
    is_deeply($by{'P::Q::A1'}{values}, ['a', 'b', 3, 'x', 'y', 'p', 'q', 'n1', 'n2', 'n3', 'm3!', 'm2!', 'm1!'], 'initializer: array literal');
    is_deeply($by{'P::Q::A2'}{values}, ['one', 'two'], 'initializer: qw array');
    is_deeply($by{'P::Q::A3'}{values}, ['three', 'four'], 'initializer: qw// array');
    is($by{'P::Q::CNT'}{by}, 2, 'initializer: increment');

    my @bad_use = PAX::CodeUnitCompiler::_compile_initializers("package P;\nuse Foo (\$x + 1);\n", 'P');
    is_deeply(\@bad_use, [undef], 'initializer: unparsable use args');
    my @bad_inc = PAX::CodeUnitCompiler::_compile_initializers("package P;\nour \$A = (\$B // 0) + 1;\n", 'P');
    is_deeply(\@bad_inc, [undef], 'initializer: mismatched increment');
    my @skip = PAX::CodeUnitCompiler::_compile_initializers("package P;\nour \@Z = (\$weird);\nour \@Z = qw(a b);\n", 'P');
    is(scalar(@skip), 1, 'initializer: unparsable array falls to qw form');
    my @dup = PAX::CodeUnitCompiler::_compile_initializers("package P;\nour \@Z = ('a', 'b');\nour \@Z = qw(a b);\nour \@Y = ('c');\nour \@Y = qw/c/;\n", 'P');
    is(scalar(@dup), 2, 'initializer: literal arrays suppress duplicate qw forms');
}

is_deeply(PAX::CodeUnitCompiler::_parse_array_literal_values(undef), [], 'array literal: undef');
is_deeply(PAX::CodeUnitCompiler::_parse_array_literal_values(', 1'), [1], 'array literal: leading comma');
is_deeply(PAX::CodeUnitCompiler::_parse_array_literal_values('1, 2,'), [1, 2], 'array literal: trailing comma');
is_deeply(PAX::CodeUnitCompiler::_parse_array_literal_values("'a' 'b'"), ['a', 'b'], 'array literal: missing comma still reads next value');
is(PAX::CodeUnitCompiler::_parse_array_literal_values('$x'), undef, 'array literal: unsupported');

is(PAX::CodeUnitCompiler::_strip_pod(undef), '', 'strip_pod undef');
is(PAX::CodeUnitCompiler::_strip_pod("a\n=head1 X\nb\n=cut\nc\n__END__\nd\n"), "a\nc\n", 'strip_pod strips pod and __END__');

is_deeply(PAX::CodeUnitCompiler::_parse_use_args(undef), [], 'use args: undef');
is_deeply(PAX::CodeUnitCompiler::_parse_use_args('()'), [], 'use args: empty list');
is_deeply(PAX::CodeUnitCompiler::_parse_use_args('qw(a b)'), ['a', 'b'], 'use args: qw()');
is_deeply(PAX::CodeUnitCompiler::_parse_use_args('qw/a b/'), ['a', 'b'], 'use args: qw//');
is_deeply(PAX::CodeUnitCompiler::_parse_use_args(q{'a\'b', "c" => 3, -4.5, Foo::Bar}), ["a'b", 'c', 3, -4.5, 'Foo::Bar'], 'use args: mixed tokens');
is_deeply(PAX::CodeUnitCompiler::_parse_use_args("'a'  "), ['a'], 'use args: trailing whitespace trimmed');
is(PAX::CodeUnitCompiler::_parse_use_args('$x'), undef, 'use args: unsupported');
is_deeply(PAX::CodeUnitCompiler::_parse_use_args("'a' \n"), ['a'], 'use args: whitespace before end');

is(PAX::CodeUnitCompiler::_package_name("package A::B;\n"), 'A::B', 'package name');
is(PAX::CodeUnitCompiler::_package_name("nothing\n"), undef, 'package name absent');
is_deeply([PAX::CodeUnitCompiler::_declared_subs("sub a {}\nsub a {}\nsub b {}\n=pod\nsub c\n=cut\n", 'P')], ['P::a', 'P::b'], 'declared subs dedupe and skip pod');

{
    local $ENV{PAX_CODE_UNIT_MAX_CAPTURE_SUBS};
    local $ENV{PAX_CODE_UNIT_MAX_CAPTURE_BYTES};
    is(PAX::CodeUnitCompiler::_prefer_lazy_hybrid('x', [1 .. 26]), 1, 'lazy hybrid: too many subs');
    is(PAX::CodeUnitCompiler::_prefer_lazy_hybrid('x' x 20000, [1]), 1, 'lazy hybrid: too many bytes');
    is(PAX::CodeUnitCompiler::_prefer_lazy_hybrid('x', [1]), 0, 'lazy hybrid: small');
    local $ENV{PAX_CODE_UNIT_MAX_CAPTURE_SUBS} = 2;
    local $ENV{PAX_CODE_UNIT_MAX_CAPTURE_BYTES} = 4;
    is(PAX::CodeUnitCompiler::_prefer_lazy_hybrid('xxxxxx', [1]), 1, 'lazy hybrid: env byte limit override');
    is(PAX::CodeUnitCompiler::_prefer_lazy_hybrid('x', [1 .. 3]), 1, 'lazy hybrid: env sub limit override');
    is(PAX::CodeUnitCompiler::_prefer_lazy_hybrid('x', [1]), 0, 'lazy hybrid: under overridden limits');
}

is(PAX::CodeUnitCompiler::_prefer_source_fallback_over_hybrid('x', undef, undef), 0, 'fallback pref: nothing unsupported');
is(PAX::CodeUnitCompiler::_prefer_source_fallback_over_hybrid('x', [1], [1 .. 3]), 0, 'fallback pref: few unsupported');
is(PAX::CodeUnitCompiler::_prefer_source_fallback_over_hybrid('x', [], [1 .. 8]), 1, 'fallback pref: none supported');
is(PAX::CodeUnitCompiler::_prefer_source_fallback_over_hybrid('x', [1 .. 2], [1 .. 20]), 1, 'fallback pref: low coverage');
is(PAX::CodeUnitCompiler::_prefer_source_fallback_over_hybrid('x' x 9000, [1 .. 4], [1 .. 16]), 1, 'fallback pref: big source mostly unsupported');
is(PAX::CodeUnitCompiler::_prefer_source_fallback_over_hybrid('x', [1 .. 10], [1 .. 8]), 0, 'fallback pref: decent coverage');
is(PAX::CodeUnitCompiler::_prefer_source_fallback_over_hybrid(undef, [1 .. 10], [1 .. 8]), 0, 'fallback pref: undef source');
is(PAX::CodeUnitCompiler::_prefer_source_fallback_over_hybrid('x' x 9000, [1 .. 10], [1 .. 12]), 0, 'fallback pref: big source adequate coverage');

is(PAX::CodeUnitCompiler::_requires_source_exporter_contract("use Exporter 'import';"), 1, 'exporter: use');
is(PAX::CodeUnitCompiler::_requires_source_exporter_contract("our \@EXPORT_OK = ();"), 1, 'exporter: EXPORT');
is(PAX::CodeUnitCompiler::_requires_source_exporter_contract("1;"), 0, 'exporter: none');
is(PAX::CodeUnitCompiler::_hybrid_coverage_detail(undef, undef), 'supported=0 unsupported=0', 'coverage detail empty');
is(PAX::CodeUnitCompiler::_hybrid_coverage_detail([1], [1, 2]), 'supported=1 unsupported=2', 'coverage detail');

is(PAX::CodeUnitCompiler::_require_path_for('/x', 'A::B'), 'A/B.pm', 'require path');

# ---- unit builders -------------------------------------------------------
{
    my $p = write_file("$root/unit/Mod.pm", "package Mod;\n1;\n");
    my $fb = PAX::CodeUnitCompiler::_fallback_unit($p, 'dependency', 'dep/Mod.pm', 'why', 'detail');
    is($fb->{packaging}, 'source_payload_fallback', 'fallback unit packaging');
    is($fb->{fallback_detail}, 'detail', 'fallback unit detail');
    my $cu = PAX::CodeUnitCompiler::_compiled_unit($p, 'dependency', 'dep/Mod.pm', 'Mod', [], []);
    is($cu->{logical_path}, 'dep/Mod.pcu.json', 'compiled unit logical path');
    is(decode($cu)->{format}, 'pcu_v1', 'compiled unit format');
    is(PAX::CodeUnitCompiler::_slurp("$root/nope"), '', 'slurp missing file');
    is(PAX::CodeUnitCompiler::_slurp($p), "package Mod;\n1;\n", 'slurp file');
    is(PAX::CodeUnitCompiler::_slurp("$root/unit"), '', 'slurp directory yields empty');

    is(PAX::CodeUnitCompiler::_same_source_path(undef, $p), 0, 'same path: undef left');
    is(PAX::CodeUnitCompiler::_same_source_path($p, undef), 0, 'same path: undef right');
    is(PAX::CodeUnitCompiler::_same_source_path('', $p), 0, 'same path: empty left');
    is(PAX::CodeUnitCompiler::_same_source_path($p, ''), 0, 'same path: empty right');
    is(PAX::CodeUnitCompiler::_same_source_path($p, "$root/unit/../unit/Mod.pm"), 1, 'same path: equivalent');
    is(PAX::CodeUnitCompiler::_same_source_path($p, "$root/nonexistent/x"), 0, 'same path: different');
    is(PAX::CodeUnitCompiler::_same_source_path("$root/ghost/a", "$root/ghost/a"), 1, 'same path: nonexistent equal');
}

is(PAX::CodeUnitCompiler::_bootstrap_has_shared_lexicals(undef), 0, 'lexicals: undef');
is(PAX::CodeUnitCompiler::_bootstrap_has_shared_lexicals(''), 0, 'lexicals: empty');
is(PAX::CodeUnitCompiler::_bootstrap_has_shared_lexicals("my \$x = 1;\n"), 1, 'lexicals: my');
is(PAX::CodeUnitCompiler::_bootstrap_has_shared_lexicals("our \$x = 1;\n"), 0, 'lexicals: our');

# hybrid unit builder
{
    my $src = "package H;\nsub a { 1 }\nsub b { 2 }\n";
    my $u = PAX::CodeUnitCompiler::_hybrid_compiled_unit("$root/H.pm", 'dependency', 'dep/H.pm', 'H', [], [], ['H::a', 'H::', 'H::missing'], $src);
    my $r = decode($u);
    is($r->{residual_mode}, 'module', 'hybrid: unmatched residual subs force module mode');
    is($r->{residual_source}, $src, 'hybrid: module mode carries full source');
    my $u2 = PAX::CodeUnitCompiler::_hybrid_compiled_unit("$root/H.pm", 'dependency', 'dep/H.pm', 'H', [], [], ['H::a'], $src);
    my $r2 = decode($u2);
    is($r2->{residual_mode}, 'per_sub', 'hybrid: per-sub mode');
    like($r2->{residual_sub_sources}{'H::a'}, qr/^sub a \{ 1 \}/, 'hybrid: per-sub source');
    my $u3 = PAX::CodeUnitCompiler::_hybrid_compiled_unit("$root/H.pm", 'dependency', 'dep/H.pm', 'H', [], [], ['H::a'], "package H;\nmy \$shared = 1;\nsub a { \$shared }\n");
    is(decode($u3)->{residual_mode}, 'module', 'hybrid: shared lexicals force module mode');
}

# ---- native shapes -------------------------------------------------------
for my $case (['+', 'add', 5], ['-', 'subtract', -1], ['*', 'multiply', 6], ['>', 'greater_than', 0]) {
    my $shape = PAX::CodeUnitCompiler::_native_i64_binary_leaf_shape("my (\$a, \$b) = \@_; return \$a $case->[0] \$b;");
    is($shape->{op}, $case->[1], "binary leaf $case->[1]");
    is($shape->{smoke_expected}, $case->[2], "binary leaf $case->[1] smoke");
}
is(PAX::CodeUnitCompiler::_native_i64_binary_leaf_shape('return 1;'), undef, 'binary leaf: no args');
is(PAX::CodeUnitCompiler::_native_i64_binary_leaf_shape('my ($a, $b) = @_; return 1;'), undef, 'binary leaf: no return');
is(PAX::CodeUnitCompiler::_native_i64_binary_leaf_shape('my ($a, $b) = @_; return $b + $a;'), undef, 'binary leaf: swapped');
is(PAX::CodeUnitCompiler::_native_i64_binary_leaf_shape('my ($a, $b) = @_; return $a + $c;'), undef, 'binary leaf: wrong right');

my $sum_body = 'my ($n) = @_; my $s = 0; for (my $i = 1; $i <= $n; $i++) { $s += $i; } return $s;';
is(PAX::CodeUnitCompiler::_native_i64_sum_loop_shape($sum_body)->{op}, 'sum_to_n', 'sum loop');
is(PAX::CodeUnitCompiler::_native_i64_sum_loop_shape('return 1;'), undef, 'sum loop: no arg');
is(PAX::CodeUnitCompiler::_native_i64_sum_loop_shape('my ($n) = @_; return 1;'), undef, 'sum loop: no accumulator');
is(PAX::CodeUnitCompiler::_native_i64_sum_loop_shape('my ($n) = @_; my $s = 0; return $s;'), undef, 'sum loop: no loop');
is(PAX::CodeUnitCompiler::_native_i64_sum_loop_shape('my ($n) = @_; my $s = 0; for (my $i = 1; $i <= $n; $i++) { $s += $i; } return 0;'), undef, 'sum loop: no return');

my $mix_body = 'my ($n) = @_; my $a = 0; for (my $i = 0; $i < $n; $i++) { $a += (($i * 13) ^ ($i >> 3)) & 0xFFFF; } return $a;';
is(PAX::CodeUnitCompiler::_native_i64_masked_mix_accum_loop_shape($mix_body)->{op}, 'masked_mix_accumulate', 'mix loop');
is(PAX::CodeUnitCompiler::_native_i64_masked_mix_accum_loop_shape('return 1;'), undef, 'mix loop: no arg');
is(PAX::CodeUnitCompiler::_native_i64_masked_mix_accum_loop_shape('my ($n) = @_; return 1;'), undef, 'mix loop: no accumulator');
is(PAX::CodeUnitCompiler::_native_i64_masked_mix_accum_loop_shape('my ($n) = @_; my $a = 0; return $a;'), undef, 'mix loop: no loop');
is(PAX::CodeUnitCompiler::_native_i64_masked_mix_accum_loop_shape(($mix_body =~ s/return \$a;/return 0;/r)), undef, 'mix loop: no return');

is(PAX::CodeUnitCompiler::_native_shape_from_source_body($sum_body)->{kind}, 'i64_sum_loop', 'shape dispatcher: sum');
is(PAX::CodeUnitCompiler::_native_shape_from_source_body($mix_body)->{kind}, 'i64_masked_mix_accum_loop', 'shape dispatcher: mix');
is(PAX::CodeUnitCompiler::_native_shape_from_source_body('return 1;'), undef, 'shape dispatcher: none');

is(PAX::CodeUnitCompiler::_compile_script_sub_from_source("sub ghost;\n", 'main::ghost', 'ghost'), undef, 'script sub: no body');
is(PAX::CodeUnitCompiler::_compile_script_sub_from_source("sub plain { return 1; }\n", 'main::plain', 'plain'), undef, 'script sub: no shape');
{
    my @subs = PAX::CodeUnitCompiler::_compiled_script_subs('x', "sub add(\$\$) { my (\$a, \$b) = \@_; return \$a + \$b; }\nsub plain { 1 }\nsub sum_to_n { $sum_body }\n");
    is_deeply([map { $_->{name} } @subs], ['add', 'sum_to_n'], 'script subs: only native shapes');
    is($subs[0]{prototype}, '($$)', 'script subs: prototype');
}

# script unit via compile()
{
    my $p = write_file("$root/script/tool.pl", "#!/usr/bin/perl\nsub add { my (\$a, \$b) = \@_; return \$a + \$b; }\nexit main(\@ARGV) unless caller;\nsub main { return 0 }\n");
    my $u = $compiler->compile(path => $p, kind => 'entrypoint', logical_path => 'bin/tool.pl');
    is($u->{packaging}, 'compiled_script_pcu_v1', 'script unit packaging');
    is($u->{logical_path}, 'bin/tool.script.json', 'script unit logical path');
    is(decode($u)->{entry_invocation}{op}, 'call_main_argv_and_exit', 'script unit entry invocation');
    my $p2 = write_file("$root/script/plain", "print 1;\n");
    my $u2 = $compiler->compile(path => $p2, kind => 'entrypoint', logical_path => 'bin/plain');
    is($u2->{logical_path}, 'bin/plain.script.json', 'script unit logical path without extension');
    ok(!exists decode($u2)->{entry_invocation}, 'script unit without main has no entry invocation');
}

# ---- dispatch scripts ----------------------------------------------------
is(PAX::CodeUnitCompiler::_extract_braced_region('abc', 0), undef, 'braced region unterminated');
is(PAX::CodeUnitCompiler::_extract_braced_region('a { b } c } d', 0), 'a { b } c ', 'braced region nested');

is(PAX::CodeUnitCompiler::_unescape_literal(undef), '', 'unescape undef');
is(PAX::CodeUnitCompiler::_unescape_literal('a\"b\'c\\\\d\ne\tf'), "a\"b'c\\d\ne\tf", 'unescape sequences');

is_deeply(PAX::CodeUnitCompiler::_compile_dispatch_action(q{ print Foo::bar(), "\n"; exit 0; }),
    { op => 'print_call', target => 'Foo::bar', args => [], newline => 1, exit_code => 0 }, 'dispatch action: print call');
is_deeply(PAX::CodeUnitCompiler::_compile_dispatch_action(q{ print Foo::bar('a\'b'), "\n"; exit 3; })->{args}, ["a'b"], 'dispatch action: print call with arg');
is_deeply(PAX::CodeUnitCompiler::_compile_dispatch_action(q{ require Foo; print $Foo::VERSION, "\n"; exit 0; }),
    { op => 'print_required_global', require_module => 'Foo', symbol => 'Foo::VERSION', newline => 1, exit_code => 0 }, 'dispatch action: required global');
is(PAX::CodeUnitCompiler::_compile_dispatch_action(q{PAX_EMBEDDED_ASSET_ROOT banner.txt})->{op}, 'print_embedded_asset', 'dispatch action: asset by bare name');
is(PAX::CodeUnitCompiler::_compile_dispatch_action(q{my $r = $ENV{PAX_EMBEDDED_ASSET_ROOT}; "$r/banner.txt"})->{op}, 'print_embedded_asset', 'dispatch action: asset by env');
is(PAX::CodeUnitCompiler::_compile_dispatch_action(q{my $r = $ENV{PAX_EMBEDDED_ASSET_ROOT}; "$r/other"}), undef, 'dispatch action: asset without banner');
is(PAX::CodeUnitCompiler::_compile_dispatch_action(q{system 'x'}), undef, 'dispatch action: unsupported');

is(PAX::CodeUnitCompiler::_compile_dispatch_unknown_action(undef), undef, 'unknown action: undef');
is(PAX::CodeUnitCompiler::_compile_dispatch_unknown_action("  \n"), undef, 'unknown action: blank');
is(PAX::CodeUnitCompiler::_compile_dispatch_unknown_action('die "x";'), undef, 'unknown action: unsupported');
is_deeply(PAX::CodeUnitCompiler::_compile_dispatch_unknown_action(q{ print STDERR "unknown: $cmd\n"; exit 2; }),
    { op => 'stderr_interpolate_cmd', prefix => 'unknown: ', suffix => "\n", exit_code => 2 }, 'unknown action: stderr');

{
    my $ok = <<'PERL';
use strict;
my $cmd = shift @ARGV // "status";
if ($cmd eq 'a') { print Foo::bar(), "\n"; exit 0; }
elsif ($cmd eq 'b') { print Foo::baz('q'), "\n"; exit 1; }
print STDERR "bad $cmd\n"; exit 2;
PERL
    my $d = PAX::CodeUnitCompiler::_extract_dispatch_script($ok);
    is($d->{command_default}, 'status', 'dispatch script: default');
    is($d->{command_default_mode}, 'defined_or', 'dispatch script: // mode');
    is(scalar(@{ $d->{actions} }), 2, 'dispatch script: actions');
    is($d->{unknown_action}{op}, 'stderr_interpolate_cmd', 'dispatch script: unknown action');
    my $or = PAX::CodeUnitCompiler::_extract_dispatch_script(q{my $cmd = shift @ARGV || 'x'; if ($cmd eq 'a') { print Foo::bar(), "\n"; exit 0; }});
    is($or->{command_default_mode}, 'or', 'dispatch script: || mode');
    is($or->{unknown_action}, undef, 'dispatch script: no unknown action');
    is(PAX::CodeUnitCompiler::_extract_dispatch_script('print 1;'), undef, 'dispatch script: no decl');
    is(PAX::CodeUnitCompiler::_extract_dispatch_script(q~my $cmd = shift @ARGV || 'x'; if ($cmd eq 'a') { print 1;~), undef, 'dispatch script: unterminated block');
    is(PAX::CodeUnitCompiler::_extract_dispatch_script(q{my $cmd = shift @ARGV || 'x'; if ($cmd eq 'a') { system 'x'; }}), undef, 'dispatch script: unsupported action');
    is(PAX::CodeUnitCompiler::_extract_dispatch_script(q{my $cmd = shift @ARGV || 'x'; print 1;}), undef, 'dispatch script: no actions');

    my $p = write_file("$root/disp/app.pl", $ok);
    my $u = $compiler->compile(path => $p, kind => 'entrypoint', logical_path => 'bin/app.pl');
    is($u->{packaging}, 'compiled_dispatch_script_pcu_v1', 'dispatch unit via compile');
    is($u->{logical_path}, 'bin/app.dispatch.json', 'dispatch unit logical path');
    my $p2 = write_file("$root/disp/app2", $ok);
    is($compiler->compile(path => $p2, kind => 'entrypoint', logical_path => 'bin/app2')->{logical_path}, 'bin/app2.dispatch.json', 'dispatch unit logical path without extension');
    is(PAX::CodeUnitCompiler::_compiled_dispatch_script_unit($p, 'entrypoint', 'x', 'print 1;'), undef, 'dispatch unit: none');
}

# ---- service dispatch ----------------------------------------------------
{
    my $svc = <<'PERL';
# main()
# entry
sub main {
    my @argv = @_;
    my $cmd = shift @argv || 'version';
    my $APP_VERSION = '1.2\'3';
    require My::App; require My::Server;
    return My::App->build_custom_app(asset_root => 'x');
}
PERL
    my $p = write_file("$root/svc/svc.pl", $svc);
    my $u = $compiler->compile(path => $p, kind => 'entrypoint', logical_path => 'bin/svc.pl');
    is($u->{packaging}, 'compiled_service_dispatch_pcu_v1', 'service unit via compile');
    my $r = decode($u);
    is($r->{builder_method}, 'build_custom_app', 'service unit builder method');
    is($r->{version}, "1.2'3", 'service unit version');
    is($u->{logical_path}, 'bin/svc.service.json', 'service logical path');
    (my $default = $svc) =~ s/->build_custom_app\(asset_root/->x(root/;
    is(decode(PAX::CodeUnitCompiler::_compiled_service_dispatch_unit($p, 'entrypoint', 'bin/svc', $default))->{builder_method}, 'build_psgi_app', 'service default builder');
    is(PAX::CodeUnitCompiler::_compiled_service_dispatch_unit($p, 'entrypoint', 'bin/svc', $default)->{logical_path}, 'bin/svc.service.json', 'service logical path no extension');
    is(PAX::CodeUnitCompiler::_compiled_service_dispatch_unit($p, 'e', 'l', 'x'), undef, 'service: no main');
    is(PAX::CodeUnitCompiler::_compiled_service_dispatch_unit($p, 'e', 'l', 'sub main {}'), undef, 'service: no cmd');
    is(PAX::CodeUnitCompiler::_compiled_service_dispatch_unit($p, 'e', 'l', "sub main { my \$cmd = shift \@argv || 'version'; }"), undef, 'service: no requires');
    is(PAX::CodeUnitCompiler::_compiled_service_dispatch_unit($p, 'e', 'l', "sub main { my \$cmd = shift \@argv || 'version'; require A; require B; }"), undef, 'service: no version');
}

# ---- lib / module discovery ---------------------------------------------
is_deeply([PAX::CodeUnitCompiler::_used_modules_from_source("use A::B;\nuse A::B (1);\nuse C [2];\nuse D 1;\n")], ['A::B', 'C'], 'used modules');

is(PAX::CodeUnitCompiler::_normalize_lib_path(undef, '/b'), '', 'normalize lib: undef');
is(PAX::CodeUnitCompiler::_normalize_lib_path('', '/b'), '', 'normalize lib: empty');
is(PAX::CodeUnitCompiler::_normalize_lib_path('  ', '/b'), '', 'normalize lib: blank');
is(PAX::CodeUnitCompiler::_normalize_lib_path('/b/lib', '/b'), '/b/lib', 'normalize lib: under bin');
is(PAX::CodeUnitCompiler::_normalize_lib_path('../lib', '/b/bin'), File::Spec->rel2abs('../lib', '/b/bin'), 'normalize lib: parent');
is(PAX::CodeUnitCompiler::_normalize_lib_path('lib', '/b/bin'), File::Spec->rel2abs('lib', '.'), 'normalize lib: relative');

is_deeply([PAX::CodeUnitCompiler::_use_lib_paths_from_source(qq{use lib q'';\nuse lib q' ';\nuse lib "/b/lib";\nuse lib '../x';\n}, '/b/bin/app.pl')],
    ['/b/lib', File::Spec->rel2abs('../x', '/b/bin')], 'use lib paths');

{
    my $bin = "$root/roots/bin";
    make_path($bin, "$root/roots/lib", "$root/roots/extra");
    local @INC = (undef, '', sub { }, "$root/roots/extra", "$root/roots/extra", "$root/roots/missing");
    my @r = PAX::CodeUnitCompiler::_module_search_roots_from_source("use lib '$root/roots/extra';\n", "$bin/app.pl");
    is_deeply(\@r, [File::Spec->catdir($bin, File::Spec->updir, 'lib'), "$root/roots/extra"], 'module roots deduped and filtered');

    write_file("$root/roots/lib/Ver/Mod.pm", "package Ver::Mod;\nour \$VERSION = '9.8\\'7';\n1;\n");
    write_file("$root/roots/lib/NoVer.pm", "package NoVer;\n1;\n");
    write_file("$root/roots/lib/Empty.pm", '');
    make_path("$root/roots/lib/DirMod.pm");
    write_file("$root/roots/extra/Empty.pm", "package Empty;\nour \$VERSION = '1';\n");
    my $roots = ["$root/roots/lib", "$root/roots/extra"];
    is(PAX::CodeUnitCompiler::_module_version_from_roots('Ver::Mod', $roots), "9.8'7", 'module version');
    is(PAX::CodeUnitCompiler::_module_version_from_roots('NoVer', $roots), undef, 'module without version');
    is(PAX::CodeUnitCompiler::_module_version_from_roots('Missing', $roots), undef, 'missing module version');
    like(PAX::CodeUnitCompiler::_module_source_from_roots('Empty', $roots), qr/VERSION/, 'empty module in first root skipped');
    is(PAX::CodeUnitCompiler::_module_source_from_roots('DirMod', $roots), undef, 'directory candidate skipped');
    my $sock = IO::Socket::UNIX->new(Local => "$root/roots/lib/SockMod.pm", Listen => 1);
    SKIP: {
        skip 'cannot create unix socket', 1 if !$sock;
        is(PAX::CodeUnitCompiler::_module_source_from_roots('SockMod', $roots), undef, 'unopenable candidate skipped');
    }
}

# ---- entry command helpers ----------------------------------------------
is(PAX::CodeUnitCompiler::_entry_command_sub_name('sub _x_entry_command {}'), '_x_entry_command', 'entry sub: underscore form');
is(PAX::CodeUnitCompiler::_entry_command_sub_name('sub app_entry_point_command {}'), 'app_entry_point_command', 'entry sub: entry_point_command');
is(PAX::CodeUnitCompiler::_entry_command_sub_name('sub appentrypoint_command {}'), 'appentrypoint_command', 'entry sub: entrypoint_command');
is(PAX::CodeUnitCompiler::_entry_command_sub_name('sub app_entry_command {}'), 'app_entry_command', 'entry sub: entry_command');
is(PAX::CodeUnitCompiler::_entry_command_sub_name('sub other {}'), undef, 'entry sub: none');
is(PAX::CodeUnitCompiler::_is_entry_command_sub(undef), 0, 'is entry: undef');
is(PAX::CodeUnitCompiler::_is_entry_command_sub(''), 0, 'is entry: empty');
is(PAX::CodeUnitCompiler::_is_entry_command_sub('_app_entry_command'), 1, 'is entry: yes');
is(PAX::CodeUnitCompiler::_is_entry_command_sub('other'), 0, 'is entry: no');

is_deeply(PAX::CodeUnitCompiler::_entry_command_capture(q{sub _a_entry_command { return $ENV{A_ENTRY} || 'abc'; }}),
    { env => 'A_ENTRY', fallback => 'abc', sub_name => '_a_entry_command' }, 'entry capture: from sub body');
is(scalar(PAX::CodeUnitCompiler::_entry_command_capture(q{sub other { 1 }}, 'x', 'other', 'Sym::other')), undef, 'entry capture: no env');
is_deeply(PAX::CodeUnitCompiler::_entry_command_capture(q{$ENV{B_ENTRY} ||= $0;}, 'bin/app.pl'),
    { env => 'B_ENTRY', fallback => 'app', sub_name => 'entry_command' }, 'entry capture: assignment fallback');
is(PAX::CodeUnitCompiler::_extract_entrypoint_assignment_fallback(q{$ENV{B} ||= $0;}, undef)->{fallback}, 'app', 'assignment fallback: empty logical path');
is(PAX::CodeUnitCompiler::_extract_entrypoint_assignment_fallback(q{$ENV{B} ||= "lit\n";}, 'x')->{fallback}, "lit\n", 'assignment fallback: literal');
is(PAX::CodeUnitCompiler::_extract_entrypoint_assignment_fallback(q{$ENV{B} ||= foo();}, 'x')->{fallback}, '', 'assignment fallback: none');

is(PAX::CodeUnitCompiler::_entry_command_from_env_assignment('nothing', 'x'), undef, 'env assignment: none');
is(PAX::CodeUnitCompiler::_entry_command_from_env_assignment(q{$ENV{HOMEISH} ||= 'x';}, 'x'), undef, 'env assignment: not ENTRYPOINT');
is(PAX::CodeUnitCompiler::_entry_command_from_env_assignment(q{$ENV{APP_ENTRYPOINT} ||= 'x';}, 'x')->{sub_name}, 'entrypoint', 'env assignment: default sub name');
is(PAX::CodeUnitCompiler::_entry_command_from_env_assignment(q{sub _q_entry_command {1} $ENV{APP_ENTRYPOINT} ||= 'x';}, 'x')->{sub_name}, '_q_entry_command', 'env assignment: detected sub name');

{
    my $bin = "$root/entry/bin";
    make_path($bin, "$root/entry/lib/Ent");
    write_file("$root/entry/lib/Ent/Cmd.pm", "package Ent::Cmd;\nsub _x_entry_command { return \$ENV{ENT_CMD} || 'entcmd'; }\n1;\n");
    write_file("$root/entry/lib/Ent/Plain.pm", "package Ent::Plain;\nsub other { 1 }\n1;\n");
    my $src = "use strict;\nuse Ent::Missing;\nuse Ent::Plain;\nuse Ent::Cmd;\n";
    my $e = PAX::CodeUnitCompiler::_entry_command_from_entrypoint($src, "$bin/app.pl", 'bin/app.pl');
    is($e->{env}, 'ENT_CMD', 'entry from entrypoint: module entry');
    is($e->{sub_name}, 'Ent::Cmd::_x_entry_command', 'entry from entrypoint: symbolic name');
    my $e2 = PAX::CodeUnitCompiler::_entry_command_from_entrypoint("use Ent::Plain;\n\$ENV{APP_ENTRYPOINT} ||= 'z';\n", "$bin/app.pl", 'bin/app.pl');
    is($e2->{env}, 'APP_ENTRYPOINT', 'entry from entrypoint: env assignment');
    is(PAX::CodeUnitCompiler::_entry_command_from_entrypoint("use Ent::Plain;\n", "$bin/app.pl", 'bin/app.pl'), undef, 'entry from entrypoint: none');
}

done_testing;
