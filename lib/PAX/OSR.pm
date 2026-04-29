package PAX::OSR;

our $VERSION = '0.016';

use strict;
use warnings;
use JSON::PP ();

sub new {
    my ($class, %args) = @_;
    return bless {
        threshold => $args{threshold} // 2,
    }, $class;
}

sub evaluate {
    my ($self, %args) = @_;
    my $unit = $args{ssa_unit} // {};
    my $profile = $args{profile} // {};
    my $shape = $unit->{native_shape} // $unit->{source}{native_shape} // {};
    my $dispatches = $profile->{dispatches} // 0;

    if (($shape->{kind} // '') ne 'i64_sum_loop') {
        return {
            status => 'not_applicable',
            reason => 'region is not an OSR-capable loop',
            osr_event => undef,
            safepoint => $unit->{deopt}{safepoint},
        };
    }

    if ($dispatches + 1 >= $self->{threshold}) {
        return {
            status => 'promote',
            reason => 'loop reached OSR threshold',
            osr_event => 'promote',
            loop_header => 'entry',
            backedge => 'entry',
            safepoint => $unit->{deopt}{safepoint},
        };
    }

    return {
        status => 'observe',
        reason => 'loop below OSR threshold',
        osr_event => undef,
        loop_header => 'entry',
        backedge => 'entry',
        safepoint => $unit->{deopt}{safepoint},
    };
}

sub retirement {
    my ($self, %args) = @_;
    return {
        status => 'retire',
        reason => $args{reason} // 'guard invalidated promoted OSR region',
        osr_event => 'retire',
        safepoint => $args{safepoint},
    };
}

1;
