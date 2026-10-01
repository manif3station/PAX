use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::CodeUnitCompiler;

=pod

=head1 NAME

t/cov_r2cuc_helpers.t - last coverage gaps of the code-unit compiler

=head1 WHY IT EXISTS

Round two of the coverage work removed dead defensive code from
C<PAX::CodeUnitCompiler> and left a few reachable outcomes that only need a
direct call: the simple-transform fallback of the declared-sub compiler, the
path resolver fallback and the entry-command capture without a named sub.

=head1 DESCRIPTION

Each case calls the compiler in process with a synthetic source string or a
locally replaced C<Cwd::abs_path>, and asserts the observable result.

=cut

my $C = 'PAX::CodeUnitCompiler';

# A sub that only a simple-transform recogniser (not a custom shape) accepts.
my $source = "package Demo::T;\nsub twice { return JSON::XS->new->utf8->decode(\$_[0]); }\n1;\n";
my $record = PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped($source, 'Demo::T::twice');
is($record && $record->{op}, 'json_xs_decode', 'declared sub falls through to the simple transform recogniser');

# The path resolver returns the input when Cwd cannot resolve it.
{
    no warnings 'redefine';
    # Stand-in resolver that always fails, to force the fallback.
    local *PAX::CodeUnitCompiler::abs_path = sub { return undef };
    is(PAX::CodeUnitCompiler::_real_path('/no/such/dir/x'), '/no/such/dir/x', 'real path falls back to the given path');
    is(PAX::CodeUnitCompiler::_same_source_path('/no/such/a', '/no/such/a'), 1, 'same source path compares unresolved paths');
    is(PAX::CodeUnitCompiler::_same_source_path('/no/such/a', '/no/such/b'), 0, 'same source path distinguishes unresolved paths');
}
is(PAX::CodeUnitCompiler::_real_path('/'), '/', 'real path resolves an existing path');

# Entry command capture without any recognisable entry sub falls back to the generic name.
my $capture = PAX::CodeUnitCompiler::_entry_command_capture("\$ENV{APP_ENTRYPOINT} ||= 'tool';\n", 'bin/tool.pl');
is($capture && $capture->{sub_name}, 'entry_command', 'entry command capture names itself entry_command without a sub');
is($capture && $capture->{fallback}, 'tool', 'entry command capture keeps the env fallback');
is(PAX::CodeUnitCompiler::_entry_command_capture("sub x { 1 }\n"), undef, 'entry command capture is empty without an env assignment');

# The loop shapes report their induction variable (it was lost when a later capture-less match reset $1).
{
    my $sum = PAX::CodeUnitCompiler::_native_i64_sum_loop_shape('my ($n) = @_; my $sum = 0; for (my $i = 1; $i <= $n; $i++) { $sum += $i; } return $sum;');
    is($sum && $sum->{induction}, 'i', 'sum loop shape records its induction variable');
    my $mix = PAX::CodeUnitCompiler::_native_i64_masked_mix_accum_loop_shape('my ($n) = @_; my $acc = 0; for (my $k = 0; $k < $n; $k++) { $acc += (($k * 13) ^ ($k >> 3)) & 0xFFFF; } return $acc;');
    is($mix && $mix->{induction}, 'k', 'masked mix loop shape records its induction variable');
}

done_testing();
