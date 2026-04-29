use strict;
use warnings;

sub add {
    my ($left, $right) = @_;
    return $left + $right;
}

my $value = add(2, 3);
die "bad arithmetic" unless $value == 5;
1;

=pod

=head1 NAME

t/fixtures/simple.pl - provide the simple fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the simple fixture used by the PAX test suite.

=cut

