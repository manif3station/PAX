use strict;
use warnings;
use Test::More;
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/../lib";

use PAX::OSR;
use PAX::HotRegionJIT;
use PAX::ProfileStore;
use PAX::Compatibility;
use PAX::RegionSelector;

=pod

=head1 NAME

t/cov_mib_planners.t - coverage tests for the small planner modules

=head1 WHY IT EXISTS

PAX::OSR, PAX::HotRegionJIT, PAX::ProfileStore, PAX::Compatibility and
PAX::RegionSelector are pure data-in/data-out modules whose every branch and
condition outcome must be exercised to keep full coverage of lib/.

=head1 DESCRIPTION

Each section feeds fabricated inputs that drive every default (//) and every
branch of the module under test and asserts on the returned structures.

=cut

# --- PAX::OSR ---------------------------------------------------------------
{
    my $default = PAX::OSR->new;
    is($default->{threshold}, 2, 'OSR default threshold');
    my $osr = PAX::OSR->new(threshold => 3);
    is($osr->{threshold}, 3, 'OSR explicit threshold');

    my $none = $osr->evaluate;
    is($none->{status}, 'not_applicable', 'OSR with no arguments is not applicable');

    my $other = $osr->evaluate(ssa_unit => { native_shape => {}, deopt => { safepoint => 'sp' } }, profile => {});
    is($other->{status}, 'not_applicable', 'OSR empty shape not applicable');
    is($other->{safepoint}, 'sp', 'OSR carries safepoint');

    my $loop = { native_shape => { kind => 'i64_sum_loop' }, deopt => { safepoint => 'sp2' } };
    is($osr->evaluate(ssa_unit => $loop, profile => { dispatches => 0 })->{status}, 'observe', 'OSR observes below threshold');
    my $promote = $osr->evaluate(ssa_unit => $loop, profile => { dispatches => 2 });
    is($promote->{status}, 'promote', 'OSR promotes at threshold');
    is($promote->{safepoint}, 'sp2', 'OSR promote safepoint');

    my $nested = { source => { native_shape => { kind => 'i64_sum_loop' } } };
    is($osr->evaluate(ssa_unit => $nested, profile => { dispatches => 9 })->{status}, 'promote', 'OSR reads nested source shape');

    is($osr->retirement->{reason}, 'guard invalidated promoted OSR region', 'OSR default retirement reason');
    my $ret = $osr->retirement(reason => 'because', safepoint => 'spx');
    is($ret->{reason}, 'because', 'OSR explicit retirement reason');
    is($ret->{safepoint}, 'spx', 'OSR retirement safepoint');
    is($ret->{osr_event}, 'retire', 'OSR retirement event');
}

# --- PAX::HotRegionJIT ------------------------------------------------------
{
    is(PAX::HotRegionJIT->new->{threshold}, 2, 'JIT default threshold');
    my $jit = PAX::HotRegionJIT->new(threshold => 3);
    is($jit->{threshold}, 3, 'JIT explicit threshold');

    my $barrier = $jit->decision;
    is($barrier->{status}, 'barrier', 'JIT no unit is a barrier');
    ok(!$barrier->{hot}, 'JIT barrier is not hot');

    is($jit->decision(ssa_unit => { native_shape => {} }, profile => {})->{status}, 'barrier', 'JIT empty shape barrier');

    my $unit = { native_shape => { kind => 'x' } };
    my $observe = $jit->decision(ssa_unit => $unit, profile => { dispatches => 0 });
    is($observe->{status}, 'observe', 'JIT observes below threshold');
    is($observe->{tier}, 'interpreter', 'JIT observe tier');
    my $promote = $jit->decision(ssa_unit => $unit, profile => { dispatches => 5 });
    is($promote->{status}, 'promote', 'JIT promotes at threshold');
    ok($promote->{hot}, 'JIT promote is hot');
    is($jit->decision(ssa_unit => { source => { native_shape => { kind => 'y' } } }, profile => {})->{status}, 'observe', 'JIT nested shape');

    is($jit->retirement->{reason}, 'native region retired', 'JIT default retirement reason');
    my $ret = $jit->retirement(reason => 'r', region_id => 'id', region_name => 'nm');
    is_deeply([@$ret{qw(reason region_id region_name)}], [qw(r id nm)], 'JIT explicit retirement');
}

# --- PAX::ProfileStore ------------------------------------------------------
{
    is(PAX::ProfileStore->new->{threshold}, 2, 'store default threshold');
    my $store = PAX::ProfileStore->new(threshold => 3);
    is($store->{threshold}, 3, 'store explicit threshold');

    $store->record_dispatch({ region_name => 'a', status => 'native', osr_event => 'promote' });
    $store->record_dispatch({ region_id => 'idonly', status => 'deopt', osr_event => 'retire' });
    $store->record_dispatch({ status => 'fallback' });
    $store->record_dispatch({});
    $store->record_dispatch({ region_name => 'a', status => 'native' });
    $store->record_dispatch({ region_name => 'a', status => 'native' });

    my $report = $store->report;
    is($report->{threshold}, 3, 'report threshold');
    my %by = map { $_->{region} => $_ } @{ $report->{regions} };
    is_deeply([sort keys %by], [qw(a idonly unknown)], 'regions keyed by name, id and unknown');
    is($by{a}{native}, 3, 'native counted');
    ok($by{a}{hot}, 'region a is hot');
    is($by{a}{osr_promotions}, 1, 'promotion counted');
    is($by{idonly}{deopt}, 1, 'deopt counted');
    is($by{idonly}{fallback}, 1, 'deopt is also fallback');
    is($by{idonly}{osr_retirements}, 1, 'retirement counted');
    ok(!$by{idonly}{hot}, 'idonly is cold');
    is($by{unknown}{fallback}, 2, 'undef and other status are fallback');
}

# --- PAX::Compatibility -----------------------------------------------------
{
    my $empty = PAX::Compatibility->new;
    is_deeply($empty->{capture}, {}, 'compat default capture');
    is($empty->{baseline_match}, 0, 'compat default baseline');
    is($empty->report->{level}, 'D', 'compat empty capture is level D');

    my $failed = PAX::Compatibility->new(capture => { status => 'error', source_features => { tie => 1, autoload => 0 } })->report;
    is($failed->{level}, 'D', 'failed capture level D');
    is(scalar @{ $failed->{barriers} }, 1, 'failed capture still reports barriers');
    is($failed->{barriers}[0]{policy}, 'barrier', 'tie policy');

    my $mismatch = PAX::Compatibility->new(capture => { status => 'ok' })->report;
    is($mismatch->{level}, 'C', 'baseline mismatch level C');
    ok(!$mismatch->{acceleration_supported}, 'level C has no acceleration');

    my $features = { map { $_ => 1 } qw(string_eval autoload tie overload typeglob xs_loader local_dynamic bogus_feature) };
    my $b = PAX::Compatibility->new(capture => { status => 'ok', source_features => $features }, baseline_match => 1)->report;
    is($b->{level}, 'B', 'barriers give level B');
    ok($b->{acceleration_supported}, 'level B supports acceleration');
    my %pol = map { $_->{feature} => $_ } @{ $b->{barriers} };
    is($pol{string_eval}{policy}, 'fallback', 'string_eval policy');
    is($pol{bogus_feature}{policy}, 'unknown', 'unknown feature policy');
    is($pol{bogus_feature}{reason}, 'unknown dynamic feature', 'unknown feature reason');
    is(scalar keys %pol, 8, 'every enabled feature reported');

    my $a = PAX::Compatibility->new(capture => { status => 'ok' }, baseline_match => 1)->report;
    is($a->{level}, 'A', 'no barriers level A');
    is_deeply($a->{barriers}, [], 'level A has no barriers');
}

# --- PAX::RegionSelector ----------------------------------------------------
{
    is_deeply(PAX::RegionSelector->new->select, { selected => [], rejected => [] }, 'selector with no manifest');
    is_deeply(PAX::RegionSelector->new(manifest => {})->select->{selected}, [], 'selector without optree units');

    my $shape = { kind => 'i64_binary_leaf' };
    my @subs = (
        { available => 1 },
        { name => 'main::BEGIN', available => 1 },
        { name => 'main::_private', available => 1 },
        { name => 'main::encode_json', available => 1 },
        { name => 'main::broken', available => 0, reason => 'no optree' },
        { name => 'main::nodetail', available => 0 },
        { name => 'main::good', available => 1, root_class => 'B::LISTOP', start_class => 'B::COP', optree_ops => [1], native_shape => $shape },
        { name => 'PAX::Fixture::thing', available => 1 },
        { name => 'Foo::BEGIN', available => 1, closure_descriptor => { file => 'lib/Foo.pm' } },
        { name => 'Foo::nofile', available => 1 },
        { name => 'Foo::dash', available => 1, closure_descriptor => { file => '-' } },
        { name => 'Foo::txt', available => 1, closure_descriptor => { file => 'foo.txt' } },
        { name => 'Foo::shaped', available => 1, native_shape => $shape, closure_descriptor => { file => '/usr/lib/Shaped.pm' } },
        { name => 'Foo::usr', available => 1, closure_descriptor => { file => '/usr/lib/Plain.pm' } },
        { name => 'Foo::entry', available => 1, closure_descriptor => { file => '/opt/app/main.pl' } },
        { name => 'Foo::other', available => 1, closure_descriptor => { file => '/opt/app/other.pm' } },
        { name => 'Foo::rel', available => 1, closure_descriptor => { file => 'lib/Rel.pm' } },
    );
    my $manifest = { source_entrypoint => '/opt/app/main.pl', runtime => { baseline_match => 1 }, optree_units => { subs => \@subs } };
    my $result = PAX::RegionSelector->new(manifest => $manifest)->select;
    my @names = map { $_->{name} } @{ $result->{selected} };
    is_deeply(\@names, [qw(main::good PAX::Fixture::thing Foo::BEGIN Foo::shaped Foo::entry Foo::rel)], 'selected application subs');
    is_deeply([ map { $_->{name} } @{ $result->{rejected} } ], [qw(main::broken main::nodetail)], 'rejected subs');
    is($result->{rejected}[0]{detail}, 'no optree', 'rejection detail');
    is($result->{rejected}[1]{detail}, '', 'rejection default detail');
    is($result->{selected}[0]{id}, 'region-0001', 'region ids');
    is($result->{selected}[0]{kind}, 'candidate_leaf_function', 'leaf kind');
    is($result->{selected}[2]{kind}, 'compile_phase_hook', 'hook kind');
    is($result->{selected}[0]{lowering_status}, 'ready', 'guarded support is ready');
    like($result->{selected}[0]{reason}, qr/can enter HIR/, 'baseline match reason');
    is($result->{selected}[0]{source}{native_shape}, $shape, 'native shape propagated');

    # No entrypoint: the entrypoint-equality shortcut is skipped and absolute files are rejected.
    my $noentry = { runtime => {}, optree_units => { subs => [
        { name => 'Foo::abs', available => 1, closure_descriptor => { file => '/opt/app/main.pl' } },
        { name => 'Foo::rel', available => 1, closure_descriptor => { file => 'lib/Rel.pm' } },
    ] } };
    my $second = PAX::RegionSelector->new(manifest => $noentry)->select;
    is_deeply([ map { $_->{name} } @{ $second->{selected} } ], ['Foo::rel'], 'no entrypoint rejects absolute files');
    ok(!PAX::RegionSelector::_is_application_sub({}, {}), 'nameless sub is not an application sub');
    like($second->{selected}[0]{reason}, qr/baseline mismatch/, 'baseline mismatch reason');
}

done_testing;
