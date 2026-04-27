#!/usr/bin/env perl
use strict;
use warnings;

my $version_file = 'lib/PAX.pm';
my $changes_file = 'Changes';

open my $vf, '<', $version_file or die "open $version_file: $!";
local $/;
my $version_content = <$vf>;
close $vf;
my ($version) = $version_content =~ /^our \$VERSION\s*=\s*'([^']+)';/m
    or die "cannot read VERSION from $version_file\n";

open my $cf, '<', $changes_file or die "open $changes_file: $!";
my $first_nonblank = '';
while (defined(my $line = <$cf>)) {
    next if $line =~ /^\s*$/;
    $first_nonblank = $line;
    last;
}
close $cf;

die "changes-gate failed: Changes is empty\n" if !$first_nonblank;
die "changes-gate failed: top Changes entry does not match version $version\n"
    if $first_nonblank !~ /^\Q$version\E\b/;

print "changes-gate: top Changes entry matches version $version\n";
