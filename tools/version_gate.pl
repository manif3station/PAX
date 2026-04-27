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
