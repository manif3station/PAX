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

=pod

=head1 NAME

t/fixtures/nasty_typeglob_local.pl - provide the nasty_typeglob_local fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the nasty_typeglob_local fixture used by the PAX test suite.

=cut

