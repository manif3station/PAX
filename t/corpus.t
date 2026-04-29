use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::Corpus;
use PAX::Capture;
use PAX::Manifest;

my $manifest = "$FindBin::Bin/corpus.json";
my $result = PAX::Corpus->new(manifest_path => $manifest)->run;

ok($result->{passed}, 'corpus passes expected compatibility levels');
is($result->{total}, 5, 'corpus case count recorded');

my $capture = PAX::Capture->new(mode => 'live')->capture("$FindBin::Bin/fixtures/simple.pl");
my $pax_manifest = PAX::Manifest->new(capture => $capture)->to_hash;
if ($pax_manifest->{runtime}{baseline_match}) {
    is($result->{levels}{A}, 1, 'Level A aggregate recorded');
    is($result->{levels}{B}, 4, 'Level B aggregate recorded');
} else {
    is($result->{levels}{C}, 5, 'baseline mismatch aggregate recorded');
}

done_testing;

=pod

=head1 NAME

t/corpus.t - cover the corpus behavior exercised by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to cover the corpus behavior exercised by the PAX test suite.

=cut

