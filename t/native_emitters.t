use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::Capture;
use PAX::Manifest;
use PAX::RegionSelector;
use PAX::HIR;
use PAX::GuardedSSA;
use PAX::Tier1;
use PAX::NativeRunner;

my $fixture = "$FindBin::Bin/fixtures/native_leafs.pl";
my $capture = PAX::Capture->new(mode => 'live')->capture($fixture);
my $manifest = PAX::Manifest->new(capture => $capture)->to_hash;
my $regions = PAX::RegionSelector->new(manifest => $manifest)->select;
my $hir = PAX::HIR->new(manifest => $manifest, regions => $regions->{selected})->lower_all;
my $ssa = PAX::GuardedSSA->new(hir_units => $hir)->build_all;

my %expected = (
    'main::add' => 5,
    'main::subtract' => -1,
    'main::multiply' => 6,
    'main::greater_than' => 0,
);

my $tier1 = PAX::Tier1->new;
my $runner = PAX::NativeRunner->new;
my $seen = 0;

for my $unit (@$ssa) {
    next if !exists $expected{ $unit->{region_name} };
    $seen++;
    is(($unit->{native_shape}{kind} // ''), 'i64_binary_leaf', "HIR native shape carried into SSA for $unit->{region_name}")
        if ($unit->{status} // '') eq 'ssa';
    my $artifact = $tier1->compile($unit);
    ok($artifact->{status}, "artifact status for $unit->{region_name}");
    if ($artifact->{status} eq 'native_artifact') {
        is($artifact->{entry_kind}, 'native_i64_leaf', "native leaf emitted for $unit->{region_name}");
        my $run = $runner->run_i64_binary(
            path => $artifact->{executable_path},
            left => 2,
            right => 3,
        );
        is($run->{value}, $expected{ $unit->{region_name} }, "native result for $unit->{region_name}");
    }
}

is($seen, 4, 'all native leaf fixture functions were selected');
done_testing;
