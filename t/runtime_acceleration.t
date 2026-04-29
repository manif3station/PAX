use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::Capture;
use PAX::GuardedSSA;
use PAX::HIR;
use PAX::HotRegionJIT;
use PAX::InlineCache;
use PAX::Manifest;
use PAX::OSR;
use PAX::ProfileGuidedAOT;
use PAX::ProfileStore;
use PAX::RegionSelector;
use PAX::RuntimeDispatcher;

my $fixture = "$FindBin::Bin/fixtures/loop_sum.pl";
my $store = PAX::ProfileStore->new(threshold => 2);
my $dispatcher = PAX::RuntimeDispatcher->new(profile_store => $store, threshold => 2);

my $first = $dispatcher->dispatch_i64(
    entrypoint => $fixture,
    region_name => 'sum_to_n',
    left => 10,
    right => 0,
);
my $first_attempt = $first->{attempts}[0] // $first;
ok($first_attempt->{jit}, 'dispatch reports JIT decision');
ok($first_attempt->{inline_cache}, 'dispatch reports inline-cache state');

my $second = $dispatcher->dispatch_i64(
    entrypoint => $fixture,
    region_name => 'sum_to_n',
    left => 10,
    right => 0,
);
my $second_attempt = $second->{attempts}[0] // $second;
ok($second_attempt->{osr}, 'dispatch reports OSR decision');
is($second_attempt->{osr}{status}, 'promote', 'loop dispatch promotes through OSR after threshold');

my %profile = map { $_->{region} => $_ } @{ $dispatcher->profile_report->{regions} };
ok(($profile{'main::sum_to_n'}{osr_promotions} // 0) >= 1, 'profile records OSR promotion');

my $cache = $dispatcher->inline_cache_report;
ok(keys %{ $cache->{sites} } >= 1, 'inline cache records call site');

my $capture = PAX::Capture->new(mode => 'live')->capture($fixture);
my $manifest = PAX::Manifest->new(capture => $capture)->to_hash;
my $regions = PAX::RegionSelector->new(manifest => $manifest)->select;
my $hir = PAX::HIR->new(manifest => $manifest, regions => $regions->{selected})->lower_all;
my $ssa = PAX::GuardedSSA->new(hir_units => $hir)->build_all;
my $aot = PAX::ProfileGuidedAOT->new(threshold => 2)->plan(
    manifest => $manifest,
    ssa_units => $ssa,
    profile => \%profile,
);
is($aot->{status}, 'planned', 'profile-guided AOT plans hot native region');
ok(@{ $aot->{artifacts} } >= 1, 'AOT plan includes artifact candidate');

my $leaf = "$FindBin::Bin/fixtures/native_leafs.pl";
my $ic = PAX::InlineCache->new(max_polymorphic => 1);
$ic->update(site => 'call', class_key => 'main', method => 'main::add', target_region_id => 'r1', target_region_name => 'main::add');
my $hit = $ic->lookup(site => 'call', class_key => 'main', method => 'main::add');
is($hit->{status}, 'hit', 'inline cache hits stable call target');
$ic->update(site => 'call', class_key => 'main', method => 'main::multiply', target_region_id => 'r2', target_region_name => 'main::multiply');
my $mega = $ic->lookup(site => 'call', class_key => 'main', method => 'main::subtract');
is($mega->{status}, 'megamorphic', 'inline cache marks over-wide site megamorphic');

my $jit = PAX::HotRegionJIT->new(threshold => 2)->decision(
    ssa_unit => $ssa->[0],
    profile => { dispatches => 1 },
);
is($jit->{status}, 'promote', 'hot-region JIT promotes native-shaped region at threshold');

my $osr = PAX::OSR->new(threshold => 2)->evaluate(
    ssa_unit => $ssa->[0],
    profile => { dispatches => 1 },
);
is($osr->{status}, 'promote', 'OSR promotes loop at threshold');

done_testing;

=pod

=head1 NAME

t/runtime_acceleration.t - cover the runtime acceleration behavior exercised by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to cover the runtime acceleration behavior exercised by the PAX test suite.

=cut

