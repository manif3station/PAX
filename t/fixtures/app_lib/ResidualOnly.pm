package ResidualOnly;

use strict;
use warnings;

sub reverse_words {
    my ($text) = @_;
    my @parts = split /\s+/, ($text // '');
    return join ' ', reverse @parts;
}

1;
