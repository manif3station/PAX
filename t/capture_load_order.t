use strict;
use warnings;
use Test::More;
use FindBin;

=pod

=head1 NAME

t/capture_load_order.t - command capture works whatever was loaded first

=head1 WHY IT EXISTS

C<Capture::Tiny::capture { ... }> only parses as a block when Capture::Tiny's C<(&;@)>
prototype is known at compile time. The runtime loads that module with C<require> inside
the subs that use it, so the block was parsed as an anonymous hash whenever nothing else
had loaded the module first: the command ran immediately (its output leaked to the
terminal) and C<capture> died with "Can't use string ("0") as a subroutine ref". Which
commands failed therefore depended on module load order, and C<d2 restart> broke.

=head1 DESCRIPTION

Runs the helper in a fresh interpreter where nothing has loaded Capture::Tiny yet, and also
scans the runtime source (including the handler section) for the block form.

=head1 HOW TO RUN

  prove -l t/capture_load_order.t

=cut

my $lib = "$FindBin::Bin/../lib";
my $out = `$^X -I$lib -e 'require PAX::StandaloneRuntime; die "preloaded" if \$INC{"Capture/Tiny.pm"}; my (\$o, \$e, \$x) = PAX::StandaloneRuntime::_capture_system_command("sh", "-c", "echo out; echo err >&2; exit 3"); print "[\$o][\$e][\$x]"'`;
is($out, "[out\n][err\n][3]", 'a fresh interpreter captures stdout, stderr and the exit code without leaking');

open my $fh, '<', "$lib/PAX/StandaloneRuntime.pm" or die "cannot read runtime: $!";
my $source = do { local $/; <$fh> };
close $fh;
my @blocks = $source =~ /^(.*Capture::Tiny::capture\s*\{.*)$/mg;
is(scalar(@blocks), 0, 'no call site relies on the block prototype of a lazily loaded module');

done_testing();
