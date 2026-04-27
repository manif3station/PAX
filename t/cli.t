use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path getcwd);
use File::Path qw(make_path remove_tree);
use File::Spec;
use FindBin;
use JSON::PP qw(decode_json);

=pod

=head1 NAME

t/cli.t - SOW-03 public CLI contract tests

=head1 DESCRIPTION

This test file verifies that C<bin/pax> exposes only C<build> and C<run> to
users. Older diagnostics remain implementation internals and must not be
reachable as public subcommands.

=cut

my $repo = abs_path("$FindBin::Bin/..");
my $pax = "$repo/bin/pax";
my $sow03_root = "$repo/t/tmp-sow03";
remove_tree($sow03_root) if -d $sow03_root;
make_path($sow03_root);

my $help = `$^X $pax help`;
is($? >> 8, 0, 'pax help exits successfully');
like($help, qr/^usage:\n  pax build /, 'help starts with build usage');
like($help, qr/^  pax run /m, 'help includes run usage');
unlike($help, qr/\bpax (?:capture|standalone-build|app-build|bench|gatekeeper)\b/, 'help omits non-public commands');

my $old_cli = `$^X $pax capture --compact t/fixtures/simple.pl 2>&1`;
is($? >> 8, 2, 'removed public command exits with usage error');
like($old_cli, qr/unknown command: capture/, 'removed command reports unknown command');
like($old_cli, qr/^usage:\n  pax build /m, 'removed command prints SOW-03 usage');
unlike($old_cli, qr/\bpax standalone-build\b|\bpax app-build\b/, 'removed command usage stays minimal');

my $build_json = `$^X $pax build --compact --paxfile t/fixtures/paxfile.yml`;
is($? >> 8, 0, 'pax build exits successfully using paxfile defaults');
my $build = decode_json($build_json);
my $paxfile_binary = File::Spec->rel2abs("$repo/t/tmp-sow03/fixture-app");
is($build->{status}, 'built', 'build command creates standalone binary');
is($build->{standalone}{output_path}, $paxfile_binary, 'build command honors paxfile output');
ok(-x $build->{standalone}{output_path}, 'build output binary is executable');

my $run_output = `$^X $pax run --paxfile t/fixtures/paxfile.yml -- status`;
is($? >> 8, 0, 'pax run exits successfully using paxfile defaults');
is($run_output, "slowload-ready\n", 'run command executes the built standalone binary');

my $override_binary = File::Spec->rel2abs("$sow03_root/override-binary");
my $override_build_json = `$^X $pax build --compact --paxfile t/fixtures/paxfile.yml -o $override_binary`;
is($? >> 8, 0, 'pax build accepts -o output override');
my $override_build = decode_json($override_build_json);
is($override_build->{standalone}{output_path}, $override_binary, 'build command records overridden output path');
ok(-x $override_binary, 'overridden build output is executable');

my $override_run_output = `$^X $pax run --paxfile t/fixtures/paxfile.yml --output $override_binary -- asset`;
is($? >> 8, 0, 'pax run accepts --output override');
is($override_run_output, "embedded-fixture-asset\n", 'run command executes binary with embedded asset');

my $progress_json = "$sow03_root/progress-build.json";
my $progress_stderr = "$sow03_root/progress-build.stderr";
system("PAX_PROGRESS=1 $^X $pax build --compact --paxfile t/fixtures/paxfile.yml >$progress_json 2>$progress_stderr");
is($? >> 8, 0, 'pax build still succeeds when progress rundown is enabled');
open my $progress_fh, '<', $progress_stderr or die "cannot read progress stderr: $!";
my $progress_text = do { local $/; <$progress_fh> };
close $progress_fh;
like($progress_text, qr/pax build progress/, 'pax build progress output prints the task-board title');
like($progress_text, qr/\[ \] Resolve build inputs/, 'pax build progress output prints the full task list before work begins');
like($progress_text, qr/\[OK\] Compile standalone launcher/, 'pax build progress output marks the launcher phase complete');
open my $progress_json_fh, '<', $progress_json or die "cannot read progress json: $!";
my $progress_payload = do { local $/; <$progress_json_fh> };
close $progress_json_fh;
my $progress_build = decode_json($progress_payload);
is($progress_build->{status}, 'built', 'pax build keeps machine-readable payload on stdout while progress prints on stderr');

my $workdir = "$sow03_root/work";
make_path($workdir);
my $no_arg_binary = "$sow03_root/no-arg-binary";
open my $pfh, '>', "$workdir/paxfile.yml" or die "cannot write test paxfile: $!";
print {$pfh} join("\n",
    "name: no-arg-fixture",
    "entrypoint: $repo/t/fixtures/app_entry.pl",
    "output: $no_arg_binary",
    "libs:",
    "  - $repo/t/fixtures/app_lib",
    "assets:",
    "  - $repo/t/fixtures/app_assets/banner.txt",
    "",
);
close $pfh or die "cannot close test paxfile: $!";
my $no_arg_build_json = `cd $workdir && $^X $pax build --compact`;
is($? >> 8, 0, 'pax build with no arguments reads local paxfile.yml');
my $no_arg_build = decode_json($no_arg_build_json);
is($no_arg_build->{standalone}{output_path}, $no_arg_binary, 'no-argument build honors paxfile output');
ok(-x $no_arg_binary, 'no-argument build output is executable');
my $no_arg_run_output = `cd $workdir && $^X $pax run -- status`;
is($? >> 8, 0, 'pax run with no build arguments reads local paxfile.yml');
is($no_arg_run_output, "slowload-ready\n", 'no-argument run executes built standalone binary');

my $blank = "$sow03_root/blank";
make_path($blank);
my $self_binary = "$sow03_root/pax-self";
my $self_build_log = "$sow03_root/pax-self-build.json";
system("cd $blank && $^X $pax build --compact -o $self_binary $repo/bin/pax > $self_build_log");
is($? >> 8, 0, 'pax build -o output bin/pax succeeds from a blank directory without paxfile.yml');
ok(-x $self_binary, 'self-built pax binary is executable');
my $self_help = `cd $blank && env -i PATH=/nonexistent TMPDIR=/tmp $self_binary help`;
is($? >> 8, 0, 'self-built pax runs without source checkout in its working directory');
like($self_help, qr/^usage:\n  pax build /, 'self-built pax prints build usage');
unlike($self_help, qr/\bpax standalone-build\b|\bpax app-build\b|\bpax capture\b/, 'self-built pax keeps SOW-03 CLI surface');

my $self_run_binary = "$sow03_root/pax-self-run";
my $self_run_output = `cd $blank && $^X $pax run --compact -o $self_run_binary $repo/bin/pax -- help`;
is($? >> 8, 0, 'pax run bin/pax builds then runs self-built pax');
like($self_run_output, qr/^usage:\n  pax build /, 'pax run bin/pax emits self-built help output');
ok(-x $self_run_binary, 'pax run self-build writes requested binary');

my $nested_workdir = "$sow03_root/self-hosted-build";
make_path($nested_workdir);
my $nested_binary = "$nested_workdir/nested-app";
open my $nested_pfh, '>', "$nested_workdir/paxfile.yml" or die "cannot write nested paxfile: $!";
print {$nested_pfh} join("\n",
    "name: nested-app",
    "entrypoint: $repo/t/fixtures/app_entry.pl",
    "output: $nested_binary",
    "libs:",
    "  - $repo/t/fixtures/app_lib",
    "assets:",
    "  - $repo/t/fixtures/app_assets/banner.txt",
    "",
);
close $nested_pfh or die "cannot close nested paxfile: $!";
my $nested_build_json = `cd $nested_workdir && env -i PATH=/nonexistent TMPDIR=/tmp $self_binary build --compact`;
is($? >> 8, 0, 'self-built pax can build another standalone binary from paxfile defaults');
my $nested_build = decode_json($nested_build_json);
is($nested_build->{status}, 'built', 'self-built pax reports successful nested build');
ok(-x $nested_binary, 'self-built pax writes nested standalone binary');
my $nested_status = `env -i PATH=/nonexistent TMPDIR=/tmp $nested_binary status`;
is($? >> 8, 0, 'nested standalone binary built by self-built pax executes');
is($nested_status, "slowload-ready\n", 'nested standalone built by self-built pax returns expected output');

done_testing;
