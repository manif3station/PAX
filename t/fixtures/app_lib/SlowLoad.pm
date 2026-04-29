package SlowLoad;

use strict;
use warnings;

our $LOADED = ($LOADED // 0) + 1;

sub message {
    return "slowload-ready";
}

1;

=pod

=head1 NAME

t/fixtures/app_lib/SlowLoad.pm - provide the SlowLoad fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the SlowLoad fixture used by the PAX test suite.

=cut

