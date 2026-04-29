#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use File::Find;
use File::Spec;

my $root = File::Spec->catdir(qw(lib PAX));
my $version_file = File::Spec->catfile(qw(lib PAX.pm));
my $version = _read_version($version_file);

my @modules;
find(
    {
        wanted => sub {
            return unless -f;
            return unless /\.pm$/;
            return unless m{\Alib/PAX/};
            push @modules, $File::Find::name;
        },
        no_chdir => 1,
    },
    $root
);

for my $module (@modules) {
    open my $in, '<', $module or die "open $module: $!";
    local $/;
    my $content = <$in>;
    close $in;

    if ($content =~ /^our \$VERSION\s*=/m) {
        $content =~ s/^our \$VERSION\s*=\s*'[^']*';?/our \$VERSION = '$version';/m;
    }
    else {
        $content =~ s/\A(package\s+[A-Za-z0-9_:]+;\n)\n?/$1 . 'our $VERSION = ' . "'" . $version . "';\n\n"/me;
    }

    open my $out, '>', $module or die "open $module: $!";
    print {$out} $content;
    close $out;
}

say "Synced " . scalar(@modules) . " modules to version $version";

sub _read_version {
    my ($file) = @_;
    open my $fh, '<', $file or die "open $file: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    my ($version) = $content =~ /^our \$VERSION\s*=\s*'([^']+)';/m;
    die "cannot read VERSION from $file" unless $version;
    return $version;
}

=pod

=head1 NAME

sync_versions.pl - version synchronizer

=head1 SYNOPSIS

  perl tools/sync_versions.pl

=head1 DESCRIPTION

Copies the canonical version from lib/PAX.pm into the rest of the distribution modules.

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
