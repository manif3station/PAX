#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;

my $version_file = 'lib/PAX.pm';
open my $vf, '<', $version_file or die "open $version_file: $!";
local $/;
my $version_content = <$vf>;
close $vf;

my ($version) = $version_content =~ /^our \$VERSION\s*=\s*'([^']+)';/m
    or die "cannot read VERSION from $version_file\n";

my @bad;
find(
    {
        wanted => sub {
            return unless -f $File::Find::name;
            return unless $File::Find::name =~ /\.pm\z/;
            return unless $File::Find::name =~ m{\Alib/};

            open my $fh, '<', $File::Find::name or die "open $File::Find::name: $!";
            local $/;
            my $content = <$fh>;
            close $fh;

            my ($module_version) = $content =~ /^our \$VERSION\s*=\s*'([^']+)';/m;
            push @bad, $File::Find::name if !defined $module_version || $module_version ne $version;
        },
        no_chdir => 1,
    },
    'lib'
);

if (@bad) {
    die "version-gate failed: module versions out of sync with $version\n" . join("\n", @bad) . "\n";
}

print "version-gate: all module versions match $version\n";

=pod

=head1 NAME

version_gate.pl - version consistency gate

=head1 SYNOPSIS

  perl tools/version_gate.pl

=head1 DESCRIPTION

Verifies that every PAX module carries the same version as lib/PAX.pm.

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
