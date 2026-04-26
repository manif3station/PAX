use strict;
use warnings;

BEGIN {
    package PAX::Fixture::CompilePhase;
    our $BEGIN_RAN = 1;
}

sub marker {
    return $PAX::Fixture::CompilePhase::BEGIN_RAN;
}

die "BEGIN did not run" unless marker();
1;
