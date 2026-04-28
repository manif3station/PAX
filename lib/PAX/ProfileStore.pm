package PAX::ProfileStore;

our $VERSION = '0.012';

use strict;
use warnings;
use JSON::PP ();

sub new {
    my ($class, %args) = @_;
    return bless {
        threshold => $args{threshold} // 2,
        regions => {},
    }, $class;
}

sub record_dispatch {
    my ($self, $event) = @_;
    my $region = $event->{region_name} // $event->{region_id} // 'unknown';
    my $slot = $self->{regions}{$region} ||= {
        dispatches => 0,
        native => 0,
        fallback => 0,
        deopt => 0,
        osr_promotions => 0,
        osr_retirements => 0,
    };
    $slot->{dispatches}++;
    if (($event->{status} // '') eq 'native') {
        $slot->{native}++;
    } elsif (($event->{status} // '') eq 'deopt') {
        $slot->{deopt}++;
        $slot->{fallback}++;
    } else {
        $slot->{fallback}++;
    }
    $slot->{osr_promotions}++ if ($event->{osr_event} // '') eq 'promote';
    $slot->{osr_retirements}++ if ($event->{osr_event} // '') eq 'retire';
    return $slot;
}

sub report {
    my ($self) = @_;
    my @regions;
    for my $name (sort keys %{ $self->{regions} }) {
        my $stats = $self->{regions}{$name};
        push @regions, {
            region => $name,
            %$stats,
            hot => $stats->{dispatches} >= $self->{threshold} ? JSON::PP::true() : JSON::PP::false(),
        };
    }
    return {
        threshold => $self->{threshold},
        regions => \@regions,
    };
}

1;
