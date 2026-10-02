use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::CodeUnitCompiler;

=pod

=head1 NAME

t/op_drift_guard.t - hand-written handlers are only trusted while they still match the real sub

=head1 WHY IT EXISTS

A compiled-sub handler is a copy of application code taken at one point in time. When the
application later gained arguments, helper calls and security checks (a dry-run flag, a
constant-time password compare, a required clock argument), the stale copy silently dropped
them: the standalone binary ignored C<--dry-run> and compared password hashes with C<ne>.
The compiler now keeps a handler only when every behaviour token of the real body is
accounted for by the handler text or its record; otherwise the sub keeps its real source.

=head1 DESCRIPTION

Covers token extraction, the trust decision (accept, reject, unreadable body, packaged-layout
adapters), the clock-helper tz contract, and the two pipeline choke points that apply the guard.

=head1 HOW TO RUN

  prove -l t/op_drift_guard.t

=cut

# ---- _source_behavior_tokens
{
    my @tokens = PAX::CodeUnitCompiler::_source_behavior_tokens(<<'PL');
    my ($self, %args) = @_;
    # ->commented_away( ignored => 1 )
    my $x = $self->_helper($args{dry_run});
    $self->save( mode => 'x', verbose => 1 );
    return shift->new(name => $x);
PL
    is_deeply(\@tokens, [qw(_helper dry_run mode save verbose)], 'tokens are methods, helper calls, named args and hash keys; comments and plain words are skipped');
}

# ---- _handler_text_for_op
{
    local %PAX::CodeUnitCompiler::HANDLER_TEXT_FOR_OP;
    local $INC{'PAX/StandaloneRuntime.pm'} = '/nonexistent/StandaloneRuntime.pm';
    is(PAX::CodeUnitCompiler::_handler_text_for_op('anything'), undef, 'an unreadable runtime file yields no handlers');
    is(PAX::CodeUnitCompiler::_handler_text_for_op(''), '', 'the empty op has empty text');
}
{
    local %PAX::CodeUnitCompiler::HANDLER_TEXT_FOR_OP;
    delete local $INC{'PAX/StandaloneRuntime.pm'};
    like(PAX::CodeUnitCompiler::_handler_text_for_op('return_literal'), qr/\$impl/, 'handlers are found next to the compiler when the runtime is not loaded');
    is(PAX::CodeUnitCompiler::_handler_text_for_op('no_such_op'), undef, 'unknown ops have no handler');
}

# ---- _handler_accounts_for_source
{
    local %PAX::CodeUnitCompiler::HANDLER_TEXT_FOR_OP = (
        '' => '',
        known => '$impl = sub { $self->_known(dry_run => 1) };',
        adapt => "# PAX_ADAPTS_PACKAGED_LAYOUT: relocates data\n\$impl = sub { 1 };",
    );
    my $ok = sub { PAX::CodeUnitCompiler::_handler_accounts_for_source(@_) };
    my $source = "sub run {\n    my (\$self, %args) = \@_;\n    \$self->_known(dry_run => 1);\n}\n";
    ok($ok->({ op => 'unlisted' }, $source, 'run'), 'an op without a handler is not second-guessed');
    ok($ok->({ op => 'known' }, $source, 'run'), 'a handler that mentions everything the body does is trusted');
    my $drifted = "sub run {\n    my (\$self) = \@_;\n    \$self->_known(dry_run => 1);\n    \$self->_sweep_sessions();\n}\n";
    ok(!$ok->({ op => 'known' }, $drifted, 'run'), 'a body that grew a new call is no longer matched by the old handler');
    ok(!$ok->({ op => 'known' }, "# no such sub\n", 'run'), 'a body that cannot be read cannot be verified');
    ok($ok->({ op => 'adapt' }, $drifted, 'run'), 'a packaged-layout adapter is meant to differ and stays trusted');
    ok($ok->({ op => 'known', sweep_method => 'Pkg::_sweep_sessions' }, $drifted, 'run'), 'tokens may be accounted for by the record that parameterises the handler');
    ok(!$ok->({ op => 'known', sweep_method => [ '_sweep_sessions' ] }, $drifted, 'run'), 'references in the record do not count');
    ok($ok->({}, $source, 'run'), 'a record without an op is left alone');
}

# ---- _now_iso8601_tz
{
    my $tz = sub { PAX::CodeUnitCompiler::_now_iso8601_tz(@_) };
    is($tz->('my $x = _now_iso8601( tz => "utc" );'), 'utc', 'utc literal');
    is($tz->("my \$x = _now_iso8601(tz => 'local');"), 'local', 'local literal');
    is($tz->('_now_iso8601(tz=>"utc"); _now_iso8601( tz => "utc" );'), 'utc', 'agreeing calls');
    is($tz->('_now_iso8601(tz=>"utc"); _now_iso8601(tz=>"local");'), undef, 'disagreeing calls cannot share one handler argument');
    is($tz->('_now_iso8601(tz => $zone);'), undef, 'a dynamic tz cannot be copied');
    is($tz->('_now_iso8601(tz => "utc"); _now_iso8601();'), undef, 'a mix of explicit and bare calls is ambiguous');
    is($tz->('my $x = _now_iso8601();'), '', 'a helper that takes no argument needs none passed');
    is($tz->('return 1;'), '', 'no call at all');
}

# ---- _compile_simple_transform_sub_from_source passes the tz through
{
    no warnings 'redefine';
    my $record;
    local *PAX::CodeUnitCompiler::_simple_transform_record = sub { return $record && { %$record } };
    my $run = sub { PAX::CodeUnitCompiler::_compile_simple_transform_sub_from_source("sub s {\n$_[0]\n}\n", 's', 'Pkg::s') };
    $record = undef;
    is($run->(''), undef, 'no matched handler, no record');
    $record = { op => 'x' };
    is_deeply($run->(''), { op => 'x' }, 'a handler that does not use the clock is untouched');
    $record = { op => 'x', now_method => 'Pkg::_now_iso8601' };
    is($run->('_now_iso8601( tz => "utc" );')->{now_tz}, 'utc', 'the real tz is handed to the handler');
    ok(!exists $run->('_now_iso8601();')->{now_tz}, 'a bare helper call stays bare');
    is($run->('_now_iso8601(tz=>"utc"); _now_iso8601(tz=>"local");'), undef, 'ambiguous clock use keeps the real source');
}

# ---- the two choke points apply the guard
{
    no warnings 'redefine';
    local %PAX::CodeUnitCompiler::HANDLER_TEXT_FOR_OP = ('' => '', known => '$impl = sub { $self->_known() };');
    my $fresh = "sub s {\n    \$self->_known();\n}\n";
    my $stale = "sub s {\n    \$self->_known();\n    \$self->_brand_new();\n}\n";
    local *PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped = sub { return { name => 's', op => 'known' } };
    ok(PAX::CodeUnitCompiler::_compile_declared_sub_from_source($fresh, 'Pkg::s'), 'declared sub keeps its handler while it matches');
    is(PAX::CodeUnitCompiler::_compile_declared_sub_from_source($stale, 'Pkg::s'), undef, 'declared sub falls back to source once the body drifts');
    local *PAX::CodeUnitCompiler::_custom_sub_from_source = sub { return { name => 's', op => 'known' } };
    ok(PAX::CodeUnitCompiler::_compile_sub({ name => 'Pkg::s' }, $fresh), 'captured sub keeps its handler while it matches');
    is(PAX::CodeUnitCompiler::_compile_sub({ name => 'Pkg::s' }, $stale), undef, 'captured sub falls back to source once the body drifts');
}

done_testing();
