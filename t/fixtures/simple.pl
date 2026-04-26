use strict;
use warnings;

sub add {
    my ($left, $right) = @_;
    return $left + $right;
}

my $value = add(2, 3);
die "bad arithmetic" unless $value == 5;
1;
