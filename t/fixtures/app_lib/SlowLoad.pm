package SlowLoad;

use strict;
use warnings;

our $LOADED = ($LOADED // 0) + 1;

sub message {
    return "slowload-ready";
}

1;
