package PAX::Backend::Tier1CraneliftEquivalent;
our $VERSION = '0.024';

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

=pod

=head1 NAME

PAX::Backend::Tier1CraneliftEquivalent - document the Tier1CraneliftEquivalent component within the PAX compiler, packaging, or runtime stack.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to document the Tier1CraneliftEquivalent component within the PAX compiler, packaging, or runtime stack.

=cut

