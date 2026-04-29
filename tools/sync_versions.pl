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

sync_versions.pl - implement the sync versions release or maintenance utility used by the PAX project.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to implement the sync versions release or maintenance utility used by the PAX project.

=cut

