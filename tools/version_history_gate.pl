#!/usr/bin/env perl
use strict;
use warnings;

my $current_version = eval { _read_version_from_git('HEAD', 'lib/PAX.pm') };
if ($@) {
    print "version-history-gate: no committed HEAD version to compare\n";
    exit 0;
}

my $previous_version = eval { _read_version_from_git('HEAD^', 'lib/PAX.pm') };
if ($@) {
    print "version-history-gate: no prior committed version to compare\n";
    exit 0;
}

my @changed = _git_lines('git diff-tree --no-commit-id --name-only -r HEAD');
my @meaningful = grep { _requires_version_bump($_) } @changed;

if (!@meaningful) {
    print "version-history-gate: HEAD has no release-facing file changes\n";
    exit 0;
}

if ($current_version eq $previous_version) {
    die "version-history-gate failed: HEAD changed release-facing files without a version bump\n"
        . "previous version: $previous_version\n"
        . "current version: $current_version\n"
        . "changed files requiring a bump:\n"
        . join("\n", map { "  $_" } @meaningful) . "\n";
}

print "version-history-gate: HEAD bumped version from $previous_version to $current_version\n";

sub _requires_version_bump {
    my ($path) = @_;
    return 0 if !defined $path || $path eq '';
    return 0 if $path =~ m{\A(?:project|projects)/};
    return 0 if $path =~ m{\A(?:DD Source Code|cover_db|pax-webapp|blogs)/};
    return 0 if $path =~ m{\A(?:SOW[^/]*|BACKLOG\.md|AGENTS\.override\.md)\z};
    return 0 if $path =~ m{\A(?:PAX-[^/]+(?:\.tar\.gz)?|\.build|\.dzil)(?:/|\z)};
    return 1 if $path =~ m{\A(?:bin|lib|t|tools|examples|docs)/};
    return 1 if $path =~ m{\A(?:Makefile|README\.md|Changes|dist\.ini|cpanfile|Dockerfile|DOCKER\.md|docker-compose\.yml)\z};
    return 1;
}

sub _read_version_from_git {
    my ($rev, $path) = @_;
    my $content = qx{git show $rev:$path 2>/dev/null};
    die "cannot read $path from $rev\n" if $? != 0 || $content eq '';
    my ($version) = $content =~ /^our \$VERSION\s*=\s*'([^']+)';/m
        or die "cannot read VERSION from $rev:$path\n";
    return $version;
}

sub _git_lines {
    my ($cmd) = @_;
    my @lines = qx{$cmd};
    die "command failed: $cmd\n" if $?;
    chomp @lines;
    return grep { defined $_ && $_ ne '' } @lines;
}

=pod

=head1 NAME

version_history_gate.pl - implement the version history gate release or maintenance utility used by the PAX project.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to implement the version history gate release or maintenance utility used by the PAX project.

=cut

