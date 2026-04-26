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
