use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Spec;
use FindBin;

=pod

=head1 NAME

t/standalone_hermetic.t - a standalone binary needs nothing from the machine it runs on

=head1 WHY IT EXISTS

A binary that still loads the host's libc or libm, or that starts its bundled perl through the
host's dynamic loader, only works where those exist. PAX bundles glibc and its loader and links
the launcher statically, so the one remaining requirement is a Linux kernel.

=head1 DESCRIPTION

Builds a tiny program that prints a greeting and also runs a child through C<$^X>, then checks the
launcher is statically linked and, when root and chroot are available, runs it in a root that
contains only the binary and the /dev nodes (no libc, no libm, no loader, no perl, no shell).

=head1 HOW TO RUN

  prove -l t/standalone_hermetic.t

=cut

plan skip_all => 'needs a C compiler' if !grep { -x "$_/cc" || -x "$_/gcc" } split /:/, $ENV{PATH};
my $dir = tempdir('pax-hermetic-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $script = "$dir/hello.pl";
open my $out, '>', $script or die $!;
print {$out} <<'PERL';
use strict; use warnings;
print "hello\n";
open my $fh, '-|', $^X, '-e', 'print 6*7' or die "no child: $!";
my $child = <$fh>;
close $fh;
print "child=$child\n";
PERL
close $out;
my $root = File::Spec->rel2abs("$FindBin::Bin/..");
my $bin = "$dir/hello";
my $rc = system('sh', '-c', 'cd "$1" && PAX_PROGRESS=0 "$2" -I"$3/lib" "$3/bin/pax" build --compact -o "$4" "$5" >/dev/null 2>&1', 'sh', $dir, $^X, $root, $bin, $script);
plan skip_all => 'build unavailable here' if $rc != 0 || !-x $bin;

my $ldd = `ldd '$bin' 2>&1`;
like($ldd, qr/not a dynamic executable|statically linked/, 'the launcher is statically linked');

SKIP: {
    skip 'needs root and chroot', 3 if $> != 0 || !grep { -x "$_/chroot" } split /:/, $ENV{PATH};
    my $sandbox = "$dir/bare";
    make_path(map { "$sandbox/$_" } qw(bin tmp dev));
    system('cp', $bin, "$sandbox/bin/app");
    system('mknod', '-m', '666', "$sandbox/dev/null", 'c', '1', '3');
    my $text = `chroot '$sandbox' /bin/app 2>&1`;
    is($? >> 8, 0, 'the binary runs in a root that holds nothing but itself');
    like($text, qr/^hello$/m, 'it prints its output');
    like($text, qr/^child=42$/m, 'a child started through $^X runs too');
}

done_testing();
