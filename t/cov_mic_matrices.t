use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/../lib";

use PAX;
use PAX::BenchmarkMatrix;
use PAX::CPANMatrix;
use PAX::CoreSuite;

=pod

=head1 NAME

t/cov_mic_matrices.t - coverage for the benchmark, CPAN and core-suite matrix runners

=head1 DESCRIPTION

Drives PAX::BenchmarkMatrix, PAX::CPANMatrix and PAX::CoreSuite against
temporary manifests with stubbed capture/benchmark back ends, covering both
sides of every defaulting operator and pass/fail ternary, and loads the PAX
umbrella module.

=head1 WHY IT EXISTS

These runners were never loaded under Devel::Cover, and the project requires
full coverage of lib/.

=cut

my $tmp = tempdir('pax-cov-mic-mx-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_json($name, $data)
# Writes a JSON manifest into the temp dir. Input: file name and data.
# Output: the written path.
sub write_json {
    my ($name, $data) = @_;
    my $path = File::Spec->catfile($tmp, $name);
    open my $fh, '>', $path or die "$path: $!";
    print {$fh} JSON::PP->new->encode($data);
    close $fh;
    return $path;
}

like($PAX::VERSION, qr/^\d+\.\d+/, 'PAX umbrella module loads');

# ------------------------------------------------------------ BenchmarkMatrix
{
    no warnings 'redefine';
    my @seen;
    local *PAX::Capture::capture = sub { return { status => 'ok', runtime => { config_version => '5.42.0' } } };
    local *PAX::Benchmark::run_runtime_benchmark = sub { my ($self, $f) = @_; push @seen, $self->{iterations}; return { fixture => $f } };

    my $dflt = PAX::BenchmarkMatrix->new(manifest_path => 'x');
    is($dflt->{iterations}, 1, 'iterations default to one');

    my $path = write_json('bm.json', { classes => [
        { id => 'c1', description => 'd', metrics => ['m'], fixtures => ['a.pl', 'b.pl'] },
        { id => 'c2' },
    ] });
    my $r = PAX::BenchmarkMatrix->new(manifest_path => $path, iterations => 3, pax_bin => 'pax')->run;
    is($r->{iterations}, 3, 'iterations honoured');
    is(scalar @{ $r->{classes} }, 2, 'two classes');
    is_deeply($r->{classes}[0]{metrics}, ['m'], 'metrics kept');
    is_deeply($r->{classes}[1]{metrics}, [], 'metrics default');
    is_deeply($r->{classes}[1]{fixtures}, [], 'fixtures default');
    is($r->{classes}[0]{fixtures}[1]{path}, 'b.pl', 'fixture result');
    is($r->{classes}[0]{fixtures}[0]{capture_status}, 'ok', 'capture status');
    is_deeply(\@seen, [3, 3], 'benchmark gets iterations');
    ok($r->{passed}, 'passed');

    is(scalar @{ PAX::BenchmarkMatrix->new(manifest_path => write_json('bm0.json', {}))->run->{classes} }, 0, 'no classes key');
    eval { PAX::BenchmarkMatrix->new(manifest_path => File::Spec->catfile($tmp, 'missing'))->run };
    like($@, qr/cannot read benchmark matrix/, 'missing manifest dies');
}

# ------------------------------------------------------------------ CPANMatrix
{
    no warnings 'redefine';
    my %captures = ('ok.pl' => { status => 'ok', runtime => { config_version => '5.42.0' } }, 'bad.pl' => { runtime => {} });
    local *PAX::Capture::capture = sub { my ($self, $path) = @_; return $captures{$path} };

    my $dflt = PAX::CPANMatrix->new(manifest_path => 'x');
    is($dflt->{perl}, $^X, 'perl defaults to $^X');
    is(PAX::CPANMatrix->new(perl => 'myperl')->{perl}, 'myperl', 'perl override');

    my $path = write_json('cpan.json', { distributions => [
        { distribution => 'Good', source => 'local', compatibility_class => 'x', declared_xs => ['XS'],
          modules => ['strict'], fixtures => ['ok.pl'], expected_levels => ['A'] },
        { distribution => 'Bare' },
        { distribution => 'Bad', modules => ['No::Such::Module::Pax'], fixtures => ['bad.pl'], expected_levels => ['B'] },
        { distribution => 'NoFixtures', expected_levels => ['A'] },
        { distribution => 'WrongLevel', fixtures => ['ok.pl'], expected_levels => ['Z'] },
    ] });
    my $r = PAX::CPANMatrix->new(manifest_path => $path)->run;
    is($r->{total}, 5, 'five distributions');
    is($r->{failed}, 2, 'failures counted');
    ok(!$r->{passed}, 'suite fails');
    my %by = map { $_->{distribution} => $_ } @{ $r->{results} };
    ok($by{Good}{passed}, 'good distribution passes');
    is($by{Good}{source}, 'local', 'source kept');
    like($by{Good}{modules}[0]{version}, qr/\S/, 'module version reported');
    is($by{Bare}{source}, 'installed', 'source defaults');
    is_deeply($by{Bare}{declared_xs}, [], 'declared_xs defaults');
    is_deeply($by{Bare}{expected_levels}, [], 'expected_levels defaults');
    ok($by{Bare}{passed}, 'empty distribution passes');
    ok(!$by{Bad}{passed}, 'bad distribution fails');
    is($by{Bad}{modules}[0]{version}, undef, 'failing module has no version');
    ok(!$by{Bad}{modules}[0]{passed}, 'failing module');
    ok(!$by{Bad}{fixtures}[0]{passed}, 'capture without status fails');
    ok($by{NoFixtures}{passed}, 'level passes with no fixtures');
    ok(!$by{WrongLevel}{passed}, 'wrong level fails');
    is($by{Good}{fixtures}[0]{compatibility_level}, 'A', 'level reported');

    is(PAX::CPANMatrix->new(manifest_path => write_json('cpan0.json', {}))->run->{total}, 0, 'no distributions key');
    eval { PAX::CPANMatrix->new(manifest_path => File::Spec->catfile($tmp, 'missing'))->run };
    like($@, qr/cannot read CPAN matrix manifest/, 'missing manifest dies');

    is(PAX::CPANMatrix::_trim(undef), '', 'trim undef');
    is(PAX::CPANMatrix::_trim("  x \n"), 'x', 'trim whitespace');
    is(PAX::CPANMatrix::_level_present('A', [{}]), 0, 'fixture without level does not match');

    # A stream already at EOF reads as undef and is normalised.
    local *PAX::CPANMatrix::open3 = sub {
        open $_[0], '<', '/dev/null' or die $!;
        my ($o, $e) = ("x\n", "y\n");
        open $_[1], '<', \$o or die $!;
        open $_[2], '<', \$e or die $!;
        readline($_[1]);
        readline($_[2]);
        return 999999;
    };
    my ($out, $err) = PAX::CPANMatrix::_run('nothing');
    is($out, '', 'undef stdout normalised');
    is($err, '', 'undef stderr normalised');
}

# ------------------------------------------------------------------- CoreSuite
{
    my $dflt = PAX::CoreSuite->new(manifest_path => 'x');
    is($dflt->{perl}, $^X, 'perl defaults to $^X');
    my $path = write_json('core.json', { cases => [
        { id => 'good', description => 'd', argv => ['-e', 'print 1'] },
        { id => 'bad', argv => ['-e', 'exit 4'] },
        { id => 'noargs' },
    ] });
    my $suite = PAX::CoreSuite->new(manifest_path => $path, perl => $^X);
    my $r = $suite->run;
    is($r->{total}, 3, 'three cases');
    ok($r->{results}[0]{passed}, 'good passes');
    is($r->{results}[0]{stdout}, '1', 'stdout captured');
    is($r->{results}[1]{exit}, 4, 'exit code captured');
    ok(!$r->{results}[1]{passed}, 'bad fails');
    is_deeply($r->{results}[2]{command}, [$^X], 'argv defaults to empty');
    ok(!$r->{passed}, 'suite fails when a case fails');
    ok($r->{failed} >= 1, 'failures counted');

    my $ok = PAX::CoreSuite->new(manifest_path => write_json('core1.json', { cases => [{ id => 'x', argv => ['-e', '1'] }] }))->run;
    ok($ok->{passed}, 'suite passes');
    is(PAX::CoreSuite->new(manifest_path => write_json('core0.json', {}))->run->{total}, 0, 'no cases key');
    eval { PAX::CoreSuite->new(manifest_path => File::Spec->catfile($tmp, 'missing'))->run };
    like($@, qr/cannot read core suite manifest/, 'missing manifest dies');

    no warnings 'redefine';
    local *PAX::CoreSuite::open3 = sub {
        open $_[0], '<', '/dev/null' or die $!;
        my ($o, $e) = ("x\n", "y\n");
        open $_[1], '<', \$o or die $!;
        open $_[2], '<', \$e or die $!;
        readline($_[1]);
        readline($_[2]);
        return 999999;
    };
    my ($out, $err) = PAX::CoreSuite::_run('nothing');
    is($out, '', 'undef stdout normalised');
    is($err, '', 'undef stderr normalised');
}

done_testing;
