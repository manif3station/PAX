use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use FindBin;

=pod

=head1 NAME

t/dashboard_unit_parity.t - sub-level differential test of the dashboard binary against stock Perl

=head1 WHY IT EXISTS

The command-line and web parity tests only reach the handler-compiled subs that a command or route
happens to call. This test runs every script in C<t/fixtures/diff/> as a page C<CODE1> block under
the interpreter and under the PAX-built binary and requires byte-identical output, so a handler that
drifted from the source it replaced is caught even if no command exercises it.

=head1 DESCRIPTION

Each fixture is a plain Perl program that prints deterministic text. It is saved as a page in a fresh
HOME and rendered with C<dashboard page render>; paths, timestamps, epoch values and die locations are
normalized exactly as in C<t/dashboard_parity.t>. Skips without the application checkout or its
dependencies. Add a fixture by dropping a C<.pl> file into C<t/fixtures/diff/>.

=head1 HOW TO RUN

  prove -l t/dashboard_unit_parity.t
  PAX_DIFF_ONLY=runtime_result prove -lv t/dashboard_unit_parity.t   # one fixture

=cut

my $app = $ENV{PAX_PARITY_APP} // abs_path("$FindBin::Bin/../../developer-dashboard") // '';
plan skip_all => 'no Developer Dashboard checkout found (set PAX_PARITY_APP)' if !$app || !-f "$app/bin/dashboard";
my $pax = abs_path("$FindBin::Bin/../bin/pax");
my $tmp = tempdir('pax-unit-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# render($label, $home, @launcher) renders the saved page 'unit' and returns (status, normalized text).
sub render {
    my ($label, $home, @launcher) = @_;
    my $out = "$tmp/$label.out";
    local $ENV{HOME} = $home;
    local $ENV{TMPDIR} = $tmp;
    local $ENV{PAX_PROGRESS} = 0;
    my $cmd = join ' ', map { "'$_'" } @launcher, 'page', 'render', 'unit';
    my $status = system("cd '$home' && $cmd >'$out' 2>&1 </dev/null");
    open my $fh, '<:raw', $out or die "cannot read $out: $!";
    my $text = do { local $/; <$fh> } // '';
    close $fh;
    $text =~ s/\Q$home\E/HOME/g;
    $text =~ s{\S*?/pax-standalone-cache-[0-9a-f]+/(?:code/lib/lib|runtime/inc/\d+)}{LIB}g;
    $text =~ s{\Q$app\E/bin/\.\./lib}{LIB}g;
    $text =~ s{\Q$app\E/lib}{LIB}g;
    $text =~ s/\d{4}-\d{2}-\d{2}[T ][\d:.]+Z?/TS/g;
    $text =~ s{ at (?:\S+\.pm|PAX::StandaloneRuntime op \w+) line \d+\.}{ at LOC.}g;
    $text =~ s/\b1\d{9}\.\d+\b/EPOCH/g;
    $text =~ s/\b1\d{9}\b/EPOCH/g;
    $text =~ s/HASH\(0x[0-9a-f]+\)/HASH/g;
    $text =~ s/(?:ARRAY|CODE|SCALAR|GLOB)\(0x[0-9a-f]+\)/REF/g;
    return ($status >> 8, $text);
}

# prepare($home, $script) writes the fixture as a page into a fresh HOME.
sub prepare {
    my ($home, $script) = @_;
    remove_tree($home);
    make_path("$home/.developer-dashboard/dashboards");
    open my $in, '<', $script or die "cannot read $script: $!";
    my $code = do { local $/; <$in> };
    close $in;
    $code =~ s/^\s*#.*\n//mg;
    open my $o, '>', "$home/.developer-dashboard/dashboards/unit" or die $!;
    print {$o} "TITLE: Unit\n:--------------------------------------------------------------------------------:\nBOOKMARK: unit\n:--------------------------------------------------------------------------------:\nCODE1: $code";
    close $o;
    return;
}

my $binary = "$tmp/unit-app";
my $rc = system('sh', '-c', 'cd "$1" && PAX_PROGRESS=0 "$2" -I"$3/lib" "$4" build --compact -o "$5" "$6/bin/dashboard" >/dev/null 2>&1', 'sh', $tmp, $^X, abs_path("$FindBin::Bin/.."), $pax, $binary, $app);
plan skip_all => 'could not build the dashboard binary' if $rc != 0 || !-x $binary;

my @fixtures = sort glob("$FindBin::Bin/fixtures/diff/*.pl");
@fixtures = grep { m{/\Q$ENV{PAX_DIFF_ONLY}\E\.pl\z} } @fixtures if $ENV{PAX_DIFF_ONLY};
my $home = "$tmp/home";
for my $fixture (@fixtures) {
    my ($name) = $fixture =~ m{([^/]+)\.pl\z};
    prepare($home, $fixture);
    my ($srv, $stock) = render("stock-$name", $home, $^X, "-I$app/lib", "$app/bin/dashboard");
    prepare($home, $fixture);
    my ($brc, $bin) = render("bin-$name", $home, $binary);
    $stock =~ s/\Q$app\E\/bin\/dashboard/dashboard/g;
    is($brc, $srv, "$name: exits with the same status as stock Perl");
    is($bin, $stock, "$name: prints the same output as stock Perl");
}
ok(1, 'no fixtures to run') if !@fixtures;

done_testing();
