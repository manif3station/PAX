package PAX::Backend::Tier1CraneliftEquivalent;
our $VERSION = '0.018';

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {
        name => $args{name} // 'cranelift-equivalent-low-latency-backend',
    }, $class;
}

sub metadata {
    my ($self) = @_;
    return {
        tier => 1,
        name => $self->{name},
        role => 'quick_native_backend',
        contract => 'low_latency_guarded_ssa_native_emission',
    };
}

1;
