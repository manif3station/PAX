use strict;
use warnings;

sub add {
    my ($left, $right) = @_;
    return $left + $right;
}

our $MUTATED = 0;

sub mutate_symbols {
    no strict 'refs';
    *dynamic_symbol = sub { return 1 };
    $MUTATED = 1;
    return $MUTATED;
}

die "bad add" unless add(2, 3) == 5;
1;

=pod

=head1 NAME

t/fixtures/mutation.pl - provide the mutation fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the mutation fixture used by the PAX test suite.

=cut

