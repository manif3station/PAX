package PAX::RuntimeDispatcher;

our $VERSION = '0.019';

use strict;
use warnings;
use JSON::PP ();
use PAX::Capture;
use PAX::Manifest;
use PAX::RegionSelector;
use PAX::HIR;
use PAX::GuardedSSA;
use PAX::GuardManager;
use PAX::HotRegionJIT;
use PAX::InlineCache;
use PAX::OSR;
use PAX::ProfileGuidedAOT;
use PAX::ProfileStore;
use PAX::Tier1;
use PAX::NativeRunner;

sub new {
    my ($class, %args) = @_;
    return bless {
        mode => $args{mode} // 'live',
        profile_store => $args{profile_store} // PAX::ProfileStore->new(threshold => $args{threshold} // 2),
        inline_cache => $args{inline_cache} // PAX::InlineCache->new,
        hot_region_jit => $args{hot_region_jit} // PAX::HotRegionJIT->new(threshold => $args{threshold} // 2),
        osr => $args{osr} // PAX::OSR->new(threshold => $args{threshold} // 2),
        aot => $args{aot} // PAX::ProfileGuidedAOT->new(threshold => $args{threshold} // 2),
    }, $class;
}

sub dispatch_i64 {
    my ($self, %args) = @_;
    my $entrypoint = $args{entrypoint};
    my $region_name = $args{region_name};
    my $left = defined $args{left} ? $args{left} : 0;
    my $right = defined $args{right} ? $args{right} : 0;
    my $cache_site = $args{cache_site} // 'main-dispatch';

    my $capture = PAX::Capture->new(mode => $self->{mode})->capture($entrypoint);
    my $manifest = PAX::Manifest->new(capture => $capture)->to_hash;
    my $regions = PAX::RegionSelector->new(manifest => $manifest)->select;
    my $hir = PAX::HIR->new(manifest => $manifest, regions => $regions->{selected})->lower_all;
    my $ssa = PAX::GuardedSSA->new(hir_units => $hir)->build_all;
    my $guard_manager = PAX::GuardManager->new(epochs => $manifest->{runtime_epochs});
    my @attempts;

    my @candidate_units = defined $region_name
        ? grep { ($_->{region_name} // '') eq $region_name || ($_->{region_name} // '') eq "main::$region_name" } @$ssa
        : @$ssa;
    my $profile_by_region = _profile_by_region($self->{profile_store}->report);
    my $aot_plan = $self->{aot}->plan(
        manifest => $manifest,
        ssa_units => $ssa,
        profile => $profile_by_region,
    );

    if (defined $region_name && !@candidate_units) {
        my $event = {
            status => 'fallback',
            region_name => $region_name,
            entrypoint => $entrypoint,
            args => [$left + 0, $right + 0],
            reason => "requested region not found: $region_name",
            attempts => [],
            baseline_match => $manifest->{runtime}{baseline_match},
        };
        $self->{profile_store}->record_dispatch($event);
        return $event;
    }

    for my $unit (@candidate_units) {
        my $method = $unit->{region_name} // $region_name // $unit->{region_id};
        my $cache_lookup = $self->{inline_cache}->lookup(
            site => $cache_site,
            class_key => 'main',
            method => $method,
        );
        my $jit = $self->{hot_region_jit}->decision(
            ssa_unit => $unit,
            profile => $profile_by_region->{$method} // {},
        );
        my $osr = $self->{osr}->evaluate(
            ssa_unit => $unit,
            profile => $profile_by_region->{$method} // {},
        );
        my $guard = $guard_manager->validate_or_deopt($unit);
        if ($guard->{status} ne 'native_allowed') {
            my $retirement = $self->{osr}->retirement(
                reason => $guard->{fallback}{reason},
                safepoint => $unit->{deopt}{safepoint},
            );
            push @attempts, {
                region_id => $unit->{region_id},
                region_name => $unit->{region_name},
                status => 'deopt',
                guard => $guard,
                osr => $retirement,
                inline_cache => $cache_lookup,
            };
            $self->{profile_store}->record_dispatch({
                region_id => $unit->{region_id},
                region_name => $unit->{region_name},
                status => 'deopt',
                osr_event => $retirement->{osr_event},
            });
            next;
        }

        my $artifact = PAX::Tier1->new->compile($unit);
        if (($artifact->{entry_kind} // '') !~ /\Anative_i64_(?:leaf|loop)\z/ || !$artifact->{executable_path}) {
            my $cache_update = $self->{inline_cache}->update(
                site => $cache_site,
                class_key => 'main',
                method => $method,
                target_region_id => $unit->{region_id},
                target_region_name => $unit->{region_name},
            );
            push @attempts, {
                region_id => $unit->{region_id},
                region_name => $unit->{region_name},
                status => 'fallback',
                reason => $artifact->{reason},
                artifact => $artifact,
                jit => $jit,
                osr => $osr,
                inline_cache => {
                    lookup => $cache_lookup,
                    update => $cache_update,
                },
            };
            $self->{profile_store}->record_dispatch({
                region_id => $unit->{region_id},
                region_name => $unit->{region_name},
                status => 'fallback',
                osr_event => $osr->{osr_event},
            });
            next;
        }

        my $result = PAX::NativeRunner->new->run_i64_binary(
            path => $artifact->{executable_path},
            left => $left,
            right => $right,
        );

        my $cache_update = $self->{inline_cache}->update(
            site => $cache_site,
            class_key => 'main',
            method => $method,
            target_region_id => $unit->{region_id},
            target_region_name => $unit->{region_name},
        );
        my $event = {
            status => $result->{status} eq 'ok' ? 'native' : 'fallback',
            entrypoint => $entrypoint,
            region_id => $unit->{region_id},
            region_name => $unit->{region_name},
            args => [$left + 0, $right + 0],
            requested_region => $region_name,
            result => $result,
            artifact => $artifact,
            attempts => \@attempts,
            baseline_match => $manifest->{runtime}{baseline_match},
            jit => $jit,
            osr => $osr,
            inline_cache => {
                lookup => $cache_lookup,
                update => $cache_update,
            },
            aot_plan => $aot_plan,
        };
        $self->{profile_store}->record_dispatch({
            region_id => $unit->{region_id},
            region_name => $unit->{region_name},
            status => $event->{status},
            osr_event => $osr->{osr_event},
        });
        $event->{aot_plan} = $self->{aot}->plan(
            manifest => $manifest,
            ssa_units => $ssa,
            profile => _profile_by_region($self->{profile_store}->report),
        );
        return $event;
    }

    my $event = {
        status => 'fallback',
        entrypoint => $entrypoint,
        args => [$left + 0, $right + 0],
        requested_region => $region_name,
        reason => 'no native i64 dispatch candidate succeeded',
        attempts => \@attempts,
        baseline_match => $manifest->{runtime}{baseline_match},
        aot_plan => $aot_plan,
    };
    return $event;
}

sub profile_report {
    my ($self) = @_;
    return $self->{profile_store}->report;
}

sub inline_cache_report {
    my ($self) = @_;
    return $self->{inline_cache}->report;
}

sub _profile_by_region {
    my ($report) = @_;
    my %profile;
    for my $region (@{ $report->{regions} // [] }) {
        $profile{$region->{region}} = $region;
    }
    return \%profile;
}

1;
