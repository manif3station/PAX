#!/usr/bin/env perl
use strict;
use warnings;

my $file = 'lib/PAX.pm';
open my $fh, '<', $file or die "open $file: $!";
local $/;
my $content = <$fh>;
close $fh;

my ($version) = $content =~ /^our \$VERSION\s*=\s*'(\d+)\.(\d+)';/m
    or die "cannot read VERSION from $file\n";

my ($major, $minor) = ($1, $2);
$minor += 1;
my $width = length($2);
printf "%d.%0*d\n", $major, $width, $minor;

=pod

=head1 NAME

next_version.pl - implement the next version release or maintenance utility used by the PAX project.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to implement the next version release or maintenance utility used by the PAX project.

=cut

