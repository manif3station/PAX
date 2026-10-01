use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneImage;

=pod

=head1 NAME

t/cov_sima_build.t - coverage for PAX::StandaloneImage build orchestration

=head1 DESCRIPTION

Drives C<PAX::StandaloneImage::build> end to end on tiny fabricated trees with
the launcher compile stubbed out, plus the small public accessors (C<new>,
C<load>, C<path_for>, C<build_progress_tasks>) and the pure metadata helpers it
uses.

=head1 WHY IT EXISTS

C<build> has many defaulting branches (explicit arguments versus values inferred
from a previous standalone binary), progress reporting, and a failed-launcher
path. Real image builds are slow, so this exercises them with host_perl mode and
a stubbed launcher compile.

=cut

$ENV{PAX_CODE_UNIT_CAPTURE} = 'never';
$ENV{PAX_JOBS} = 1;
$ENV{PAX_PROGRESS} = 0;

my $root = tempdir('pax-cov-sima-build-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($path, $text)
# Writes a fixture file, creating parent directories first.
# Input: destination path and file text. Output: the path written.
sub write_file {
    my ($path, $text) = @_;
    my ($volume, $dir) = File::Spec->splitpath($path);
    make_path($dir) if length $dir && !-d $dir;
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh or die "cannot close $path: $!";
    return $path;
}

write_file("$root/app/lib/Foo/App.pm", "package Foo::App; use strict; sub hi { return 1 }\n1;\n");
write_file("$root/app/lib/Foo/Other.pm", "package Foo::Other; use strict; sub hi { return 2 }\n1;\n");
write_file("$root/app/bin/main.pl", "#!/usr/bin/perl\nuse strict; use Foo::App; use Foo::Other; print Foo::App::hi();\n");
write_file("$root/app/assets/data.txt", "asset\n");
write_file("$root/app/extra.txt", "extra\n");

my @launcher_calls;
my $launcher_result = { status => 'built' };
no warnings 'redefine';
local *PAX::StandaloneImage::_compile_launcher = sub {
    push @launcher_calls, $_[0];
    return $launcher_result;
};
use warnings 'redefine';

# static accessors
{
    my $tasks = PAX::StandaloneImage::build_progress_tasks();
    is(scalar(@$tasks), 12, 'twelve progress tasks');
    is($tasks->[0]{id}, 'resolve_inputs', 'first task id');

    local $ENV{PAX_STANDALONE_ROOT} = '/tmp/env-root';
    is(PAX::StandaloneImage->new->{root}, '/tmp/env-root', 'root from env');
    is(PAX::StandaloneImage->new(root => '/x')->{root}, '/x', 'root from args');
    local $ENV{PAX_STANDALONE_ROOT};
    delete $ENV{PAX_STANDALONE_ROOT};
    is(PAX::StandaloneImage->new->{root}, '.pax/standalone', 'default root');
    is(PAX::StandaloneImage->new(root => '/r')->path_for('n'), '/r/n/manifest.json', 'path_for');
}

# progress emit
{
    my @events;
    is(PAX::StandaloneImage::_progress_emit(undef, {}), 1, 'no progress is fine');
    is(PAX::StandaloneImage::_progress_emit('nope', {}), 1, 'non-code progress ignored');
    PAX::StandaloneImage::_progress_emit(sub { push @events, $_[0] }, { a => 1 });
    is_deeply(\@events, [ { a => 1 } ], 'progress callback receives event');
}

my $image = PAX::StandaloneImage->new(root => "$root/out");
eval { $image->build() };
like($@, qr/entrypoint required/, 'build requires an entrypoint');
eval { $image->build(entrypoint => "$root/nodir/deeper/nope.pl") };
like($@, qr/entrypoint not found/, 'build rejects a missing entrypoint');

# full build with progress, explicit arguments and assets
{
    my @events;
    my $result = $image->build(
        entrypoint => "$root/app/bin/main.pl",
        name => 'demo',
        runtime_mode => 'host_perl',
        lib_dirs => ["$root/app/lib"],
        assets => ["$root/app/extra.txt"],
        asset_dirs => ["$root/app/assets"],
        app_name => 'Demo App',
        app_namespace => 'Foo::App',
        app_legacy_namespace => 'Foo::Legacy',
        app_entrypoint_env => 'DEMO_ENTRY',
        app_entrypoint_fallback => 'fallback',
        app_command => 'demo-cmd',
        paxfile_applied => 1,
        override_fields => ['name'],
        output_path => "$root/demo.bin",
        progress => sub { push @events, $_[0] },
    );
    is($result->{status}, 'built', 'build reports built');
    is($result->{standalone}{model}, 'single_executable_host_perl_payload', 'host_perl model');
    is($result->{standalone}{output_path}, "$root/demo.bin", 'explicit output path');
    is($result->{standalone}{app}{name}, 'Demo App', 'explicit app name');
    is($result->{standalone}{app}{compat}{namespace}, 'Foo::App', 'explicit namespace');
    is($result->{standalone}{app}{compat}{legacy_namespace}, 'Foo::Legacy', 'explicit legacy namespace');
    is($result->{standalone}{app}{entrypoint_env}, 'DEMO_ENTRY', 'explicit entrypoint env');
    is($result->{standalone}{app}{command}, 'demo-cmd', 'explicit command');
    ok($result->{standalone}{build_plan}{paxfile_applied}, 'paxfile flag recorded');
    is_deeply($result->{standalone}{build_plan}{override_fields}, ['name'], 'override fields recorded');
    is($result->{standalone}{asset_count}, 2, 'asset file plus asset dir file');
    ok(-f $result->{manifest_path}, 'manifest written');
    ok((grep { $_->{status} eq 'failed' } @events) == 0, 'no failed progress events');
    my ($done) = grep { $_->{task_id} eq 'infer_app_metadata' && $_->{status} eq 'done' } @events;
    like($done->{label}, qr/Foo::App namespace/, 'metadata label names namespace');
    my @logical = map { $_->{logical_path} } @{ $result->{standalone}{code_units} };
    ok((grep { m{Foo/App} } @logical), 'application unit compiled');
    my $disk = $image->load(name => 'demo');
    is($disk->{name}, 'demo', 'load returns the manifest written to disk');
    is($disk->{launcher_status}, 'built', 'launcher status stored');
    ok(!exists $disk->{launcher_reason}, 'no reason for a built launcher');
    eval { $image->load() };
    like($@, qr/name required/, 'load requires a name');
    eval { $image->load(name => 'missing-image') };
    like($@, qr/cannot read standalone image/, 'load reports unreadable manifest');
}

# defaults: inferred namespace, bundled model with stubbed runtime, failed launcher
{
    $launcher_result = { status => 'failed', reason => 'no compiler' };
    my @events;
    local *PAX::StandaloneImage::_runtime_manifest = sub {
        return {
            payloads => [],
            perl_binary => 'perl',
            perl_binary_logical_path => 'runtime/perl',
            bundled_inc_roots => [],
            runtime_hash => 'h',
        };
    };
    my $result = $image->build(
        entrypoint => "$root/app/bin/main.pl",
        lib_dirs => ["$root/app/lib"],
        progress => sub { push @events, $_[0] },
    );
    is($result->{status}, 'not_built', 'failed launcher gives not_built');
    is($result->{standalone}{model}, 'single_executable_bundled_perl_payload', 'bundled default model');
    is($result->{standalone}{name}, 'main', 'name derived from entrypoint');
    like($result->{standalone}{app}{compat}{namespace}, qr/\AFoo::(?:App|Other)\z/, 'namespace inferred from units');
    is($result->{standalone}{launcher_reason}, 'no compiler', 'failure reason kept');
    ok(!$result->{standalone}{build_plan}{paxfile_applied}, 'paxfile flag defaults off');
    my ($failed) = grep { $_->{task_id} eq 'compile_launcher' && $_->{status} eq 'failed' } @events;
    like($failed->{label}, qr/\(no compiler\)/, 'failed label carries reason');

    $launcher_result = { status => 'failed' };
    @events = ();
    $image->build(entrypoint => "$root/app/bin/main.pl", name => 'noreason', progress => sub { push @events, $_[0] });
    ($failed) = grep { $_->{task_id} eq 'compile_launcher' && $_->{status} eq 'failed' } @events;
    like($failed->{label}, qr/\(failed\)/, 'failed label defaults reason');
    my $disk = $image->load(name => 'noreason');
    ok(!exists $disk->{launcher_reason}, 'empty reason is not stored');
    $launcher_result = { status => 'built' };
}

# values inherited from a previous standalone binary plan
{
    my $plan = {
        name => 'inherited',
        entrypoint => "$root/app/bin/main.pl",
        lib_dirs => ["$root/app/lib"],
        source_roots => [],
        assets => [],
        asset_dirs => [],
        runtime_mode => 'host_perl',
        app_name => 'Inherited',
        app_namespace => 'Foo::App',
        app_legacy_namespace => 'Foo::Old',
        app_entrypoint_env => 'INH_ENV',
        app_entrypoint_fallback => 'inh-fallback',
        app_command => 'inh-cmd',
        cpanfiles => [],
    };
    local *PAX::StandaloneImage::_standalone_source_plan = sub { return $plan };
    my $result = $image->build(entrypoint => "$root/app/bin/ignored-binary");
    is($result->{standalone}{name}, 'inherited', 'name from source plan');
    is($result->{standalone}{app}{name}, 'Inherited', 'app name from source plan');
    is($result->{standalone}{app}{compat}{legacy_namespace}, 'Foo::Old', 'legacy namespace from plan');
    is($result->{standalone}{app}{entrypoint_fallback}, 'inh-fallback', 'fallback from plan');
    is($result->{standalone}{app}{command}, 'inh-cmd', 'command from plan');
    is($result->{standalone}{runtime}{mode}, 'host_perl', 'runtime mode from plan');
}

# entrypoint with no lib dirs triggers app-tree inference
{
    my $dir = "$root/infer";
    write_file("$dir/Zed/Core.pm", "package Zed::Core; use strict; sub z { return 1 }\n1;\n");
    write_file("$dir/Zed/Core/Part.pm", "package Zed::Core::Part; use strict; sub p { return 1 }\n1;\n");
    write_file("$dir/run.pl", "#!/usr/bin/perl\nuse strict; use Zed::Core; use Zed::Core::Part;\n1;\n");
    my @events;
    my $result = $image->build(
        entrypoint => "$dir/run.pl",
        runtime_mode => 'host_perl',
        progress => sub { push @events, $_[0] },
    );
    my ($done) = grep { $_->{task_id} eq 'resolve_inputs' && $_->{status} eq 'done' } @events;
    like($done->{label}, qr/1 inferred app roots/, 'inferred app root counted');
    ok((grep { $_->{logical_path} =~ m{Zed/Core/Part} } @{ $result->{standalone}{code_units} }), 'inferred tree compiled');
    my @counts = map { $_->{label} } grep { $_->{task_id} eq 'analyze_dependencies' && $_->{status} eq 'done' } @events;
    like($counts[0], qr/Analyze runtime dependencies/, 'dependency label emitted');
}

# relative output paths resolve against the working directory; analysis labels default counts
{
    my $cwd = File::Spec->rel2abs('.');
    chdir $root or die "chdir: $!";
    my $result = eval {
        PAX::StandaloneImage->new(root => 'rel-root')->build(
            entrypoint => "$root/app/bin/main.pl",
            name => 'relimg',
            runtime_mode => 'host_perl',
            output_path => 'rel-out.bin',
        );
    };
    my $err = $@;
    chdir $cwd or die "chdir back: $!";
    is($err, '', 'relative build lives');
    is($result->{standalone}{output_path}, "$root/rel-out.bin", 'relative output made absolute');
    like($result->{standalone}{standalone_dir}, qr{\Q$root\E/rel-root/relimg\z}, 'relative root made absolute');
}

# source roots and empty lib dirs exercise the app-root inference conditions
{
    write_file("$root/srcroot/Tool/Thing.pm", "package Tool::Thing; use strict; sub t { return 1 }\n1;\n");
    make_path("$root/emptylib");
    my $entry = "$root/app/bin/main.pl";
    my $only_src = $image->build(
        entrypoint => $entry, name => 'srconly', runtime_mode => 'host_perl',
        source_roots => ["$root/srcroot"],
    );
    is(scalar(@{ $only_src->{standalone}{source_roots} }), 1, 'source root recorded');
    is($only_src->{standalone}{source_roots}[0], 'src/srcroot', 'source root logical path');
    ok((grep { ($_->{unit_kind} // '') eq 'source' } @{ $only_src->{standalone}{code_units} }), 'source unit compiled');

    my $mixed = $image->build(
        entrypoint => $entry, name => 'mixed', runtime_mode => 'host_perl',
        lib_dirs => ["$root/emptylib"], source_roots => ["$root/srcroot"],
    );
    is(scalar(@{ $mixed->{standalone}{source_roots} }), 1, 'empty lib dir with source root');

    my $empty_lib = $image->build(
        entrypoint => $entry, name => 'emptylib', runtime_mode => 'host_perl',
        lib_dirs => ["$root/emptylib"],
    );
    is($empty_lib->{standalone}{code_unit_count}, 1, 'empty lib dir leaves only the entrypoint unit');

    my $plan = { source_roots => ["$root/srcroot"] };
    local *PAX::StandaloneImage::_standalone_source_plan = sub { return $plan };
    my $planned = $image->build(entrypoint => $entry, name => 'planned', runtime_mode => 'host_perl');
    is(scalar(@{ $planned->{standalone}{source_roots} }), 1, 'source roots from plan');
}

# analysis summaries without counters fall back to zero in the progress labels
{
    my @events;
    local *PAX::StandaloneAnalysis::dependencies = sub { return { items => [], summary => {} } };
    local *PAX::StandaloneAnalysis::native_artifacts = sub { return { items => [], summary => {}, runtime_epochs => {} } };
    $image->build(
        entrypoint => "$root/app/bin/main.pl", name => 'zero', runtime_mode => 'host_perl',
        progress => sub { push @events, $_[0] },
    );
    my ($dep) = grep { $_->{task_id} eq 'analyze_dependencies' && $_->{status} eq 'done' } @events;
    my ($nat) = grep { $_->{task_id} eq 'analyze_native' && $_->{status} eq 'done' } @events;
    like($dep->{label}, qr/\(0 packaged, 0 bundled XS\)/, 'dependency counters default to zero');
    like($nat->{label}, qr/\(0 native-ready, 0 fallback-only\)/, 'native counters default to zero');
}

done_testing;
