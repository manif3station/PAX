use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneRuntime;

=pod

=head1 NAME

t/blank_container.t - a lone standalone binary must run where the host Perl library is absent

=head1 WHY IT EXISTS

A standalone binary is meant to be copied to a machine that has none of the
build host's CPAN modules or core Perl library. Every other test runs on a
machine that does have them, so a module the packager forgot to bundle (for
example JSON::PP) goes unnoticed. This test builds a small application and runs
it inside a private mount namespace that hides the host's Perl module
directories, which is what a minimal container looks like.

=head1 DESCRIPTION

The namespace part needs root and C<unshare -m>; it skips itself otherwise.
The unit part checks the framework location defaults the runtime sets so that
frameworks do not depend on the build-time source path.

=cut

# Framework locations default to the embedded asset root unless the operator chose one.
{
    local $ENV{DANCER_CONFDIR};
    local $ENV{PAX_EMBEDDED_ASSET_ROOT};
    delete $ENV{DANCER_CONFDIR};
    delete $ENV{PAX_EMBEDDED_ASSET_ROOT};
    PAX::StandaloneRuntime::_default_framework_locations();
    ok(!defined $ENV{DANCER_CONFDIR}, 'no asset root leaves the config location alone');
    $ENV{PAX_EMBEDDED_ASSET_ROOT} = '/embedded/assets';
    PAX::StandaloneRuntime::_default_framework_locations();
    is($ENV{DANCER_CONFDIR}, '/embedded/assets', 'config location defaults to the embedded asset root');
    $ENV{DANCER_CONFDIR} = '/operator/choice';
    PAX::StandaloneRuntime::_default_framework_locations();
    is($ENV{DANCER_CONFDIR}, '/operator/choice', 'an operator-set config location is kept');
}

my $unshare = -x '/usr/bin/unshare' ? '/usr/bin/unshare' : '';
plan skip_all => 'needs root and unshare for a private mount namespace' if !$unshare || $> != 0;
my $probe = system("$unshare -m --propagation private true >/dev/null 2>&1");
plan skip_all => 'unshare -m is not permitted here' if $probe != 0;

my $root = tempdir('pax-blank-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $binary = File::Spec->catfile($root, 'blank-app');
my $repo = abs_path("$FindBin::Bin/..");
my $build_rc = system("cd '$repo' && PAX_PROGRESS=0 '$^X' bin/pax build --compact --no-paxfile --name blank-app --lib t/fixtures/app_lib -o '$binary' t/fixtures/app_entry.pl >'$root/build.json' 2>'$root/build.err'");
is($build_rc >> 8, 0, 'fixture application builds');
ok(-x $binary, 'standalone binary exists');

# The binary has never run on this machine, so its payload cache does not exist yet.
my $script = File::Spec->catfile($root, 'inside.sh');
open my $fh, '>', $script or die "cannot write $script: $!";
print {$fh} <<"SH";
#!/bin/sh
for d in /usr/share/perl5 /usr/lib/x86_64-linux-gnu/perl5 /usr/lib/x86_64-linux-gnu/perl /usr/share/perl /usr/local/share/perl /usr/local/lib /etc/perl; do
  [ -d "\$d" ] && mount -t tmpfs tmpfs "\$d"
done
cd '$root'
env -i PATH=/usr/bin:/bin HOME='$root' TMPDIR='$root' '$binary' 2>&1
SH
close $fh or die "cannot close $script: $!";
chmod 0755, $script;
my $output = `$unshare -m --propagation private '$script'`;
is($? >> 8, 0, 'binary exits cleanly with the host Perl library hidden');
like($output, qr/slowload-ready/, 'binary prints its normal output with the host Perl library hidden');
unlike($output, qr/Can't locate/, 'no module is missing from the bundle');

done_testing();
