use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::Capture;
use PAX::Manifest;

my $fixture = "$FindBin::Bin/fixtures/dynamic.pl";
my $capture = PAX::Capture->new(mode => 'live')->capture($fixture);
is($capture->{status}, 'ok', 'dynamic fixture captures');
ok($capture->{source_features}{string_eval}, 'string eval feature detected');
ok($capture->{source_features}{autoload}, 'AUTOLOAD feature detected');

my $manifest = PAX::Manifest->new(capture => $capture)->to_hash;
ok(@{ $manifest->{compatibility}{barriers} } >= 1, 'compatibility barriers reported');
like(
    join("\n", map { $_->{feature} } @{ $manifest->{compatibility}{barriers} }),
    qr/string_eval/,
    'string eval barrier reported',
);

done_testing;
