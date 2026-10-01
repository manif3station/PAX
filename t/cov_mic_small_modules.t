use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::ArtifactCache;
use PAX::Corpus;
use PAX::DeoptEngine;
use PAX::Differential;
use PAX::GuardManager;
use PAX::GuardedSSA;
use PAX::HIR;
use PAX::InlineCache;
use PAX::Manifest;
use PAX::Mode;
use PAX::ProfileGuidedAOT;
use PAX::Runtime::Value;
use PAX::Backend::Tier1CraneliftEquivalent;

=pod

=head1 NAME

t/cov_mic_small_modules.t - branch and condition coverage for the small core modules

=head1 DESCRIPTION

Exercises both sides of every defaulting operator and ternary in the small
planning/runtime helper modules (ArtifactCache, Corpus, DeoptEngine,
Differential, GuardManager, GuardedSSA, HIR, InlineCache, Manifest, Mode,
ProfileGuidedAOT, Runtime::Value and the tier-1 backend stub).

=head1 WHY IT EXISTS

The project requires full Devel::Cover coverage of lib/, and these modules are
dense with C<//> defaults whose fallback side was never reached.

=cut

my $tmp = tempdir('pax-cov-mic-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# ---------------------------------------------------------------- ArtifactCache
{
    my $default = PAX::ArtifactCache->new;
    is($default->{root}, '.pax/cache', 'ArtifactCache defaults its root');

    my $cache = PAX::ArtifactCache->new(root => File::Spec->catdir($tmp, 'cache'));
    my $full = {
        schema_version => 1,
        source_entrypoint => 'a.pl',
        capture => { mode => 'live' },
        module_graph => { modules => ['A.pm', 'B.pm'] },
        runtime => { archname => 'x86', perl_config_version => '5.42.0', pax_abi_stamp => 'stamp' },
    };
    my $art = { region_id => 'r1' };
    my $m = $cache->metadata_for($full, $art);
    like($m->{cpu_target}, qr/-x86$/, 'archname used');
    ok($m->{environment_bound}, 'live capture is environment bound');

    my $bare = { capture => { mode => 'hermetic' }, runtime => {}, module_graph => {} };
    my $m2 = $cache->metadata_for($bare, {});
    like($m2->{cpu_target}, qr/-unknown$/, 'unknown archname fallback');
    ok(!$m2->{environment_bound}, 'non-live capture is not environment bound');
    my $m3 = $cache->metadata_for({ runtime => {}, module_graph => { modules => [] } }, {});
    ok(!$m3->{environment_bound}, 'missing capture mode is not environment bound');

    eval { $cache->write_artifact(artifact => $art) };
    like($@, qr/manifest required/, 'manifest required');
    eval { $cache->write_artifact(manifest => $full) };
    like($@, qr/artifact required/, 'artifact required');

    my $w = $cache->write_artifact(manifest => $full, artifact => $art);
    ok(-f $w->{path}, 'artifact written');
    my $back = $cache->read_artifact($w->{path});
    is($back->{artifact}{region_id}, 'r1', 'artifact read back');
    eval { $cache->read_artifact(File::Spec->catfile($tmp, 'nope.json')) };
    like($@, qr/cannot read/, 'read failure dies');

    my $blocked = PAX::ArtifactCache->new(root => File::Spec->catdir($tmp, 'blocked'));
    my $id = $blocked->metadata_for($full, $art)->{artifact_id};
    make_path(File::Spec->catdir($tmp, 'blocked', substr($id, 0, 2), "$id.json"));
    eval { $blocked->write_artifact(manifest => $full, artifact => $art) };
    like($@, qr/cannot write/, 'write failure dies');

    eval { $cache->validate_metadata(metadata => {}) };
    like($@, qr/manifest required/, 'validate needs manifest');
    eval { $cache->validate_metadata(manifest => {}) };
    like($@, qr/metadata required/, 'validate needs metadata');

    my $ok = $cache->validate_metadata(manifest => $full, metadata => { %$m, snapshot_schema_version => 1 });
    ok($ok->{valid}, 'matching metadata valid');
    my $bad = $cache->validate_metadata(manifest => $full, metadata => {});
    is_deeply($bad->{errors},
        [qw(perl_version_mismatch abi_stamp_mismatch snapshot_schema_mismatch capture_mode_mismatch)],
        'empty metadata fails every check');
    my $bad2 = $cache->validate_metadata(manifest => {}, metadata => { perl_version => 'x' });
    ok(!$bad2->{valid}, 'empty manifest vs populated metadata invalid');
    my $bad3 = $cache->validate_metadata(manifest => { runtime => { perl_config_version => 'y', pax_abi_stamp => 'z' }, schema_version => 3, capture => { mode => 'live' } },
        metadata => { perl_version => 'y', perl_abi_stamp => 'z', snapshot_schema_version => 3 });
    is_deeply($bad3->{errors}, ['capture_mode_mismatch'], 'only capture mode differs');
}

# ---------------------------------------------------------------- Corpus
{
    my @captures;
    my @modes;
    no warnings 'redefine';
    local *PAX::Capture::capture = sub { my ($self, $path) = @_; push @modes, $self->{mode}; return shift @captures };
    my $mpath = File::Spec->catfile($tmp, 'corpus.json');
    open my $fh, '>', $mpath or die $!;
    print {$fh} JSON::PP->new->encode({ cases => [
        { id => 'a', path => 'a.pl', expected_level => 'A' },
        { id => 'b', path => 'b.pl', mode => 'hermetic', expected_level => 'A', expected_level_when_baseline_mismatch => 'C' },
        { id => 'c', path => 'c.pl', expected_level => 'A' },
        { id => 'd', path => 'd.pl' },
    ] });
    close $fh;
    my $good = { status => 'ok', runtime => { config_version => '5.42.1' }, capture => {} };
    my $old = { status => 'ok', runtime => { config_version => '5.38.0' }, capture => {}, diagnostics => ['x'] };
    @captures = ($good, $old, $old, $old);
    my $r = PAX::Corpus->new(manifest_path => $mpath)->run;
    is($r->{total}, 4, 'four cases');
    is($r->{failed}, 1, 'one failure');
    ok(!$r->{passed}, 'run not passed');
    is_deeply(\@modes, [qw(live hermetic live live)], 'case mode defaults to live');
    is($r->{results}[1]{expected_level}, 'C', 'mismatch expectation used');
    ok($r->{results}[1]{passed}, 'mismatch expectation matches');
    ok(!$r->{results}[2]{passed}, 'plain expectation fails on old perl');
    ok($r->{results}[3]{passed}, 'undefined expectation passes');
    is_deeply($r->{results}[1]{diagnostics}, ['x'], 'diagnostics kept');

    # compatibility report without barriers key
    local *PAX::Compatibility::report = sub { return { level => 'A', reason => 'r' } };
    @captures = ($good);
    open $fh, '>', $mpath or die $!;
    print {$fh} '{"cases":[{"id":"z","path":"z.pl","expected_level":"A"}]}';
    close $fh;
    my $r2 = PAX::Corpus->new(manifest_path => $mpath)->run;
    is_deeply($r2->{results}[0]{barriers}, [], 'barriers default to empty');
    ok($r2->{passed}, 'all passed');

    # A manifest without diagnostics falls back to an empty list.
    local *PAX::Manifest::to_hash = sub { return { compatibility => { level => 'A' }, runtime => { baseline_match => 1 } } };
    @captures = ({});
    open $fh, '>', $mpath or die $!;
    print {$fh} '{"cases":[{"id":"z","path":"z.pl"}]}';
    close $fh;
    my $r4 = PAX::Corpus->new(manifest_path => $mpath)->run;
    is_deeply($r4->{results}[0]{diagnostics}, [], 'diagnostics default to empty');

    open $fh, '>', $mpath or die $!;
    print {$fh} '{}';
    close $fh;
    my $r3 = PAX::Corpus->new(manifest_path => $mpath)->run;
    is($r3->{total}, 0, 'no cases key tolerated');

    eval { PAX::Corpus->new(manifest_path => File::Spec->catfile($tmp, 'missing.json'))->run };
    like($@, qr/cannot read corpus manifest/, 'missing manifest dies');
}

# ---------------------------------------------------------------- DeoptEngine
{
    my $d = PAX::DeoptEngine->new;
    my $bare = $d->reconstruct;
    is($bare->{reason}, 'guard_failed', 'default reason');
    is($bare->{frame}{wantarray}, 0, 'default scalar context');
    is_deeply($bare->{materialised}, [], 'no materialise default');
    my $full = $d->reconstruct(
        ssa_unit => { region_id => 'r', region_name => 'n', deopt => { safepoint => 's', materialise => ['x'] } },
        reason => 'why', guard => { guard_id => 'g', invalidation_key => 'k' },
        args => [1, 2], context => 'list', lexicals => { a => 1 }, closure_environment => { c => 1 },
        exception_handlers => ['h'], exception_state => 'e', caller => 'c', debugger_stack => ['d'],
        interpreter_result => 5,
    );
    is($full->{frame}{wantarray}, 1, 'list context');
    is_deeply($full->{frame}{lexicals}, { a => 1 }, 'lexicals passed');
    is_deeply($full->{frame}{closure_environment}, { c => 1 }, 'closure env passed');
    is_deeply($full->{frame}{exception_handlers}, ['h'], 'handlers passed');
    is_deeply($full->{frame}{debugger_stack}, ['d'], 'debugger stack passed');
    is_deeply($full->{materialised}, ['x'], 'materialise passed');
    is($d->reconstruct(context => 'void')->{frame}{wantarray}, undef, 'void context');
    is(PAX::DeoptEngine::_wantarray_for_context(undef), undef, 'undef context');
}

# ---------------------------------------------------------------- Differential
{
    my $script = File::Spec->catfile($tmp, 'ok.pl');
    open my $fh, '>', $script or die $!;
    print {$fh} "print qq{hi\\n};\n";
    close $fh;
    my $bad = File::Spec->catfile($tmp, 'bad.pl');
    open $fh, '>', $bad or die $!;
    print {$fh} "print STDERR qq{oops\\n}; exit 3;\n";
    close $fh;

    my $diff = PAX::Differential->new(pax_bin => 'pax');
    is($diff->{pax_bin}, 'pax', 'pax_bin stored');

    no warnings 'redefine';
    local *PAX::Capture::capture = sub { return { status => 'ok' } };
    my $r = $diff->compare_capture($script);
    ok($r->{pass}, 'good script passes');
    is($r->{comparison}{stock_stderr_present}, JSON::PP::false(), 'no stderr');

    local *PAX::Capture::capture = sub { return { status => 'ok' } };
    my $r2 = $diff->compare_capture($bad);
    ok(!$r2->{pass}, 'failing stock script fails');
    is($r2->{comparison}{stock_exit}, 3, 'stock exit code');
    ok($r2->{comparison}{stock_stderr_present}, 'stderr present');

    local *PAX::Capture::capture = sub { return undef };
    my $r3 = $diff->compare_capture($script);
    is($r3->{comparison}{pax_exit}, 1, 'undef capture is failure');

    local *PAX::Capture::capture = sub { return { status => 'error' } };
    my $r4 = $diff->compare_capture($script);
    is($r4->{comparison}{pax_exit}, 1, 'capture with an error status is failure');

    local *PAX::Capture::capture = sub { die "boom\n" };
    my $r5 = $diff->compare_capture($script);
    is($r5->{comparison}{pax_exit}, 1, 'dying capture is failure');
    ok($r5->{comparison}{pax_stderr_present}, 'capture error reported');
    ok(!$r5->{pass}, 'overall fail');

    # A handle already at EOF makes a slurping read return undef.
    {
        local *PAX::Differential::open3 = sub {
            open $_[0], '<', '/dev/null' or die $!;
            my ($a, $b) = ("x\n", "y\n");
            open $_[1], '<', \$a or die $!;
            open $_[2], '<', \$b or die $!;
            my $drain1 = readline($_[1]);
            my $drain2 = readline($_[2]);
            return 999999;
        };
        my $r = PAX::Differential::_run('nothing');
        is($r->{stdout}, '', 'undef stdout normalised');
        is($r->{stderr}, '', 'undef stderr normalised');
    }

    # An empty child output exercises the "// ''" fallbacks of _run.
    my $empty = PAX::Differential::_run($^X, '-e', '1');
    is($empty->{stdout}, '', 'empty stdout');
    is($empty->{stderr}, '', 'empty stderr');
}

# ---------------------------------------------------------------- GuardManager
{
    my $g = PAX::GuardManager->new;
    my $unit = { region_id => 'r', guards => [{ id => 'g1', invalidation_key => 'k1' }], deopt => { safepoint => 'sp' } };
    is($g->validate_region({ region_id => 'r' }), 1, 'no guards passes');
    my $d = $g->validate_or_deopt($unit);
    is($d->{status}, 'deopt', 'missing epoch deopts');
    is($d->{fallback}{reason}, 'missing_epoch', 'reason from telemetry');
    my $gm = PAX::GuardManager->new(epochs => { k1 => 1 });
    is($gm->validate_or_deopt($unit)->{status}, 'native_allowed', 'epoch present');
    $gm->invalidate_epoch('k1');
    is($gm->validate_or_deopt($unit, args => [1], context => 'list', interpreter_result => 9)->{status}, 'deopt', 'invalidated');
    is($gm->telemetry->[-1]{status}, 'failed', 'telemetry recorded');

    # Defaults for a missing last telemetry entry.
    my $stub = PAX::GuardManager->new;
    no warnings 'redefine';
    local *PAX::GuardManager::validate_region = sub { 0 };
    my $d2 = $stub->validate_or_deopt({ region_id => 'q', deopt => { safepoint => 'x' } });
    is($d2->{fallback}{reason}, 'guard_failed', 'default reason without telemetry');
}

# ---------------------------------------------------------------- GuardedSSA
{
    my $s = PAX::GuardedSSA->new;
    is_deeply($s->build_all, [], 'empty by default');
    my $unit = $s->build_unit({ region_id => 'r', required_epochs => ['e1'], deopt_anchors => ['a'] });
    is($unit->{status}, 'ssa', 'normal unit');
    is($unit->{guards}[0]{compatibility_classification}, 'guarded', 'guarded');
    is_deeply($unit->{deopt}{anchors}, ['a'], 'anchors kept');
    my $fb = $s->build_unit({ region_id => 'r', status => 'fallback', required_epochs => ['e1'] });
    is($fb->{status}, 'fallback', 'fallback unit');
    is($fb->{guards}[0]{compatibility_classification}, 'fallback', 'fallback guard');
    is($fb->{blocks}[0]{terminator}, 'deopt_to_interpreter', 'fallback terminator');
    is_deeply($fb->{deopt}{anchors}, [], 'no anchors default');
    my $none = $s->build_unit({ region_id => 'r' });
    is_deeply($none->{guards}, [], 'no epochs');
    my $all = PAX::GuardedSSA->new(hir_units => [{ region_id => 'a' }, { region_id => 'b' }])->build_all;
    is(scalar @$all, 2, 'build_all maps units');
}

# ---------------------------------------------------------------- HIR
{
    my $h = PAX::HIR->new;
    is_deeply($h->lower_all, [], 'no regions');
    my $blocked = $h->lower_region({ id => 'r', name => 'n', lowering_status => 'blocked', reason => 'why' });
    is($blocked->{status}, 'fallback', 'blocked fallback');
    is($blocked->{diagnostics}[0]{message}, 'why', 'diagnostic');
    is($blocked->{deopt_anchors}[0]{reason}, 'why', 'blocked reason');
    is_deeply($blocked->{required_epochs}, [], 'epochs default');
    my $native = $h->lower_region({ id => 'r', name => 'n', source => { native_shape => 'loop' }, required_epochs => ['e'] });
    is($native->{native_shape}, 'loop', 'native shape');
    is($native->{graph}{blocks}[0]{ops}[1]{op}, 'native_candidate', 'native op');
    is($native->{deopt_anchors}[0]{reason}, 'guard_failure', 'guard failure reason');
    is_deeply($native->{required_epochs}, ['e'], 'epochs kept');
    my $plain = $h->lower_region({ id => 'r', name => 'n', source => {} });
    is($plain->{graph}{blocks}[0]{ops}[1]{op}, 'call_reference_equivalent', 'plain op');
    my $units = PAX::HIR->new(regions => [{ id => 'a', name => 'a', source => {} }])->lower_all;
    is(scalar @$units, 1, 'lower_all lowers');
}

# ---------------------------------------------------------------- InlineCache
{
    my $c = PAX::InlineCache->new;
    is($c->{max_polymorphic}, 4, 'default polymorphism');
    my $miss = $c->lookup;
    is($miss->{status}, 'miss', 'default miss');
    is($miss->{site}, 'default', 'default site');
    is($c->lookup(region_name => 'rn')->{method}, 'rn', 'region_name as method');
    $c->update(method => 'm', target_region_id => 1, target_region_name => 'one');
    is($c->lookup(method => 'm')->{status}, 'hit', 'hit');
    my $miss2 = $c->lookup(method => 'other');
    is($miss2->{status}, 'miss', 'different method misses');
    my $miss3 = $c->lookup(method => 'm', class_key => 'K');
    is($miss3->{status}, 'miss', 'different class misses');
    my $up = $c->update(region_name => 'rn2', target_region_id => 2);
    is($up->{status}, 'updated', 'update adds');
    my $re = $c->update(method => 'm', target_region_id => 7);
    is($re->{target_region_id}, 7, 'update replaces');
    $c->update(class_key => 'K', method => 'm', target_region_id => 3);
    my $anon = PAX::InlineCache->new;
    $anon->update(site => 's');
    is($anon->lookup(site => 's')->{status}, 'hit', 'method defaults to empty string');
    my $mono = PAX::InlineCache->new(max_polymorphic => 1);
    $mono->update(method => 'a');
    my $mega = $mono->update(method => 'b');
    is($mega->{status}, 'megamorphic', 'megamorphic update');
    is($mono->lookup(method => 'a')->{status}, 'megamorphic', 'megamorphic hit');
    is($mono->lookup(method => 'zz')->{status}, 'megamorphic', 'megamorphic miss');
    is($mono->report->{max_polymorphic}, 1, 'report');
    ok(exists $mono->report->{sites}{default}, 'report sites');
}

# ---------------------------------------------------------------- Manifest
{
    my $bare = PAX::Manifest->new->to_hash;
    is($bare->{runtime}{baseline_match}, JSON::PP::false(), 'bare manifest has no baseline match');
    is_deeply($bare->{module_graph}{modules}, [], 'no modules');
    is_deeply($bare->{package_state}{packages}, {}, 'no packages');
    is_deeply($bare->{optree_units}{subs}, [], 'no subs');
    is_deeply($bare->{method_resolution}, {}, 'no method resolution');
    is_deeply($bare->{regex_metadata}, [], 'no regex metadata');
    is_deeply($bare->{compile_phase_events}, [], 'no phase events');
    is_deeply($bare->{source_features}, {}, 'no features');
    is_deeply($bare->{diagnostics}, [], 'no diagnostics');
    is($bare->{runtime_epochs}{loaded_modules}, 0, 'zero modules');

    my $cap = {
        status => 'ok', mode => 'live', source_entrypoint => 'a.pl',
        runtime => { config_version => '5.42.0', archname => 'x', config => { a => 1, b => undef } },
        capture => {
            loaded_files => ['A.pm'], package_shapes => { P => 1 }, method_resolution => { m => 1 },
            regex_metadata => ['r'], compile_phase_events => ['e'],
            sub_optrees => [
                { name => 'f', pad_layout => 'pad', closure_descriptor => 'cd' },
                { pad_layout => 'ignored' },
            ],
        },
        source_features => { f => 1 }, diagnostics => ['d'],
    };
    my $m = PAX::Manifest->new(capture => $cap)->to_hash;
    is($m->{runtime}{baseline_match}, JSON::PP::true(), '5.42 baseline matches');
    is_deeply($m->{lexical_pads}{subs}, { f => 'pad' }, 'named subs only in pad map');
    is_deeply($m->{closure_descriptors}{subs}, { f => 'cd' }, 'closure map');
    is($m->{runtime_epochs}{loaded_modules}, 1, 'module count');
    is_deeply($m->{diagnostics}, ['d'], 'diagnostics kept');
    is_deeply($m->{method_resolution}, { m => 1 }, 'method resolution kept');
    isnt(PAX::Manifest::_abi_stamp({}), PAX::Manifest::_abi_stamp({ config_version => 'x', archname => 'y' }), 'stamp varies');
}

# ---------------------------------------------------------------- Mode
{
    is(PAX::Mode->policy->{telemetry}, 'verbose', 'default dev');
    is(PAX::Mode->policy('ci')->{undeclared_inputs}, 'fail', 'ci');
    is(PAX::Mode->policy('prod')->{telemetry}, 'low_overhead', 'prod');
    is(PAX::Mode->policy('bogus')->{telemetry}, 'verbose', 'unknown falls back to dev');
}

# ---------------------------------------------------------------- ProfileGuidedAOT
{
    my $p = PAX::ProfileGuidedAOT->new;
    is($p->{threshold}, 2, 'default threshold');
    my $none = $p->plan;
    is($none->{status}, 'no_hot_native_regions', 'empty plan');
    my $units = [
        { region_id => 'id1', region_name => 'hot', native_shape => 'loop' },
        { region_id => 'id2', source => { native_shape => 'loop' } },
        { region_id => 'id3', region_name => 'cold', native_shape => 'loop' },
        { region_id => 'id4', region_name => 'plain' },
        { region_name => 'noid', native_shape => 'x' },
    ];
    my $plan = $p->plan(
        manifest => { runtime => { pax_abi_stamp => 's' }, source_entrypoint => 'e' },
        ssa_units => $units,
        profile => { hot => { dispatches => 5 }, id2 => { dispatches => 2 }, cold => { dispatches => 1 }, plain => { dispatches => 9 }, noid => { dispatches => 3 } },
    );
    is($plan->{status}, 'planned', 'planned');
    is_deeply([map { $_->{region_id} } @{ $plan->{artifacts} }], ['id1', 'id2', undef], 'hot native regions chosen');
    {
        local $SIG{__WARN__} = sub { };
        my $anon = PAX::ProfileGuidedAOT->new(threshold => 0)->plan(ssa_units => [{ native_shape => 'y' }]);
        is(scalar @{ $anon->{artifacts} }, 1, 'unit without name or id still planned');
    }
    my $bare = $p->plan(ssa_units => [{ region_id => 'x', native_shape => 'y' }], profile => { x => { dispatches => 4 } });
    is($bare->{artifacts}[0]{profile_dispatches}, 4, 'bare manifest plan');
    my $t = PAX::ProfileGuidedAOT->new(threshold => 0);
    is(scalar @{ $t->plan(ssa_units => [{ region_id => 'x', native_shape => 'y' }])->{artifacts} }, 1, 'threshold zero allows empty profile');
}

# ---------------------------------------------------------------- Runtime::Value
{
    my $f = PAX::Runtime::Value->fast_int('7');
    is($f->as_hash->{escaped}, 0, 'fast int not escaped');
    my $mat = $f->materialise;
    is($mat->{kind}, 'PerlValue', 'materialised');
    is($mat->materialise, $mat, 'perl value materialises to itself');
    is(PAX::Runtime::Value->perl_value([])->{type}, 'ARRAY', 'ref type');
    is(PAX::Runtime::Value->perl_value('x')->{type}, 'scalar', 'plain scalar type');
    is($mat->as_hash->{escaped}, 1, 'escaped');
}

# ---------------------------------------------------------------- Tier1CraneliftEquivalent
{
    is(PAX::Backend::Tier1CraneliftEquivalent->new->metadata->{name}, 'cranelift-equivalent-low-latency-backend', 'default name');
    is(PAX::Backend::Tier1CraneliftEquivalent->new(name => 'n')->metadata->{name}, 'n', 'custom name');
}

done_testing;
