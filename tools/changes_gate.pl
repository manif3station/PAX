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

open my $cf2, '<', $changes_file or die "open $changes_file: $!";
local $/;
my $changes_content = <$cf2>;
close $cf2;

my ($top_block) = $changes_content =~ /\A(\Q$version\E\b.*?)(?:\n(?=\d+\.\d+\b)|\z)/ms;
die "changes-gate failed: missing top release block for $version\n" if !$top_block;
die "changes-gate failed: top release block still uses placeholder 'Version bump'\n"
    if $top_block =~ /^\s*-\s*Version bump\s*$/m;

print "changes-gate: top Changes entry matches version $version\n";

=pod

=head1 NAME

changes_gate.pl - implement the changes gate release or maintenance utility used by the PAX project.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to implement the changes gate release or maintenance utility used by the PAX project.

=cut

