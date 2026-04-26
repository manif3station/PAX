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
