use strict;
use warnings;
use Test::More;
use File::Path qw(remove_tree);
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/../lib";

use PAX::AppImage;
use PAX::AppServer;
use PAX::Paxfile;

my $root = "$FindBin::Bin/tmp-apps";
remove_tree($root) if -d $root;
local $ENV{PAX_APP_ROOT} = $root;

my $builder = PAX::AppImage->new(root => $root);
my $built = $builder->build(
    name => 'fixture-dashboard',
    entrypoint => "$FindBin::Bin/fixtures/app_entry.pl",
    lib_dirs => ["$FindBin::Bin/fixtures/app_lib"],
    assets => ["$FindBin::Bin/fixtures/app_assets/banner.txt"],
);

is($built->{status}, 'built', 'app image built');
ok(-f $built->{config_path}, 'image config written');
ok(-x $built->{image}{launcher_path}, 'native launcher built');
ok(grep { $_ eq 'SlowLoad' } @{ $built->{image}{preload_modules} }, 'preload module discovered');
is($built->{image}{asset_count}, 1, 'asset is embedded into image metadata');
is($built->{image}{assets}[0]{logical_path}, 'banner.txt', 'asset logical path is recorded');

my $image = $builder->load(name => 'fixture-dashboard');
my $pid = fork();
die "fork failed: $!" if !defined $pid;
if ($pid == 0) {
    PAX::AppServer->new(image => $image)->start;
    exit 0;
}

for (1..50) {
    last if -S $image->{socket_path};
    select undef, undef, undef, 0.05;
}
ok(-S $image->{socket_path}, 'app server socket is ready');

my $output = `$^X $FindBin::Bin/../bin/pax app-run --name fixture-dashboard -- status`;
is($? >> 8, 0, 'app-run exits successfully');
is($output, "slowload-ready\n", 'app-run dispatches through preloaded app server');

my $launcher_output = `$image->{launcher_path} status`;
is($? >> 8, 0, 'native launcher exits successfully');
is($launcher_output, "slowload-ready\n", 'native launcher dispatches through app server');
ok(-f "$image->{asset_root}/banner.txt", 'native launcher extracts embedded asset');
my $asset_text = do {
    open my $fh, '<', "$image->{asset_root}/banner.txt" or die $!;
    local $/;
    <$fh>;
};
is($asset_text, "embedded-dashboard-asset\n", 'extracted asset content matches source');

PAX::AppServer->stop(image => $image);
waitpid($pid, 0);

my $paxfile = PAX::Paxfile->load("$FindBin::Bin/fixtures/paxfile.yml");
is($paxfile->{name}, 'fixture-dashboard', 'paxfile scalar name parsed');
is_deeply($paxfile->{libs}, ['t/fixtures/app_lib'], 'paxfile repeatable libs parsed');

remove_tree($root) if -d $root;
my $paxfile_output = `cd $FindBin::Bin/.. && PAX_APP_ROOT=$root $^X bin/pax app-build --compact --paxfile t/fixtures/paxfile.yml`;
is($? >> 8, 0, 'app-build reads defaults from paxfile.yml');
my $paxfile_build = JSON::PP->new->decode($paxfile_output);
is($paxfile_build->{image}{asset_count}, 1, 'paxfile asset embedded');
ok(-x $paxfile_build->{image}{launcher_path}, 'paxfile build creates launcher');

my $override_output = `cd $FindBin::Bin/.. && PAX_APP_ROOT=$root $^X bin/pax app-build --compact --paxfile t/fixtures/paxfile.yml --name override-dashboard --asset t/fixtures/app_assets/banner.txt t/fixtures/app_entry.pl`;
is($? >> 8, 0, 'CLI args override paxfile defaults');
my $override_build = JSON::PP->new->decode($override_output);
is($override_build->{image}{name}, 'override-dashboard', 'CLI name overrides paxfile name');
is($override_build->{image}{entrypoint}, "$FindBin::Bin/fixtures/app_entry.pl", 'CLI entrypoint overrides paxfile entrypoint');

remove_tree($root) if -d $root;
done_testing;
