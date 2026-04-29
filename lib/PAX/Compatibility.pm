package PAX::Compatibility;

our $VERSION = '0.020';

use strict;
use warnings;
use JSON::PP ();

sub new {
    my ($class, %args) = @_;
    return bless {
        capture => $args{capture} // {},
        baseline_match => $args{baseline_match} ? 1 : 0,
    }, $class;
}

sub report {
    my ($self) = @_;
    my $capture = $self->{capture};
    my $features = $capture->{source_features} // {};
    my @barriers;

    for my $name (sort keys %$features) {
        next if !$features->{$name};
        my $policy = _feature_policy($name);
        push @barriers, {
            feature => $name,
            policy => $policy->{policy},
            reason => $policy->{reason},
        } if $policy->{barrier};
    }

    if (($capture->{status} // '') ne 'ok') {
        return _level('D', 'reference capture failed', 0, \@barriers);
    }

    if (!$self->{baseline_match}) {
        return _level('C', 'runtime is capturable but does not match Perl 5.42.x baseline', 0, \@barriers);
    }

    if (@barriers) {
        return _level('B', 'capturable baseline with dynamic feature barriers', 1, \@barriers);
    }

    return _level('A', 'capturable baseline with no detected dynamic barriers in source scan', 1, \@barriers);
}

sub _level {
    my ($level, $reason, $acceleration_supported, $barriers) = @_;
    return {
        level => $level,
        reason => $reason,
        acceleration_supported => $acceleration_supported ? JSON::PP::true() : JSON::PP::false(),
        barriers => $barriers,
    };
}

sub _feature_policy {
    my ($name) = @_;
    my %policies = (
        string_eval => ['fallback', 'string eval is a runtime compilation boundary'],
        autoload => ['guarded_barrier', 'AUTOLOAD requires guarded method resolution'],
        tie => ['barrier', 'tied variables are semantic barriers by default'],
        overload => ['guarded_barrier', 'overload tables require epoch guards'],
        typeglob => ['guarded_barrier', 'typeglob access requires package shape guards'],
        xs_loader => ['barrier', 'XS is barrier mode unless declared safe'],
        local_dynamic => ['guarded_barrier', 'local dynamic scoping requires deopt state'],
    );
    my $entry = $policies{$name} // ['unknown', 'unknown dynamic feature'];
    return {
        policy => $entry->[0],
        reason => $entry->[1],
        barrier => 1,
    };
}

1;
