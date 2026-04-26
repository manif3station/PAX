package HybridLoad;

use strict;
use warnings;

our $LOADED = ($LOADED // 0) + 1;
our $SOURCE_FALLBACK_LOADED = 0;

sub fast_message {
    return "hybrid-fast";
}

sub slow_message {
    my ($value) = @_;
    $SOURCE_FALLBACK_LOADED = 1;
    my @parts = split /:/, ($value // '');
    return join ':', reverse @parts;
}

1;
