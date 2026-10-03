use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use FindBin;
use lib "$FindBin::Bin/../lib";

=pod

=head1 NAME

t/standalone_cache_race.t - simultaneous first runs of one standalone binary

=head1 WHY IT EXISTS

The launcher used to extract its payload in place into a shared cache directory, so two
simultaneous first runs could overwrite files the other was already executing. That showed up
as segfaults and "failed to extract" errors and as intermittent failures when test files ran in
parallel.

=head1 DESCRIPTION

Checks that the launcher source publishes the cache with an atomic rename from a private staging
directory, then builds a tiny binary, starts eight copies at once against an empty cache and
asserts that every one exits cleanly with the right output and that no staging directory is left
behind. The build part skips without a C compiler.

=head1 HOW TO RUN

  prove -l t/standalone_cache_race.t

=cut


# Concurrent first runs of one standalone binary must not corrupt each other's payload cache:
# the extraction is staged privately and renamed into place.
my $src = File::Spec->catfile($FindBin::Bin, '..', 'lib', 'PAX', 'StandaloneImage.pm');
open my $fh, '<', $src or die "cannot read $src: $!";
my $text = do { local $/; <$fh> };
close $fh;

like($text, qr/rename\(staging, tmpdir\)/, 'launcher publishes the extracted cache with an atomic rename');
like($text, qr/remove_tree\(staging\)/, 'launcher removes its staging directory when it loses the race');
unlike($text, qr/mkdir\(tmpdir, 0700\) != 0 && errno != EEXIST\) return 111;\n\s+if \(resolve_roots\(tmpdir/, 'launcher no longer extracts in place into the shared cache directory');

SKIP: {
    skip 'no C compiler', 3 if !grep { -x "$_/cc" || -x "$_/gcc" } split /:/, $ENV{PATH};
    my $dir = tempdir('pax-race-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    my $script = "$dir/hello.pl";
    open my $out, '>', $script or die $!;
    print {$out} "print qq{hello\\n};\n";
    close $out;
    my $bin = "$dir/hello";
    local $ENV{PAX_PROGRESS} = 0;
    my $root = File::Spec->rel2abs("$FindBin::Bin/..");
    my $rc = system('sh', '-c', 'cd "$1" && "$2" -I"$3/lib" "$3/bin/pax" build --compact -o "$4" "$5" >/dev/null 2>&1', 'sh', $dir, $^X, $root, $bin, $script);
    skip 'build unavailable here', 3 if $rc != 0 || !-x $bin;
    my $cache = "$dir/cache";
    mkdir $cache;
    my @pids;
    for my $i (1 .. 8) {
        my $pid = fork();
        if (!$pid) {
            local $ENV{TMPDIR} = $cache;
            open STDOUT, '>', "$dir/out$i" or exit 99;
            open STDERR, '>&', \*STDOUT;
            exec $bin or exit 98;
        }
        push @pids, $pid;
    }
    my $bad = 0;
    for my $pid (@pids) { waitpid($pid, 0); $bad++ if $? != 0 }
    my $wrong = grep { my $f = "$dir/out$_"; my $t = do { local (@ARGV, $/) = $f; <> } // ''; $t ne "hello\n" } 1 .. 8;
    is($bad, 0, 'eight simultaneous cold starts all exit cleanly');
    is($wrong, 0, 'eight simultaneous cold starts all print the program output');
    my @stage = glob("$cache/*.stage-*");
    is(scalar(@stage), 0, 'no staging directories are left behind');
}

done_testing();
