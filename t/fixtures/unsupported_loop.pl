use strict;
use warnings;

sub sum_even_to_n {
    my ($n) = @_;
    my $sum = 0;
    for (my $i = 0; $i <= $n; $i += 2) {
        $sum += $i;
    }
    return $sum;
}

die "bad sum_even_to_n" unless sum_even_to_n(10) == 30;
1;

=pod

=head1 NAME

t/fixtures/unsupported_loop.pl - provide the unsupported_loop fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the unsupported_loop fixture used by the PAX test suite.

=cut

