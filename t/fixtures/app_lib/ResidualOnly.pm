package ResidualOnly;

use strict;
use warnings;

sub reverse_words {
    my ($text) = @_;
    my @parts = split /\s+/, ($text // '');
    return join ' ', reverse @parts;
}

1;

=pod

=head1 NAME

t/fixtures/app_lib/ResidualOnly.pm - provide the ResidualOnly fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the ResidualOnly fixture used by the PAX test suite.

=cut

