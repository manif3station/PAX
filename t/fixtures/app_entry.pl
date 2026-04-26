#!/usr/bin/env perl

use strict;
use warnings;
use HybridLoad ();
use ResidualOnly ();
use SlowLoad ();

my $cmd = shift @ARGV // 'status';
if ($cmd eq 'status') {
    print SlowLoad::message(), "\n";
    exit 0;
}

if ($cmd eq 'asset') {
    my $root = $ENV{PAX_EMBEDDED_ASSET_ROOT} // '';
    my $path = $root ? "$root/banner.txt" : '';
    if (!$path || !-f $path) {
        print STDERR "missing asset\n";
        exit 3;
    }
    open my $fh, '<', $path or die $!;
    my $content = <$fh>;
    close $fh;
    print $content;
    exit 0;
}

if ($cmd eq 'hybrid-fast') {
    print HybridLoad::fast_message(), "\n";
    exit 0;
}

if ($cmd eq 'hybrid-slow') {
    print HybridLoad::slow_message('alpha:beta'), "\n";
    exit 0;
}

if ($cmd eq 'residual-only') {
    print ResidualOnly::reverse_words('one two three'), "\n";
    exit 0;
}

print STDERR "unknown command: $cmd\n";
exit 2;
