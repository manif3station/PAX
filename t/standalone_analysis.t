use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneAnalysis;

my $analysis = PAX::StandaloneAnalysis->new;
require JSON::PP;
my $json_pp_path = $INC{'JSON/PP.pm'};
my $tmpdir = tempdir(CLEANUP => 1);
my $dep_entry = "$tmpdir/deps.pl";
open my $dep_fh, '>', $dep_entry or die "cannot write $dep_entry: $!";
print {$dep_fh} <<'PERL';
use strict;
use warnings;
use JSON::PP;
use JSON::XS;
1;
PERL
close $dep_fh;

my $deps = $analysis->dependencies(
    entrypoint => $dep_entry,
    code_units => [
        {
            source_path => $dep_entry,
            unit_kind => 'entrypoint',
        },
        {
            source_path => "$FindBin::Bin/fixtures/app_lib/SlowLoad.pm",
            unit_kind => 'lib',
        },
        {
            source_path => $json_pp_path,
            unit_kind => 'dependency',
        },
    ],
    cpanfiles => ["$FindBin::Bin/fixtures/standalone_policy.cpanfile"],
);

my %deps_by_module = map { $_->{module} => $_ } @{ $deps->{items} };
is($deps_by_module{SlowLoad}{class}, 'packaged_app', 'packaged app module classified correctly');
is($deps_by_module{'JSON::PP'}{class}, 'compiled_dependency', 'compiled dependency classified correctly');
is($deps_by_module{'JSON::XS'}{class}, 'bundled_xs', 'XS dependency classified as bundled_xs');
ok(($deps->{summary}{bundled_xs} // 0) >= 1, 'dependency summary counts bundled XS modules');
ok(($deps->{summary}{compiled_dependency} // 0) >= 1, 'dependency summary counts compiled dependencies');

my $native = $analysis->native_artifacts(
    entrypoint => "$FindBin::Bin/fixtures/native_leafs.pl",
);

ok(($native->{summary}{native_ready} // 0) >= 1, 'native analysis finds native-ready regions');
ok((grep { ($_->{entry_kind} // '') eq 'native_i64_leaf' } @{ $native->{items} }) >= 1, 'leaf entry kind recorded');
ok(exists $native->{runtime_epochs}{package_symbols}, 'native analysis records runtime epoch metadata for guard validation');

done_testing;
