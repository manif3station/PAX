#!/usr/bin/env perl
use strict;
use warnings;

my @checks = (
    [
        'README.md',
        [
            qr/^#\s+PAX\b/m,
            qr/^\Q## Quick Start\E/m,
            qr/^\Q## CLI Contract\E/m,
            qr/^\Q## `paxfile.yml`\E/m,
            qr/^\Q## Docker Deployment\E/m,
            qr/^\Q## CPAN Release Gates\E/m,
            qr/\bpax build\b/,
            qr/\bpax run\b/,
        ],
    ],
    [
        'lib/PAX.pm',
        [
            qr/^=head1 NAME/m,
            qr/^=head1 VERSION/m,
            qr/^=head1 SOW-03 PUBLIC COMMAND SURFACE/m,
            qr/^=head1 PAXFILE CONTRACT/m,
            qr/^=head1 ARCHITECTURE/m,
            qr/^=head1 RELEASE GATES/m,
            qr/\bpax build\b/,
            qr/\bpax run\b/,
        ],
    ],
);

for my $check (@checks) {
    my ($path, $patterns) = @$check;
    open my $fh, '<', $path or die "open $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;

    for my $pattern (@$patterns) {
        next if $content =~ $pattern;
        die "doc-gate failed: $path missing pattern $pattern\n";
    }
}

print "doc-gate: README.md and lib/PAX.pm contain required release sections\n";
