use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;

=pod

=head1 NAME

t/dashboard_parity.t - standalone binary versus stock Perl parity for a real application

=head1 WHY IT EXISTS

PAX compiles some application subs into hand-written ops. When the application
changes, a stale op keeps matching and silently changes behavior. This test
builds a real application with PAX and diffs the standalone binary's output
against the interpreter, so that drift shows up as a failure.

=head1 DESCRIPTION

The application is the Developer Dashboard checkout next to this repository
(or the directory named by C<PAX_PARITY_APP>). The test skips itself when that
checkout or its CPAN dependencies are not available.

=head1 HOW TO RUN

  prove -l t/dashboard_parity.t

=cut

my $app = $ENV{PAX_PARITY_APP} // abs_path("$FindBin::Bin/../../developer-dashboard") // '';
plan skip_all => 'no Developer Dashboard checkout found (set PAX_PARITY_APP)'
    if !$app || !-f "$app/bin/dashboard";

my $pax = abs_path("$FindBin::Bin/../bin/pax");
my $tmp = tempdir('pax-parity-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# run_command(label => ..., cmd => [...])
# Runs one command in a fresh HOME and normalizes paths and timestamps.
# Input: label and command list. Output: (exit status, normalized output text).
sub run_command {
    my (%args) = @_;
    my $home = File::Spec->catdir($tmp, 'home');  # same path for both runs so padding and state keys match
    remove_tree($home);
    make_path($home);
    $args{setup}->($home) if $args{setup};
    my $out = File::Spec->catfile($tmp, "$args{label}.out");
    local $ENV{HOME} = $home;
    local $ENV{TMPDIR} = $tmp;   # payload extraction lands in the tempdir that is removed afterwards
    local $ENV{PAX_PROGRESS} = 0;
    my $cmd = join ' ', map { "'$_'" } @{ $args{cmd} };
    my $cwd = $args{cwd} ? "$home/$args{cwd}" : $app;
    my $status = system("cd '$cwd' && $cmd >'$out' 2>&1 </dev/null");
    open my $fh, '<:raw', $out or die "cannot read $out: $!";
    my $text = do { local $/; <$fh> } // '';
    close $fh;
    $text =~ s/\Q$home\E/HOME/g;
    $text =~ s{\S*?/pax-standalone-cache-[0-9a-f]+/(?:code/lib/lib|runtime/inc/\d+)}{LIB}g;
    $text =~ s{\Q$app\E/bin/\.\./lib}{LIB}g;
    $text =~ s{\Q$app\E/lib}{LIB}g;
    $text =~ s/\d{4}-\d{2}-\d{2}[T ][\d:.]+Z?/TS/g;
    $text =~ s{ at (?:\S+\.pm|PAX::StandaloneRuntime op \w+) line \d+\.}{ at LOC.}g;  # die location differs inside handlers
    $text =~ s/\b1\d{9}\.\d+\b/EPOCH/g;
    return ($status >> 8, $text);
}

my ($stock_rc, $stock_version) = run_command(label => 'probe', cmd => [ $^X, "-I$app/lib", "$app/bin/dashboard", 'version' ]);
plan skip_all => 'Developer Dashboard dependencies are not installed'
    if $stock_rc != 0 || $stock_version !~ /^\d/;

my $binary = File::Spec->catfile($tmp, 'parity-app');
my $build_started = time;
my $build_rc = system("cd '$app' && PAX_PROGRESS=0 '$^X' '$pax' build --compact -o '$binary' bin/dashboard >'$tmp/build.json' 2>'$tmp/build.err'");
is($build_rc >> 8, 0, 'PAX builds the application CLI');
ok(-x $binary, 'standalone binary exists');
cmp_ok(time - $build_started, '<', 60, 'build finishes within one minute');

my $started = time;
for my $args (
    'version',
    'help',
    '--help',
    '-h',
    'nosuchcommand',
    'which ps1',
    'which jq',
    'init',
    'doctor',
    'page new',
    'page list',
    'config list',
    'path cdr x',
    'path list',
    'paths',
    'files --help',
    'skills list',
    'skill list',
    'sample.skill',
    'upgrade --dry-run',
    'jq --help',
    'yq --help',
    'tomq --help',
    'propq --help',
    'iniq --help',
    'csvq --help',
    'decode --help',
    'api --help',
    'ask --help',
    'auth --help',
    'workspace --help',
    'file --help',
    'action --help',
    'docker --help',
    'cpan --help',
    'init --help',
    'ps1 --help',
    'of --help',
    'open-file --help',
    'config --help',
    'indicator --help',
    'collector --help',
    'ps1',
    'indicator list',
    'indicator set x --status ok',
    'housekeeper',
    'config show',
    'auth list-users',
    'collector list',
    'file list',
    'page source nope',
    'jq --help',
    'decode aGVsbG8=',
    'path cdr x',
) {
    my @args = split ' ', $args;
    my ($srv, $stock) = run_command(label => 'stock', cmd => [ $^X, "-I$app/lib", "$app/bin/dashboard", @args ]);
    my ($brc, $bin) = run_command(label => 'bin', cmd => [ $binary, @args ]);
    $stock =~ s/\Q$app\E\/bin\/dashboard/dashboard/g;
    is($brc, $srv, "'$args' exits with the same status as stock Perl");
    is($bin, $stock, "'$args' prints the same output as stock Perl");
}

# Layered configuration: .env / .env.pl / .d2 / config.json / custom commands are
# discovered from the working directory up through its parents.
sub write_layers {
    my ($home) = @_;
    for my $dir (qw(.developer-dashboard/cli .developer-dashboard/config proj/.developer-dashboard/cli proj/.developer-dashboard/config proj/sub/.d2/cli proj/sub/deep)) {
        make_path("$home/$dir");
    }
    my $put = sub { my ($path, $text, $mode) = @_; open my $o, '>', "$home/$path" or die "$path: $!"; print {$o} $text; close $o; chmod $mode, "$home/$path" if $mode; };
    $put->('.developer-dashboard/cli/showenv', "#!/bin/sh\nenv | grep '^T_' | sort\n", 0755);
    $put->('.developer-dashboard/.env', "T_A=home\nT_H=fromhome\n");
    $put->('proj/.developer-dashboard/.env', "// c\n/* block\ncomment */\nT_A=proj\nT_B=\${T_A}-b\nT_TILDE=~/x\nT_DEF=\${T_MISSING:-fallback}\nT_FN=\${Cwd::getcwd():-nofn}\n");
    $put->('proj/.env.pl', "\$ENV{T_PL} = 'pl-proj'; \$ENV{T_A} = 'pl-' . \$ENV{T_A};\n");
    $put->('proj/sub/.d2/.env.pl', "\$ENV{T_C} = 'd2pl';\n");
    $put->('.developer-dashboard/config/config.json', '{"web":{"port":7001},"alias":{"a":"home"}}' . "\n");
    $put->('proj/.developer-dashboard/config/config.json', '{"web":{"port":7002},"alias":{"b":"proj"}}' . "\n");
    for my $dir (qw(.developer-dashboard proj/.developer-dashboard proj/sub/.d2)) {
        $put->("$dir/cli/who", "#!/bin/sh\necho layer-$dir \$*\n", 0755);
    }
    return;
}
for my $args ('showenv', 'who a b', 'which who', 'which showenv', 'config list', 'path list', 'paths', 'doctor') {
    my @args = split ' ', $args;
    my %common = (setup => \&write_layers, cwd => 'proj/sub/deep');
    my ($srv, $stock) = run_command(%common, label => 'lstock', cmd => [ $^X, "-I$app/lib", "$app/bin/dashboard", @args ]);
    my ($brc, $bin) = run_command(%common, label => 'lbin', cmd => [ $binary, @args ]);
    $stock =~ s/\Q$app\E\/bin\/dashboard/dashboard/g;
    is($brc, $srv, "layered '$args' exits with the same status as stock Perl");
    is($bin, $stock, "layered '$args' prints the same output as stock Perl");
}

# Installed skills with nested skills: each level contributes its own .env, deeper levels win,
# and `.d` hooks run before the command.
sub write_skills {
    my ($home) = @_;
    my $root = "$home/.developer-dashboard/skills/foo";
    make_path("$root/cli/hello.d", "$root/skills/bar/cli", "$root/skills/bar/skills/zzz/cli");
    my $put = sub { my ($path, $text, $mode) = @_; open my $o, '>', "$root/$path" or die "$path: $!"; print {$o} $text; close $o; chmod $mode, "$root/$path" if $mode; };
    $put->('.env', "VERSION=top\nT_TOP=1\n");
    $put->('.env.pl', "\$ENV{T_PL_TOP} = 'pltop';\n");
    $put->('cli/hello', "#!/bin/sh\necho \"hello VERSION=\$VERSION TOP=\$T_TOP PL=\$T_PL_TOP args=\$*\"\n", 0755);
    $put->('cli/hello.d/00-pre', "#!/bin/sh\necho pre-hook\n", 0755);
    $put->('skills/bar/.env', "VERSION=bar\nT_BAR=2\n");
    $put->('skills/bar/cli/mid', "#!/bin/sh\necho \"mid VERSION=\$VERSION TOP=\$T_TOP BAR=\$T_BAR\"\n", 0755);
    $put->('skills/bar/skills/zzz/.env', "VERSION=leaf\n");
    $put->('skills/bar/skills/zzz/cli/show', "#!/bin/sh\necho \"show VERSION=\$VERSION TOP=\$T_TOP BAR=\$T_BAR\"\n", 0755);
    system("cd '$root' && git init -q . >/dev/null 2>&1");
    return;
}
for my $args ('foo.hello a b', 'foo.bar.mid', 'foo.bar.zzz.show', 'which foo.bar.zzz.show', 'foo.nothing', 'skills list') {
    my @args = split ' ', $args;
    my %common = (setup => \&write_skills);
    my ($srv, $stock) = run_command(%common, label => 'sstock', cmd => [ $^X, "-I$app/lib", "$app/bin/dashboard", @args ]);
    my ($brc, $bin) = run_command(%common, label => 'sbin', cmd => [ $binary, @args ]);
    $stock =~ s/\Q$app\E\/bin\/dashboard/dashboard/g;
    is($brc, $srv, "skill '$args' exits with the same status as stock Perl");
    is($bin, $stock, "skill '$args' prints the same output as stock Perl");
}

done_testing();
