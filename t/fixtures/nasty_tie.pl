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

=pod

=head1 NAME

t/fixtures/nasty_tie.pl - provide the nasty_tie fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the nasty_tie fixture used by the PAX test suite.

=cut

