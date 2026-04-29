package PAX::GuardedSSA;

our $VERSION = '0.019';

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {
        hir_units => $args{hir_units} // [],
    }, $class;
}

sub build_all {
    my ($self) = @_;
    return [map { $self->build_unit($_) } @{ $self->{hir_units} }];
}

sub build_unit {
    my ($self, $unit) = @_;
    my $fallback = ($unit->{status} // '') eq 'fallback';
    my @guards = map {
        {
            id => 'guard_' . $_,
            predicate => $_ . '_epoch_unchanged',
            invalidation_key => $_,
            deopt_continuation => $unit->{region_id} . ':entry',
            compatibility_classification => $fallback ? 'fallback' : 'guarded',
        }
    } @{ $unit->{required_epochs} // [] };

    return {
        region_id => $unit->{region_id},
        region_name => $unit->{region_name},
        source => $unit->{source},
        status => $fallback ? 'fallback' : 'ssa',
        native_shape => $unit->{native_shape},
        values => [
            {
                id => 'v0',
                kind => 'frame_args',
                type_hypothesis => 'PerlValue[]',
            },
            {
                id => 'v1',
                kind => 'context',
                type_hypothesis => 'scalar|list|void',
            },
        ],
        guards => \@guards,
        blocks => [
            {
                id => 'entry',
                ops => [
                    map +{
                        op => 'guard',
                        guard_id => $_->{id},
                    }, @guards
                ],
                terminator => $fallback ? 'deopt_to_interpreter' : 'call_lowered_region',
            },
        ],
        deopt => {
            safepoint => $unit->{region_id} . ':entry',
            materialise => [qw(@_ wantarray lexicals exception_state)],
            anchors => $unit->{deopt_anchors} // [],
        },
    };
}

1;
