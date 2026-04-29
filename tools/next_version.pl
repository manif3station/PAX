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

next_version.pl - next-version calculator

=head1 SYNOPSIS

  perl tools/next_version.pl

=head1 DESCRIPTION

Calculates the next semantic checkpoint version used by the release tooling.

=head1 PURPOSE

This tool exists to keep one release or validation responsibility scripted and
repeatable instead of relying on manual edits during the PAX gate flow.

=head1 WHEN TO USE

Run it when working on the release process, distribution metadata, or the gate
that this tool enforces.

=head1 HOW TO USE

Invoke it from the repository root so it sees the expected files and git state.
Keep its checks deterministic and tied to project rules rather than local shell
assumptions.

=head1 WHAT USES IT

The Makefile gate targets and release workflow call this script directly.

=cut
