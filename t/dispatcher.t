use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::RuntimeDispatcher;

my $fixture = "$FindBin::Bin/fixtures/simple.pl";
my $result = PAX::RuntimeDispatcher->new->dispatch_i64(
    entrypoint => $fixture,
    left => 10,
    right => 32,
);

ok($result->{status}, 'dispatcher returns status');
if ($result->{status} eq 'native') {
    is($result->{result}{value}, 42, 'dispatcher native result');
} else {
    is($result->{status}, 'fallback', 'dispatcher falls back when native unavailable');
    ok($result->{reason} || @{ $result->{attempts} }, 'dispatcher reports fallback reason or attempts');
}

my $multi = "$FindBin::Bin/fixtures/native_leafs.pl";
my $selected = PAX::RuntimeDispatcher->new->dispatch_i64(
    entrypoint => $multi,
    region_name => 'multiply',
    left => 6,
    right => 7,
);
if ($selected->{status} eq 'native') {
    is($selected->{region_name}, 'main::multiply', 'dispatcher selects requested region');
    is($selected->{result}{value}, 42, 'dispatcher executes selected region');
} else {
    is($selected->{status}, 'fallback', 'selected region falls back when native unavailable');
}

my $missing = PAX::RuntimeDispatcher->new->dispatch_i64(
    entrypoint => $multi,
    region_name => 'missing_region',
    left => 1,
    right => 2,
);
is($missing->{status}, 'fallback', 'missing region falls back');
like($missing->{reason}, qr/requested region not found/, 'missing region reason reported');

done_testing;
