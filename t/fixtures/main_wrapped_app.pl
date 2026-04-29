#!/usr/bin/env perl

use strict;
use warnings;

sub main {
    my (@argv) = @_;
    my $cmd = shift @argv || 'version';

    if ($cmd eq 'version') {
        print "0.2.0\n";
        return 0;
    }

    print STDERR "unknown command: $cmd\n";
    return 2;
}

exit main(@ARGV) unless caller;

1;

=pod

=head1 NAME

t/fixtures/main_wrapped_app.pl - provide the main_wrapped_app fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the main_wrapped_app fixture used by the PAX test suite.

=cut

