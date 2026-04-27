package PAX::HotRegionJIT;

our $VERSION = '0.011';

use strict;
use warnings;
use JSON::PP ();

sub new {
    my ($class, %args) = @_;
    return bless {
        threshold => $args{threshold} // 2,
    }, $class;
}

sub decision {
    my ($self, %args) = @_;
    my $unit = $args{ssa_unit} // {};
    my $profile = $args{profile} // {};
    my $dispatches = $profile->{dispatches} // 0;
    my $shape = $unit->{native_shape} // $unit->{source}{native_shape} // {};
    my $has_native_shape = %$shape ? 1 : 0;

    if (!$has_native_shape) {
        return {
            status => 'barrier',
            reason => 'region has no native lowering shape',
            hot => JSON::PP::false(),
        };
    }

    if ($dispatches + 1 >= $self->{threshold}) {
        return {
            status => 'promote',
            reason => 'profile threshold reached',
            hot => JSON::PP::true(),
            tier => 'tier-1',
        };
    }

    return {
        status => 'observe',
        reason => 'profile threshold not reached',
        hot => JSON::PP::false(),
        tier => 'interpreter',
    };
}

sub retirement {
    my ($self, %args) = @_;
    return {
        status => 'retire',
        reason => $args{reason} // 'native region retired',
        region_id => $args{region_id},
        region_name => $args{region_name},
    };
}

1;
