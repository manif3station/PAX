package PAX::HIR;

our $VERSION = '0.016';

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {
        manifest => $args{manifest},
        regions => $args{regions} // [],
    }, $class;
}

sub lower_all {
    my ($self) = @_;
    my @units;

    for my $region (@{ $self->{regions} }) {
        push @units, $self->lower_region($region);
    }

    return \@units;
}

sub lower_region {
    my ($self, $region) = @_;
    my $blocked = ($region->{lowering_status} // '') eq 'blocked';
    my $native_shape = $blocked ? undef : $region->{source}{native_shape};
    my $body_op = $blocked ? {
        op => 'fallback_call',
        target => $region->{name},
        effects => ['interpreter'],
    } : _body_op_for_region($region, $native_shape);

    return {
        region_id => $region->{id},
        region_name => $region->{name},
        status => $blocked ? 'fallback' : 'lowered',
        native_shape => $native_shape,
        graph => {
            blocks => [
                {
                    id => 'entry',
                    ops => [
                        {
                            op => 'enter_region',
                            context => 'unknown',
                            effects => [],
                        },
                        $body_op,
                        {
                            op => 'return',
                            effects => [],
                        },
                    ],
                    successors => [],
                },
            ],
        },
        source => $region->{source},
        deopt_anchors => [
            {
                block => 'entry',
                reason => $blocked ? $region->{reason} : 'guard_failure',
                live_values => [qw(@_ wantarray)],
            },
        ],
        required_epochs => $region->{required_epochs} // [],
        diagnostics => $blocked ? [{
            level => 'warning',
            code => 'hir_fallback_region',
            message => $region->{reason},
        }] : [],
    };
}

sub _body_op_for_region {
    my ($region, $native_shape) = @_;
    if ($native_shape) {
        return {
            op => 'native_candidate',
            target => $region->{name},
            shape => $native_shape,
            effects => ['guarded_call'],
        };
    }
    return {
        op => 'call_reference_equivalent',
        target => $region->{name},
        effects => ['guarded_call'],
    };
}

1;
