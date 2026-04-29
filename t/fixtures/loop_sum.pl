use strict;
use warnings;

sub sum_to_n {
    my ($n) = @_;
    my $sum = 0;
    for (my $i = 1; $i <= $n; $i++) {
        $sum += $i;
    }
    return $sum;
}

die "bad sum_to_n" unless sum_to_n(10) == 55;
1;

=pod

=head1 NAME

t/fixtures/loop_sum.pl - provide the loop_sum fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the loop_sum fixture used by the PAX test suite.

=cut

