use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::Differential;
use PAX::Benchmark;

my $pax = "$FindBin::Bin/../bin/pax";
my $fixture = "$FindBin::Bin/fixtures/simple.pl";

my $diff = PAX::Differential->new(pax_bin => $pax)->compare_capture($fixture);
ok($diff->{pass}, 'differential capture passes for simple fixture');
is($diff->{comparison}{stock_exit}, 0, 'stock Perl exits cleanly');
is($diff->{comparison}{pax_exit}, 0, 'PAX capture exits cleanly');

my $bench = PAX::Benchmark->new(pax_bin => $pax, iterations => 1)->run_capture_benchmark($fixture);
is($bench->{benchmark_class}, 'capture_overhead', 'benchmark class recorded');
is($bench->{iterations}, 1, 'benchmark iterations recorded');
ok($bench->{mean_seconds} >= 0, 'benchmark mean recorded');
ok(ref $bench->{memory_impact} eq 'HASH', 'capture benchmark records memory impact');
ok(exists $bench->{memory_impact}{delta_rss_kb}, 'capture benchmark records memory delta field');

my $runtime = PAX::Benchmark->new(pax_bin => $pax, iterations => 1)->run_runtime_benchmark($fixture);
is($runtime->{benchmark_class}, 'runtime', 'runtime benchmark class recorded');
ok(defined $runtime->{reference_mean_seconds}, 'reference timing recorded');
ok(defined $runtime->{capture_mean_seconds}, 'capture timing recorded');
ok(exists $runtime->{native_available}, 'native availability recorded');
ok(ref $runtime->{memory_impact} eq 'HASH', 'runtime benchmark records memory impact');

done_testing;

=pod

=head1 NAME

t/validation.t - cover the validation behavior exercised by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to cover the validation behavior exercised by the PAX test suite.

=cut

