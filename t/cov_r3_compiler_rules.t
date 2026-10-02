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

t/cov_r3_compiler_rules.t - modules whose load-time statements the compiler cannot model

=head1 WHY IT EXISTS

The unit compiler models subs and the initializers before the first sub. A module
that registers routes, declares a second package, or keeps a lookup table after its
subs would silently lose that code in a standalone binary (the dashboard's web
routes answered 404 and `restart` died with "Unknown file name"). These tests pin
the two rules that keep such modules correct: ship as source, or load whole.

=head1 DESCRIPTION

Covers C<_has_toplevel_statements_after_subs>, C<_residual_subs_use_file_lexicals>
and their effect on C<compile> and C<_hybrid_compiled_unit>.

=cut

my $root = tempdir('pax-r3-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_module($name, $text)
# Writes a module file under the temp root. Input: file name and text. Output: path.
sub write_module {
    my ($name, $text) = @_;
    my $path = File::Spec->catfile($root, $name);
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh or die "cannot close $path: $!";
    return $path;
}

my $has = \&PAX::CodeUnitCompiler::_has_toplevel_statements_after_subs;

# Statements after the first sub are detected; text that only looks like code is not.
is($has->("package P;\nuse strict;\nmy \$x = 1;\n1;\n"), 0, 'a module without subs has nothing after them');
is($has->("package P;\nsub a { return 1 }\n1;\n"), 0, 'subs followed only by a true value are fine');
is($has->("package P;\nsub a { return 1 }\nget '/x' => sub { 1 };\n1;\n"), 1, 'a route registration after a sub is a top-level statement');
is($has->("package P;\nsub a { return 1 }\npackage P::Other;\nsub b { 2 }\n1;\n"), 1, 'a second package after a sub is a top-level statement');
is($has->("package P;\nsub a { return 1 }\nmy %TABLE = (a => 1);\nour \$LATE = 2;\n1;\n"), 0, 'late my/our declarations are left to the lexical rule');
is($has->("package P;\nsub a {\n    return <<'EOT';\nprint 1;\nEOT\n}\n1;\n"), 0, 'single-quoted heredoc text at column zero is ignored');
is($has->("package P;\nsub a {\n    return <<\"EOT\";\nprint 2;\nEOT\n}\n1;\n"), 0, 'double-quoted heredoc text at column zero is ignored');
is($has->("package P;\nsub a {\n    return <<EOT;\nprint 3;\nEOT\n}\n1;\n"), 0, 'bare heredoc text at column zero is ignored');
is($has->("package P;\nsub a {\n    return <<~EOT;\nprint 4;\n    EOT\n}\n1;\n"), 0, 'indented heredoc terminators end the heredoc');
is($has->("package P;\nsub a { 1 }\n# a comment\n\n}\n)\n1;\n__END__\nprint 'ignored after END';\n"), 0, 'comments, closers and text after __END__ are ignored');
is($has->("package P;\nsub a { 1 }\n=pod\n\nprint 'pod';\n\n=cut\n1;\n"), 0, 'POD is ignored');

# Late file lexicals only matter when a residual sub mentions them.
my $uses = \&PAX::CodeUnitCompiler::_residual_subs_use_file_lexicals;
my $src = "package P;\nsub a { 1 }\nmy %TABLE = (a => 1);\nmy \$count = 0;\nmy (\$left, \@right) = (1, 2);\nsub b { 1 }\n1;\n";
is($uses->($src, { 'P::b' => 'sub b { return $TABLE{x} }' }), 1, 'a residual sub using a hash lexical needs the whole module');
is($uses->($src, { 'P::b' => 'sub b { return $count++ }' }), 1, 'a residual sub using a scalar lexical needs the whole module');
is($uses->($src, { 'P::b' => 'sub b { return @right }' }), 1, 'a residual sub using a list-declared lexical needs the whole module');
is($uses->($src, { 'P::b' => 'sub b { return 5 }' }), 0, 'a residual sub that uses none keeps lazy compilation');
is($uses->($src, {}), 0, 'no residual subs means nothing to scope');
is($uses->("package P;\nsub a { 1 }\n1;\n", { 'P::a' => 'sub a { return $anything }' }), 0, 'a module without file lexicals never needs the whole module');

# compile() ships such a module as source, and a hybrid unit loads whole when it must.
my $routes = write_module('Routes.pm', "package Routes;\nuse strict;\nsub build { return 1 }\nget '/' => sub { 1 };\n1;\n");
my $unit = PAX::CodeUnitCompiler->new->compile(path => $routes, kind => 'lib', logical_path => 'lib/Routes.pm');
is($unit->{packaging}, 'source_payload_fallback', 'a module with late statements ships as source');
is($unit->{fallback_reason}, 'unsupported_toplevel_statements', 'the fallback reason names the cause');

my $late = write_module('Late.pm', "package Late;\nuse strict;\nsub plain { return 1 }\nmy %TABLE = (a => 1);\nsub lookup { my (\$k) = \@_; return \$TABLE{\$k} }\n1;\n");
open my $lfh, '<', $late or die $!;
my $late_source = do { local $/; <$lfh> };
close $lfh;
my $hybrid = PAX::CodeUnitCompiler::_hybrid_compiled_unit($late, 'lib', 'lib/Late.pm', 'Late', [], [], ['Late::lookup'], $late_source);
is(JSON::PP->new->decode($hybrid->{bytes})->{residual_mode}, 'module', 'a residual sub using a late lexical loads the whole module');
my $plain = write_module('Plain.pm', "package Plain;\nuse strict;\nsub plain { return 1 }\nmy %TABLE = (a => 1);\nsub other { return 2 }\n1;\n");
open my $pfh, '<', $plain or die $!;
my $plain_source = do { local $/; <$pfh> };
close $pfh;
my $lazy = PAX::CodeUnitCompiler::_hybrid_compiled_unit($plain, 'lib', 'lib/Plain.pm', 'Plain', [], [], ['Plain::other'], $plain_source);
is(JSON::PP->new->decode($lazy->{bytes})->{residual_mode}, 'per_sub', 'a residual sub that does not use the lexical stays lazy');

done_testing();
