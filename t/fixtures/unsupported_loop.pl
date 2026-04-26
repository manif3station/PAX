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
