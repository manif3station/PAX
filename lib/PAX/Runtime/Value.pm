package PAX::Runtime::Value;

our $VERSION = '0.016';

use strict;
use warnings;

sub fast_int {
    my ($class, $value) = @_;
    return bless {
        kind => 'FastValue',
        type => 'int',
        value => 0 + $value,
        escaped => 0,
    }, $class;
}

sub perl_value {
    my ($class, $value) = @_;
    return bless {
        kind => 'PerlValue',
        type => ref($value) || 'scalar',
        value => $value,
        escaped => 1,
    }, $class;
}

sub materialise {
    my ($self) = @_;
    return $self if $self->{kind} eq 'PerlValue';
    return __PACKAGE__->perl_value($self->{value});
}

sub as_hash {
    my ($self) = @_;
    return {
        kind => $self->{kind},
        type => $self->{type},
        value => $self->{value},
        escaped => $self->{escaped} ? 1 : 0,
    };
}

1;
