use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneAnalysis;
use PAX::StandaloneImage;

=pod

=head1 NAME

t/cov_r2img_build.t - build orchestration and runtime manifest coverage for StandaloneImage

=head1 DESCRIPTION

Runs C<PAX::StandaloneImage::build> with explicit cpanfiles and a stubbed
native analysis that reports one region, and builds a bundled runtime manifest
over an inc directory that contributes no selected files.

=head1 WHY IT EXISTS

The explicit C<cpanfiles> argument and the stripped native artifact list are only
reached with inputs the other build tests never supply, and the empty-inc-root
skip in C<_runtime_manifest> needs a directory with nothing selected.

=cut

$ENV{PAX_CODE_UNIT_CAPTURE} = 'never';
$ENV{PAX_JOBS} = 1;
$ENV{PAX_PROGRESS} = 0;

my $T = tempdir('pax-cov-r2img-build-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($path, $text, $mode)
# Writes a fixture file, creating parent directories first.
# Input: path, text and optional mode. Output: the path.
sub write_file {
    my ($path, $text, $mode) = @_;
    my ($volume, $dir) = File::Spec->splitpath($path);
    make_path($dir) if length $dir && !-d $dir;
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh or die "cannot close $path: $!";
    chmod $mode, $path if defined $mode;
    return $path;
}

write_file("$T/app/lib/Qq/App.pm", "package Qq::App; use strict; sub hi { return 1 }\n1;\n");
write_file("$T/app/bin/main.pl", "#!/usr/bin/perl\nuse strict; use Qq::App; print Qq::App::hi();\n");
write_file("$T/app/cpanfile", "requires 'JSON::PP';\n");
my $exe = write_file("$T/app/native-probe", "#!/bin/sh\nexit 0\n", 0755);

no warnings 'redefine';
my @launcher_calls;
local *PAX::StandaloneImage::_compile_launcher = sub {
    push @launcher_calls, $_[0];
    return { status => 'built' };
};
my @cpanfiles_seen;
my $real_dependencies = \&PAX::StandaloneAnalysis::dependencies;
local *PAX::StandaloneAnalysis::dependencies = sub {
    my ($self, %args) = @_;
    @cpanfiles_seen = @{ $args{cpanfiles} };
    return $real_dependencies->($self, %args);
};
local *PAX::StandaloneAnalysis::native_artifacts = sub {
    return {
        items => [ { region_id => 'r0', region_name => 'n', status => 'ready', executable_path => $exe, tier2_artifact => { path => $exe, note => 'kept' } } ],
        summary => { native_ready => 1, fallback_only => 0 },
        runtime_epochs => [],
    };
};

my $image = PAX::StandaloneImage->new(root => "$T/out");
my $result = $image->build(
    entrypoint => "$T/app/bin/main.pl",
    name => 'cp',
    runtime_mode => 'host_perl',
    lib_dirs => ["$T/app/lib"],
    cpanfiles => ["$T/app/cpanfile"],
    output_path => "$T/cp.bin",
);
is($result->{status}, 'built', 'build with explicit cpanfiles succeeds');
is_deeply(\@cpanfiles_seen, [ File::Spec->rel2abs("$T/app/cpanfile") ], 'the explicit cpanfile reaches the dependency analysis');
my @native = @{ $result->{standalone}{native_artifacts} };
is(scalar(@native), 1, 'one native artifact recorded');
ok(!exists $native[0]{executable_path}, 'runtime path stripped from the recorded native artifact');
is_deeply($native[0]{tier2_artifact}, { note => 'kept' }, 'tier2 path stripped but other fields kept');

# bundled runtime over an inc root that contributes no selected file
{
    my $used = "$T/rt/used";
    my $idle = "$T/rt/idle";
    write_file("$used/Rtq/Dep.pm", "package Rtq::Dep; 1;\n");
    make_path($idle);
    my $perl = write_file("$T/rt/perl-fake", "#!/bin/sh\nexit 0\n", 0755);
    my $m;
    open my $saved_err, '>&', \*STDERR or die "dup: $!";
    open STDERR, '>', File::Spec->devnull or die "null: $!";
    {
        local $^X = $perl;
        local @INC = ($used, $idle);
        $m = PAX::StandaloneImage::_runtime_manifest(
            dependencies => [ { class => 'bundled_pure_perl', module => 'Rtq::Dep', source_path => "$used/Rtq/Dep.pm" } ],
        );
    }
    open STDERR, '>&', $saved_err or die "restore: $!";
    my @logical = map { $_->{logical_path} } @{ $m->{payloads} };
    ok((grep { m{/Rtq/Dep\.pm\z} } @logical), 'selected module shipped');
    ok(!(grep { m{idle} } map { $_->{source_path} } @{ $m->{payloads} }), 'idle inc root contributes nothing');
}

done_testing;
