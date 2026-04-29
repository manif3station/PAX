package PAX::BenchmarkMatrix;

our $VERSION = '0.020';

use strict;
use warnings;
use JSON::PP qw(decode_json);
use PAX::Benchmark;
use PAX::Capture;
use PAX::Manifest;

sub new {
    my ($class, %args) = @_;
    return bless {
        manifest_path => $args{manifest_path},
        iterations => $args{iterations} // 1,
        pax_bin => $args{pax_bin},
    }, $class;
}

sub run {
    my ($self) = @_;
    my $manifest = $self->_load_manifest;
    my @classes;
    for my $class (@{ $manifest->{classes} // [] }) {
        my @fixtures;
        for my $fixture (@{ $class->{fixtures} // [] }) {
            push @fixtures, $self->_run_fixture($fixture);
        }
        push @classes, {
            id => $class->{id},
            description => $class->{description},
            metrics => $class->{metrics} // [],
            fixtures => \@fixtures,
        };
    }
    return {
        manifest_path => $self->{manifest_path},
        iterations => $self->{iterations},
        classes => \@classes,
        passed => JSON::PP::true(),
    };
}

sub _run_fixture {
    my ($self, $fixture) = @_;
    my $capture = PAX::Capture->new(mode => 'live')->capture($fixture);
    my $manifest = PAX::Manifest->new(capture => $capture)->to_hash;
    my $benchmark = PAX::Benchmark->new(
        pax_bin => $self->{pax_bin},
        iterations => $self->{iterations},
    )->run_runtime_benchmark($fixture);
    return {
        path => $fixture,
        capture_status => $capture->{status},
        compatibility_level => $manifest->{compatibility}{level},
        fallback_reason => $manifest->{compatibility}{reason},
        benchmark => $benchmark,
    };
}

sub _load_manifest {
    my ($self) = @_;
    open my $fh, '<', $self->{manifest_path} or die "cannot read benchmark matrix $self->{manifest_path}: $!";
    local $/;
    return decode_json(<$fh>);
}

1;
