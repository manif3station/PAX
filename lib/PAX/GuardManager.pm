package PAX::GuardManager;

our $VERSION = '0.018';

use strict;
use warnings;
use PAX::DeoptEngine;

sub new {
    my ($class, %args) = @_;
    return bless {
        epochs => $args{epochs} // {},
        telemetry => [],
    }, $class;
}

sub validate_region {
    my ($self, $ssa_unit) = @_;
    for my $guard (@{ $ssa_unit->{guards} // [] }) {
        my $key = $guard->{invalidation_key};
        if (!exists $self->{epochs}{$key}) {
            push @{ $self->{telemetry} }, {
                region_id => $ssa_unit->{region_id},
                guard_id => $guard->{id},
                status => 'failed',
                reason => 'missing_epoch',
                invalidation_key => $key,
            };
            return 0;
        }
        push @{ $self->{telemetry} }, {
            region_id => $ssa_unit->{region_id},
            guard_id => $guard->{id},
            status => 'passed',
            invalidation_key => $key,
        };
    }
    return 1;
}

sub validate_or_deopt {
    my ($self, $ssa_unit, %args) = @_;
    my $ok = $self->validate_region($ssa_unit);
    if ($ok) {
        return {
            status => 'native_allowed',
            region_id => $ssa_unit->{region_id},
            telemetry => $self->telemetry,
        };
    }

    my $last = $self->{telemetry}[-1] // {};
    my $reconstructed = PAX::DeoptEngine->new->reconstruct(
        ssa_unit => $ssa_unit,
        reason => $last->{reason} // 'guard_failed',
        guard => $last,
        interpreter_result => $args{interpreter_result},
        args => $args{args} // [],
        context => $args{context} // 'scalar',
    );
    return {
        status => 'deopt',
        region_id => $ssa_unit->{region_id},
        fallback => {
            reason => $last->{reason} // 'guard_failed',
            guard_id => $last->{guard_id},
            invalidation_key => $last->{invalidation_key},
            continuation => $ssa_unit->{deopt}{safepoint},
            interpreter_result => $args{interpreter_result},
            reconstructed_frame => $reconstructed,
        },
        telemetry => $self->telemetry,
    };
}

sub invalidate_epoch {
    my ($self, $key) = @_;
    delete $self->{epochs}{$key};
}

sub telemetry {
    my ($self) = @_;
    return $self->{telemetry};
}

1;
