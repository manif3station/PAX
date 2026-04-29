use strict;
use warnings;

sub add {
    my ($left, $right) = @_;
    return $left + $right;
}

sub subtract {
    my ($left, $right) = @_;
    return $left - $right;
}

sub multiply {
    my ($left, $right) = @_;
    return $left * $right;
}

sub greater_than {
    my ($left, $right) = @_;
    return $left > $right;
}

die "bad add" unless add(2, 3) == 5;
die "bad subtract" unless subtract(10, 3) == 7;
die "bad multiply" unless multiply(6, 7) == 42;
die "bad greater_than" unless greater_than(10, 3) == 1;
1;

=pod

=head1 NAME

t/fixtures/native_leafs.pl - provide the native_leafs fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the native_leafs fixture used by the PAX test suite.

=cut

