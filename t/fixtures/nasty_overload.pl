use strict;
use warnings;

package PAX::Fixture::Box;

use overload
    '0+' => sub { ${ $_[0] } },
    '+' => sub { ${ $_[0] } + $_[1] },
    fallback => 1;

sub new {
    my ($class, $value) = @_;
    return bless \$value, $class;
}

package main;

my $box = PAX::Fixture::Box->new(7);
die "bad overload" unless $box + 5 == 12;
1;

=pod

=head1 NAME

t/fixtures/nasty_overload.pl - provide the nasty_overload fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the nasty_overload fixture used by the PAX test suite.

=cut

