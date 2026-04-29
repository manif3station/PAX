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

=pod

=head1 NAME

t/fixtures/compile_phase.pl - provide the compile_phase fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the compile_phase fixture used by the PAX test suite.

=cut

