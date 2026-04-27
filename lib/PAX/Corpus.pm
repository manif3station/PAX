package PAX::Corpus;

our $VERSION = '0.010';

use strict;
use warnings;
use JSON::PP qw(decode_json);
use PAX::Capture;
use PAX::Manifest;

sub new {
    my ($class, %args) = @_;
    return bless {
        manifest_path => $args{manifest_path},
    }, $class;
}

sub run {
    my ($self) = @_;
    my $manifest = $self->_load_manifest;
    my @results;
    my %levels;

    for my $case (@{ $manifest->{cases} // [] }) {
        my $capture = PAX::Capture->new(mode => $case->{mode} // 'live')->capture($case->{path});
        my $pax_manifest = PAX::Manifest->new(capture => $capture)->to_hash;
        my $level = $pax_manifest->{compatibility}{level};
        my $expected = $pax_manifest->{runtime}{baseline_match}
            ? $case->{expected_level}
            : ($case->{expected_level_when_baseline_mismatch} // $case->{expected_level});
        $levels{$level}++;
        push @results, {
            id => $case->{id},
            path => $case->{path},
            expected_level => $expected,
            actual_level => $level,
            passed => (!defined $expected || $expected eq $level) ? JSON::PP::true() : JSON::PP::false(),
            reason => $pax_manifest->{compatibility}{reason},
            barriers => $pax_manifest->{compatibility}{barriers} // [],
            diagnostics => $pax_manifest->{diagnostics} // [],
        };
    }

    my $failed = grep { !$_->{passed} } @results;
    return {
        manifest_path => $self->{manifest_path},
        total => scalar @results,
        failed => $failed,
        passed => $failed ? JSON::PP::false() : JSON::PP::true(),
        levels => \%levels,
        results => \@results,
    };
}

sub _load_manifest {
    my ($self) = @_;
    open my $fh, '<', $self->{manifest_path} or die "cannot read corpus manifest $self->{manifest_path}: $!";
    local $/;
    return decode_json(<$fh>);
}

1;
