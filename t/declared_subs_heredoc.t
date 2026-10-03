use strict;
use warnings;
use Test::More;
use PAX::CodeUnitCompiler;

=pod

=head1 NAME

t/declared_subs_heredoc.t - subs declared inside here-document bodies are not declarations of the enclosing package

=head1 DESCRIPTION

A module that generates another package from a here-document (a page sandpit, a helper script wrapper)
contains C<sub NAME {> text that is not a sub of the module itself. The compiler must not treat those as
declared subs, or it installs phantom subs the interpreter never defines.

=cut

my $source = <<'SRC';
package Demo;
sub real_one { return 1 }
sub generator {
    return <<"PERL";
package Other;
sub phantom_a { 1 }
PERL
}
sub quoted {
    return <<'PERL';
sub phantom_b { 1 }
PERL
}
sub indented {
    return <<~EOT;
        sub phantom_c { 1 }
        EOT
}
sub real_two { return 2 }
SRC

is_deeply([PAX::CodeUnitCompiler::_declared_subs($source, 'Demo')],
    [map { "Demo::$_" } qw(real_one generator quoted indented real_two)], 'heredoc bodies are skipped');
is_deeply([PAX::CodeUnitCompiler::_declared_subs("package D;\nsub a { 1 }\nmy \$x = <<'EOT';\nsub never { }\n", 'D')],
    [qw(D::a D::never)], 'an unterminated heredoc leaves the source untouched');
done_testing;
