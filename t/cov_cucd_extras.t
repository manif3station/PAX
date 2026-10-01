use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::CodeUnitCompiler;

=pod

=head1 NAME

t/cov_cucd_extras.t - hand-written shape cases and helpers for the code-unit compiler

=head1 WHY IT EXISTS

A few matchers in C<_compile_simple_transform_sub_from_source> need more than literal
fragments (captured message text, a sibling entry-command sub, whole-body regexes),
and the entry-command helpers at the end of the matcher chain have no other direct
callers in the test suite.

=head1 DESCRIPTION

Covers the unknown-command message matcher, the which-command matcher with and
without an entry-command sub, the gzip/base64 whole-body matchers, C<return 1>,
C<_entry_command_capture>, C<_extract_entrypoint_assignment_fallback>,
C<_package_tail_is> and C<_calls_class_tail>.

=cut

# match($source, $name)
# Runs the matcher chain for a named sub in a source text.
# Input: source and sub name. Output: matcher record or undef.
sub match {
    my ($source, $name) = @_;
    return PAX::CodeUnitCompiler::_compile_simple_transform_sub_from_source($source, $name, "Demo::Mod::$name");
}

# unknown_command_message: message text is taken from the source.
my $msg_src = <<'SRC';
package Demo::Mod;
sub unknown_command_message {
    my ($self, $command) = @_;
    my $message = "Unknown dashboard command '$command'\nTry again";
    return $message . top_level_suggestions($command);
}
1;
SRC
my $msg = match($msg_src, 'unknown_command_message');
is($msg->{op}, 'suggest_unknown_command_message', 'unknown command message matches');
is($msg->{message_head}, 'Unknown dashboard command ', 'message head comes from the source');
is($msg->{message_tail}, "\nTry again", 'message tail has newline escapes expanded');
(my $no_msg_src = $msg_src) =~ s/my \$message = [^\n]*\n/my \$message = 1; # Unknown dashboard command\n/;
is(match($no_msg_src, 'unknown_command_message'), undef, 'unknown command message without the message assignment falls through');

(my $no_sugg_src = $msg_src) =~ s/top_level_suggestions/other_helper/;
is(match($no_sugg_src, 'unknown_command_message'), undef, 'unknown command message without the suggestions helper does not match');
(my $no_text_src = $msg_src) =~ s/Unknown dashboard command/Something else/;
is(match($no_text_src, 'unknown_command_message'), undef, 'unknown command message without its marker text does not match');

# run_which_command with and without a sibling entry-command sub.
my $which_body = <<'SRC';
sub run_which_command {
    GetOptionsFromArray(\@args);
    my $paths = _build_paths();
    my $t = _locate_target();
    _command_exec(@x);
}
SRC
my $which_plain = match("package Demo::Mod;\n$which_body\n1;\n", 'run_which_command');
is($which_plain->{entry_command_method}, 'Demo::Mod::entry_command', 'which command defaults the entry command sub');
my $which_entry = match("package Demo::Mod;\nsub _app_entry_command { return \$ENV{APP_X} || 'x'; }\n$which_body\n1;\n", 'run_which_command');
is($which_entry->{entry_command_method}, 'Demo::Mod::_app_entry_command', 'which command uses the detected entry command sub');

# Whole-body gzip/base64 matchers and return_true.
my $enc = match("package Demo::Mod;\nsub enc { my (\$text) = \@_; return if !defined \$text; gzip \\\$text => \\my \$zipped or die \"gzip failed\"; return encode_base64(\$zipped, ''); }\n1;\n", 'enc');
is($enc->{op}, 'gzip_base64_encode', 'gzip encode shape matches');
is($enc->{error_message}, 'gzip failed', 'gzip encode keeps its error message');
my $dec = match("package Demo::Mod;\nsub dec { my (\$token) = \@_; return if !defined \$token || \$token eq ''; my \$zipped = decode_base64(\$token); gunzip \\\$zipped => \\my \$text or die \"gunzip failed\"; return \$text; }\n1;\n", 'dec');
is($dec->{op}, 'gzip_base64_decode', 'gzip decode shape matches');
is($dec->{error_message}, 'gunzip failed', 'gzip decode keeps its error message');
my $true = match("package Demo::Mod;\nsub yes { return 1 }\n1;\n", 'yes');
is($true->{op}, 'return_true', 'return 1 matches');
is(match("package Demo::Mod;\nsub no_match { return 2 }\n1;\n", 'no_match'), undef, 'return 2 matches nothing');

# _entry_command_capture and its fallback.
my $capture = PAX::CodeUnitCompiler::_entry_command_capture("sub _x_entry_command { return \$ENV{XAPP} || 'xdef'; }\n", 'bin/x.pl');
is_deeply($capture, { env => 'XAPP', fallback => 'xdef', sub_name => '_x_entry_command' }, 'entry command body yields env and fallback');
$capture = PAX::CodeUnitCompiler::_entry_command_capture("sub _x_entry_command { return 1; }\n\$ENV{YAPP} ||= 'ydef';\n", 'bin/x.pl', undef, 'sym');
is_deeply($capture, { env => 'YAPP', fallback => 'ydef', sub_name => 'sym' }, 'sub without env falls back to the assignment form');
$capture = PAX::CodeUnitCompiler::_entry_command_capture("\$ENV{ZAPP} ||= \$0;\n", 'bin/zed.pl');
is_deeply($capture, { env => 'ZAPP', fallback => 'zed', sub_name => 'entry_command' }, 'no entry sub uses the assignment form and default name');
is(PAX::CodeUnitCompiler::_entry_command_capture("sub plain { 1 }\n", 'x.pl'), undef, 'nothing to capture yields undef');
$capture = PAX::CodeUnitCompiler::_entry_command_capture("sub _q_entry_command { return \$ENV{QAPP} // 'qdef'; }\n", 'x.pl', '_q_entry_command');
is_deeply($capture, { env => 'QAPP', fallback => 'qdef', sub_name => '_q_entry_command' }, 'explicit sub name is used as given');
is(PAX::CodeUnitCompiler::_entry_command_capture("sub other { 1 }\n", 'x.pl', 'missing_sub'), undef, 'explicit sub name that is absent from the source yields undef');
$capture = PAX::CodeUnitCompiler::_entry_command_capture("\$ENV{PAPP} ||= 'pdef';\n", 'x.pl', undef, 'given_symbol');
is($capture->{sub_name}, 'given_symbol', 'explicit symbolic name wins without an entry sub');
is(PAX::CodeUnitCompiler::_entry_command_capture("sub q { 1 }\n", 'x.pl', '', 'named'), undef, 'empty sub name is ignored');

is_deeply(PAX::CodeUnitCompiler::_extract_entrypoint_assignment_fallback("\$ENV{A} ||= \$0;\n", undef), { env => 'A', fallback => 'app' }, 'undefined logical path uses app');
is_deeply(PAX::CodeUnitCompiler::_extract_entrypoint_assignment_fallback("\$ENV{A} ||= \$0;\n", 'dir/tool.pl'), { env => 'A', fallback => 'tool' }, 'logical path basename without extension');
is_deeply(PAX::CodeUnitCompiler::_extract_entrypoint_assignment_fallback("\$ENV{A} ||= \"q\\\\n\";\n", 'x'), { env => 'A', fallback => "q\n" }, 'quoted literal is unescaped');
is_deeply(PAX::CodeUnitCompiler::_extract_entrypoint_assignment_fallback("\$ENV{A} ||= compute();\n", 'x'), { env => 'A', fallback => '' }, 'unrecognised rhs gives an empty fallback');
is(PAX::CodeUnitCompiler::_extract_entrypoint_assignment_fallback("no env here\n", 'x'), undef, 'no assignment yields undef');

# _package_tail_is and _calls_class_tail.
is(PAX::CodeUnitCompiler::_package_tail_is(undef, 'X'), 0, 'undefined package never matches');
is(PAX::CodeUnitCompiler::_package_tail_is('A::B', undef), 1, 'undefined tail matches any package');
is(PAX::CodeUnitCompiler::_package_tail_is('A::B', ''), 1, 'empty tail matches any package');
is(PAX::CodeUnitCompiler::_package_tail_is('A::B', 'B'), 1, 'tail match');
is(PAX::CodeUnitCompiler::_package_tail_is('A::B', 'C'), 0, 'tail mismatch');

is(PAX::CodeUnitCompiler::_calls_class_tail(undef, 'X', 'm'), 0, 'undefined body is not a call');
is(PAX::CodeUnitCompiler::_calls_class_tail('x', undef, 'm'), 0, 'undefined class tail is not a call');
is(PAX::CodeUnitCompiler::_calls_class_tail('A::Foo->bar(1)', 'Foo', 'bar'), 1, 'qualified method call');
is(PAX::CodeUnitCompiler::_calls_class_tail('A::Foo->baz(1)', 'Foo', 'bar'), 0, 'different method is not a call');
is(PAX::CodeUnitCompiler::_calls_class_tail('my $x = Foo;', 'Foo', ''), 1, 'empty method checks the bare class name');
is(PAX::CodeUnitCompiler::_calls_class_tail('my $x = Foo;', 'Foo'), 1, 'missing method checks the bare class name');
is(PAX::CodeUnitCompiler::_calls_class_tail('my $x = Bar;', 'Foo'), 0, 'absent class name');

done_testing;
