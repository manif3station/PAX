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
