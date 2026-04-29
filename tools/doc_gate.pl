#!/usr/bin/env perl
use strict;
use warnings;

my @checks = (
    [
        'README.md',
        [
            qr/^#\s+PAX\b/m,
            qr/^\Q## Introduction\E/m,
            qr/^\Q## What You Get\E/m,
            qr/^\Q## Main Concepts\E/m,
            qr/^\Q## Quick Start\E/m,
            qr/^\Q## CLI Contract\E/m,
            qr/^\Q## `paxfile.yml`\E/m,
            qr/^\Q## Docker Deployment\E/m,
            qr/^\Q## FAQ\E/m,
            qr/\bpax build\b/,
            qr/\bpax run\b/,
        ],
    ],
    [
        'lib/PAX.pm',
        [
            qr/^=head1 NAME/m,
            qr/^=head1 VERSION/m,
            qr/^=head1 INTRODUCTION/m,
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

my $pod_doc_all = system($^X, 'tools/pod_doc_all.pl');
die "doc-gate failed: POD-DOC-ALL\n" if $pod_doc_all != 0;

print "doc-gate: README.md and lib/PAX.pm contain required software sections; POD-DOC-ALL passed\n";

__END__

=head1 NAME

doc_gate.pl - enforce PAX top-level documentation requirements

=head1 SYNOPSIS

  perl tools/doc_gate.pl

=head1 DESCRIPTION

This script checks the repository-level documentation contract for PAX.

It verifies that C<README.md> stays product-focused and that C<lib/PAX.pm>
contains the required distribution-level POD sections. It then runs
C<POD-DOC-ALL> so file-level POD is enforced across the full maintained Perl
surface and changed-subroutine comments stay current where behavior changed.

=head1 PURPOSE

This tool keeps the top-level documentation contract executable. It is the gate
that stops product docs and module docs from drifting separately.

=head1 HOW TO USE

Run it from the repository root, normally through C<make doc-gate>, after any
change that affects operator workflows, module interfaces, or documentation
structure.

=cut
