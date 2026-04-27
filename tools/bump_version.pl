#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';

my $version = shift @ARGV // '';
die "Usage: perl tools/bump_version.pl <version>\n" unless $version;
die "Version must look like 0.001: $version\n" unless $version =~ /^\d+\.\d+$/;

my $pax_pm = 'lib/PAX.pm';
open my $in, '<', $pax_pm or die "open $pax_pm: $!";
local $/;
my $content = <$in>;
close $in;

if ($content !~ s/^our \$VERSION\s*=\s*'[^']*';/our \$VERSION = '$version';/m) {
    die "Cannot update version in $pax_pm\n";
}

open my $out, '>', $pax_pm or die "write $pax_pm: $!";
print {$out} $content;
close $out;

system $^X, 'tools/sync_versions.pl';
die "sync failed\n" if $?;

my $changes = 'Changes';
my $entry = "$version  " . scalar(localtime) . "\n    - Version bump\n";

if (-f $changes) {
    open my $chg, '<', $changes or die "open $changes: $!";
    local $/;
    my $changelog = <$chg>;
    close $chg;

    if ($changelog !~ /^\Q$version\E\b/m) {
        open my $chg_out, '>', $changes or die "write $changes: $!";
        print {$chg_out} "$entry\n$changelog";
        close $chg_out;
    }
}

_update_dist_ini($version);

say "Bumped VERSION to $version and synced lib/PAX/**/*.pm.";

sub _update_dist_ini {
    my ($version) = @_;
    my $dist = 'dist.ini';
    return unless -f $dist;

    open my $in, '<', $dist or die "open $dist: $!";
    local $/;
    my $ini = <$in>;
    close $in;

    $ini =~ s/^version\s*=\s*.*$/version = $version/m;
    open my $out, '>', $dist or die "write $dist: $!";
    print {$out} $ini;
    close $out;
}
