use strict;
use warnings;

package PAX::Fixture::TieScalar;

sub TIESCALAR {
    my ($class, $value) = @_;
    return bless \$value, $class;
}

sub FETCH {
    my ($self) = @_;
    return $$self;
}

sub STORE {
    my ($self, $value) = @_;
    $$self = $value;
}

package main;

tie my $value, 'PAX::Fixture::TieScalar', 10;
$value = $value + 5;
die "bad tie" unless $value == 15;
1;
