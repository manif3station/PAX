use strict;
use warnings;

our $value = 3;
our $alias;
*alias = \$value;

sub read_alias {
    local $value = 9;
    return $alias + $value;
}

die "bad typeglob/local" unless read_alias() == 12;
1;
