use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

# fork failures are simulated by overriding fork before the module compiles.
our $FAIL_FORK = 0;
our $WAITPID_HOOK;
BEGIN {
    *CORE::GLOBAL::fork = sub {
        return undef if $main::FAIL_FORK;
        return CORE::fork();
    };
    *CORE::GLOBAL::waitpid = sub ($$) {
        $main::WAITPID_HOOK->(@_) if $main::WAITPID_HOOK;
        return CORE::waitpid($_[0], $_[1]);
    };
}

use POSIX ();
use PAX::CodeUnitCompiler;
use PAX::StandaloneImage;

=pod

=head1 NAME

t/cov_sima_manifest.t - coverage for code-unit manifest assembly helpers

=head1 DESCRIPTION

Exercises C<_code_manifest> (application and dependency unit discovery with
progress reporting), the namespace/prefix inference helpers, the sibling-script
warning, and the forked parallel compile helper using tiny fabricated trees and
fake compiler objects.

=head1 WHY IT EXISTS

These helpers decide which Perl files end up in a standalone image and how fast
the build runs. Their edge cases (worker failures, serial fallback, duplicate
files, entrypoints that fall back to source) are expensive to reach through full
image builds, so they are driven directly here.

=cut

$ENV{PAX_CODE_UNIT_CAPTURE} = 'never';
$ENV{PAX_JOBS} = 1;

my $root = tempdir('pax-cov-sima-manifest-XXXXXX', TMPDIR => 1, CLEANUP => 1);

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

# wait_for_workers()
# Blocks until every child of this process has exited (or become a zombie), so
# polling tests do not depend on how slowly a forked worker shuts down.
# Input: none. Output: none.
sub wait_for_workers {
    my $deadline = time + 30;
    while (time < $deadline) {
        my $children = do {
            open my $fh, '<', "/proc/$$/task/$$/children" or last;
            local $/;
            <$fh>;
        };
        my $alive = 0;
        for my $pid (split ' ', $children // '') {
            open my $st, '<', "/proc/$pid/stat" or next;
            my $line = <$st>;
            $alive++ if defined $line && $line =~ /\)\s+([A-Za-z])/ && $1 ne 'Z';
        }
        last if !$alive;
        select(undef, undef, undef, 0.05);
    }
    return;
}

# namespace inference
{
    is(PAX::StandaloneImage::_infer_app_namespace(), '', 'no units');
    is(PAX::StandaloneImage::_infer_app_namespace(units => [ {}, { package => '' }, { package => 'Single' } ]), '', 'units without namespaces');
    is(
        PAX::StandaloneImage::_infer_app_namespace(units => [ { package => 'App::Core::One' }, { module => 'App::Core::Two' }, { package => 'Other::X' } ]),
        'App::Core',
        'deepest most common prefix wins',
    );
    like(PAX::StandaloneImage::_infer_app_namespace(units => [ { package => 'A::B' }, { package => 'C::D' } ]), qr/\A(?:A::B|C::D)\z/, 'ties pick one');
}

# path helpers
{
    my $cwd = File::Spec->rel2abs('.');
    is(PAX::StandaloneImage::_absolute_output('/abs/x'), '/abs/x', 'absolute kept');
    is(PAX::StandaloneImage::_absolute_output('rel/x'), "$cwd/rel/x", 'relative resolved');

    make_path("$root/p/one", "$root/p/two");
    is_deeply(
        [ PAX::StandaloneImage::_abs_existing([ "$root/p/one", "$root/p/./one", "$root/p/none/x", "$root/p/two" ]) ],
        [ "$root/p/one", "$root/p/two" ],
        'existing, unique absolute paths',
    );

    is_deeply([ PAX::StandaloneImage::_entrypoint_declared_lib_dirs("$root/p/missing.pl") ], [], 'unreadable entrypoint');
    is_deeply([ PAX::StandaloneImage::_entrypoint_declared_lib_dirs(write_file("$root/p/empty.pl", '')) ], [], 'empty entrypoint');
    make_path("$root/p/bin/lib", "$root/p/abs");
    my $script = write_file("$root/p/bin/s.pl", join("\n",
        'use strict;',
        'use FindBin qw($Bin);',
        'use lib "$FindBin::Bin/lib";',
        "use lib '\$Bin/lib', 'rel-missing';",
        "use lib '$root/p/abs';",
        "  use lib 'lib' ;",
        "print 1;",
    ) . "\n");
    is_deeply(
        [ PAX::StandaloneImage::_entrypoint_declared_lib_dirs($script) ],
        [ "$root/p/bin/lib", "$root/p/abs" ],
        'declared use lib directories resolved and deduplicated',
    );

    is(PAX::StandaloneImage::_logical_root('lib', '/a/b/c'), 'lib/c', 'logical root leaf');
    is(PAX::StandaloneImage::_logical_root('lib', '/'), 'lib', 'logical root of filesystem root');
    is(PAX::StandaloneImage::_progress_source_label('lib', 'A/B.pm'), 'lib:A/B.pm', 'nested label');
    is(PAX::StandaloneImage::_progress_source_label('src', 'x.pl'), 'src:x.pl', 'flat label');
    is(PAX::StandaloneImage::_progress_source_label('src', undef), 'src:', 'undef label');
}

# worker count
{
    local $ENV{PAX_JOBS} = 3;
    is(PAX::StandaloneImage::_build_job_count(), 3, 'PAX_JOBS honoured');
    local $ENV{PAX_JOBS} = '0';
    my $auto = PAX::StandaloneImage::_build_job_count();
    ok($auto >= 1 && $auto <= 8, 'zero means auto');
    local $ENV{PAX_JOBS} = 'many';
    is(PAX::StandaloneImage::_build_job_count(), $auto, 'non-numeric means auto');
    delete $ENV{PAX_JOBS};
    is(PAX::StandaloneImage::_build_job_count(), $auto, 'unset means auto');
}

# module prefix helpers
{
    is_deeply([ PAX::StandaloneImage::_declared_app_prefixes() ], [], 'no modules');
    is_deeply([ PAX::StandaloneImage::_declared_app_prefixes('', 'Single', 'strict') ], [], 'skipped modules');
    is_deeply([ PAX::StandaloneImage::_declared_app_prefixes('A::B::C', 'A::B::D', 'A::B::C') ], ['A::B'], 'repeated modules still collapse to the shared prefix');
    is_deeply([ PAX::StandaloneImage::_declared_app_prefixes('A::B::C', 'A::B::D', 'A::B::E', 'A::B::C') ], ['A::B'], 'nested candidates collapse into the shorter one');
    is_deeply([ PAX::StandaloneImage::_declared_app_prefixes('Zed::One', 'Zed::Two', 'Zed::One', 'Other::Lone') ], ['Zed::One'], 'most common prefix selected');
    is_deeply([ PAX::StandaloneImage::_declared_app_prefixes('Zed::A', 'Yak::B', 'Zed::A') ], ['Zed::A'], 'ties broken by depth then name');
    is_deeply([ sort(PAX::StandaloneImage::_declared_app_prefixes('One::Two', 'Three::Four')) ], [ 'One', 'Three' ], 'single-use modules fall back to parent prefixes');
    is_deeply([ PAX::StandaloneImage::_declared_app_prefixes('Only::Mod::X', 'Plain') ], ['Only::Mod'], 'fallback drops bare names');

    is_deeply([ PAX::StandaloneImage::_declared_app_prefixes('A::B::C', 'A::B::C') ], ['A::B::C', 'A::B'], 'equal counts prefer the deeper prefix first');
    is_deeply([ PAX::StandaloneImage::_declared_app_prefixes('R::S', 'P::Q', 'R::S', 'P::Q') ], ['P::Q', 'R::S'], 'unrelated candidates are all selected, ordered by name');
    is_deeply([ PAX::StandaloneImage::_declared_app_prefixes('::X') ], [], 'empty parent prefix is dropped');

    is(PAX::StandaloneImage::_module_base_dir_for_files(undef, '/a/Foo/Bar.pm'), undef, 'no module');
    is(PAX::StandaloneImage::_module_base_dir_for_files('Foo::Bar', undef), undef, 'no path');
    is(PAX::StandaloneImage::_module_base_dir_for_files('Foo::Bar', '/a/Foo/Baz.pm'), undef, 'mismatched path');
    is(PAX::StandaloneImage::_module_base_dir_for_files('Foo::Bar', '/a/lib/Foo/Bar.pm'), '/a/lib', 'base dir');
    is(PAX::StandaloneImage::_module_base_dir_for_files('Foo::Bar', 'C:\\a\\lib\\Foo\\Bar.pm'), 'C:/a/lib', 'backslash paths normalised') if File::Spec->catfile('a', 'b') eq 'a/b';
}

# namespace tree files and app file sets
{
    my $dir = "$root/ns";
    write_file("$dir/Zed/Core.pm", "package Zed::Core; use strict; sub z { return 1 }\n1;\n");
    write_file("$dir/Zed/Core/Part.pm", "package Zed::Core::Part; use strict; sub p { return 1 }\n1;\n");
    write_file("$dir/Zed/Core/data.txt", "ignored\n");
    write_file("$dir/Solo/One.pm", "package Solo::One; use strict; sub s { return 1 }\n1;\n");
    write_file("$dir/Boot/Strap/Bootstrap.pm", "package Boot::Strap::Bootstrap; use strict; sub b { return 1 }\n1;\n");
    write_file("$dir/Boot/Strap/Inner.pm", "package Boot::Strap::Inner; use strict; sub i { return 1 }\n1;\n");

    my @files = PAX::StandaloneImage::_namespace_tree_files('Zed::Core', [$dir]);
    is_deeply(\@files, [ "$dir/Zed/Core.pm", "$dir/Zed/Core/Part.pm" ], 'root module plus subtree');
    @files = PAX::StandaloneImage::_namespace_tree_files('Solo::One', [$dir]);
    is_deeply(\@files, [ "$dir/Solo/One.pm" ], 'root module without subtree');
    is_deeply([ PAX::StandaloneImage::_namespace_tree_files('Nothing::Here', [$dir]) ], [], 'unknown prefix');
    is_deeply([ PAX::StandaloneImage::_namespace_tree_files('', [$dir]) ], [], 'empty prefix');

    # the bootstrap fallback needs a base dir the module path cannot yield; stub the locator pieces
    {
        no warnings 'redefine';
        my $base;
        local *PAX::StandaloneImage::_module_base_dir_for_files = sub { return $base };
        $base = undef;
        is_deeply([ PAX::StandaloneImage::_namespace_tree_files('Boot::Strap', [$dir]) ], [], 'fallback without a base dir');
        $base = "$dir";
        my @tree = PAX::StandaloneImage::_namespace_tree_files('Boot::Strap', [$dir]);
        is_deeply(\@tree, [ "$dir/Boot/Strap/Bootstrap.pm", "$dir/Boot/Strap/Inner.pm" ], 'bootstrap fallback lists the namespace tree');
        $base = "$dir/nowhere";
        is_deeply([ PAX::StandaloneImage::_namespace_tree_files('Boot::Strap', [$dir]) ], [], 'fallback with a missing subtree');
    }

    # a located path that is not a file falls through to the bootstrap lookup
    {
        no warnings 'redefine';
        my @asked;
        local *PAX::StandaloneImage::_locate_pure_perl_module = sub { push @asked, $_[0]; return $_[0] eq 'Zed::Core' ? "$dir/not/a/file.pm" : undef };
        is_deeply([ PAX::StandaloneImage::_namespace_tree_files('Zed::Core', [$dir]) ], [], 'non-file module path and no bootstrap module');
        is_deeply(\@asked, [ 'Zed::Core', 'Zed::Core::Bootstrap' ], 'bootstrap module consulted');
    }
    {
        no warnings 'redefine';
        local *PAX::StandaloneImage::_declared_app_prefixes = sub { return ('Zed::Core') };
        local *PAX::StandaloneImage::_namespace_tree_files = sub { return ('Zed/Core.pm') };
        is_deeply([ PAX::StandaloneImage::_infer_entrypoint_app_file_sets(write_file("$dir/zed.pl", "use Zed::Core;\n")) ], [], 'files that map to an empty base dir are ignored');
    }

    is(PAX::StandaloneImage::_application_root_file_count([], []), 0, 'no roots');
    is(PAX::StandaloneImage::_application_root_file_count(undef, undef), 0, 'undef roots');
    make_path("$root/emptyroot");
    is(PAX::StandaloneImage::_application_root_file_count(["$root/emptyroot"], [ "$dir/Solo" ]), 1, 'counts stop at the first populated root');

    my $entry = write_file("$dir/run.pl", "#!/usr/bin/perl\nuse strict;\nuse Zed::Core;\nuse Zed::Core::Part;\nuse Solo::One;\nuse Nowhere::Ghost;\n1;\n");
    my @sets = PAX::StandaloneImage::_infer_entrypoint_app_file_sets($entry);
    is(scalar(@sets), 1, 'one inferred app root');
    is($sets[0]{dir}, $dir, 'inferred base directory');
    is($sets[0]{kind}, 'lib', 'inferred kind');
    is($sets[0]{prefix}, 'lib/ns', 'inferred logical prefix');
    is(scalar(@{ $sets[0]{files} }), 2, 'inferred files');
    is_deeply([ PAX::StandaloneImage::_infer_entrypoint_app_file_sets("$dir/missing.pl") ], [], 'unreadable entrypoint');
    is_deeply([ PAX::StandaloneImage::_infer_entrypoint_app_file_sets(write_file("$dir/none.pl", "use strict;\nprint 1;\n")) ], [], 'no app prefixes');
    my $ghost = write_file("$dir/ghost.pl", "use Ghost::Alpha; use Ghost::Beta;\n");
    is_deeply([ PAX::StandaloneImage::_infer_entrypoint_app_file_sets($ghost) ], [], 'prefix without files');
    # the same prefix twice is only considered once
    {
        no warnings 'redefine';
        local *PAX::StandaloneImage::_declared_app_prefixes = sub { return ('Zed::Core', 'Zed::Core', '', 'Solo::One') };
        my @dup = PAX::StandaloneImage::_infer_entrypoint_app_file_sets($entry);
        is(scalar(@dup), 2, 'duplicate and empty prefixes skipped');
    }
    {
        no warnings 'redefine';
        local *PAX::StandaloneImage::_module_base_dir_for_files = sub { return };
        is_deeply([ PAX::StandaloneImage::_infer_entrypoint_app_file_sets($entry) ], [], 'prefix whose files do not map to a base dir');
    }
}

# sibling script warning
{
    my $dir = "$root/sib";
    write_file("$dir/real", "#!/usr/bin/perl\nprint 1;\n");
    my $alias = write_file("$dir/alias", "#!/usr/bin/perl\nuse FindBin qw(\$Bin);\nuse File::Spec;\nexec \$^X, File::Spec->catfile(\$Bin, 'real'), \@ARGV;\n");
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    PAX::StandaloneImage::_warn_unpackaged_sibling_script($alias, undef);
    PAX::StandaloneImage::_warn_unpackaged_sibling_script($alias, "print 1;\ncatfile(\$Bin, 'real')\n");
    is(scalar(@warnings), 0, 'no warning without exec');
    PAX::StandaloneImage::_warn_unpackaged_sibling_script($alias, "exec 'x', catfile(\$Bin, 'ghost');");
    is(scalar(@warnings), 0, 'no warning for a missing sibling');
    PAX::StandaloneImage::_warn_unpackaged_sibling_script($alias, "exec 'x', catfile(\$Bin, 'alias');");
    is(scalar(@warnings), 0, 'no warning when the sibling is the entrypoint itself');
    PAX::StandaloneImage::_warn_unpackaged_sibling_script($alias, "exec \$^X, File::Spec->catfile(\$Bin, 'real'), \@ARGV;");
    is(scalar(@warnings), 1, 'warning for a real sibling');
    like($warnings[0], qr/launches the sibling script 'real'.*build \Q$dir\E\/real instead/, 'warning names the sibling');
}

# parallel compile helper
{
    # a fake compiler that records which process compiled each job
    {
        package Cov::SimaFake;
        # new(%opts): builds a fake compiler. Input: options. Output: object.
        sub new { my ($class, %opts) = @_; return bless {%opts}, $class }
        # compile(%job): fabricates a unit, or misbehaves as configured.
        # Input: job fields. Output: unit hash (or undef/die/exit as configured).
        sub compile {
            my ($self, %job) = @_;
            if ($self->{only_in_child} && $$ == $self->{parent}) {
                return { path => $job{path}, pid_kind => 'parent' };
            }
            POSIX::_exit(0) if $self->{die_silently_in_child} && $$ != $self->{parent};
            POSIX::_exit(0) if $self->{die_silently_for} && $$ != $self->{parent} && $job{path} eq $self->{die_silently_for};
            return 'plain string' if $self->{parent_string} && $$ == $self->{parent};
            select(undef, undef, undef, $self->{delay}{ $job{path} } // 0) if $self->{delay} && $$ != $self->{parent};
            die "boom for $job{path}\n" if $self->{die_for} && $job{path} eq $self->{die_for};
            return undef if $self->{undef_for} && $job{path} eq $self->{undef_for};
            return { path => $job{path}, kind => $job{kind}, pid_kind => ($$ == $self->{parent} ? 'parent' : 'child') };
        }
    }

    my @jobs = map { +{ path => "/p/$_.pm", kind => 'lib', logical_path => "lib/$_.pm" } } qw(a b c d e);

    {
        local $ENV{PAX_JOBS} = 1;
        my @seen;
        my @units = PAX::StandaloneImage::_compile_jobs_parallel(Cov::SimaFake->new(parent => $$), \@jobs, sub { push @seen, [ $_[0], $_[1]{path} ] });
        is_deeply([ map { $_->{path} } @units ], [ map { $_->{path} } @jobs ], 'serial results keep job order');
        ok(!(grep { $_->{pid_kind} ne 'parent' } @units), 'serial compile stays in process');
        is(scalar(@seen), 10, 'callback before and after each serial job');
        my @plain = PAX::StandaloneImage::_compile_jobs_parallel(Cov::SimaFake->new(parent => $$), [ $jobs[0] ], undef);
        is(scalar(@plain), 1, 'serial without callback');
    }
    # forked workers must leave through a normal exit so that coverage and END blocks are flushed
    no warnings 'redefine';
    local *POSIX::_exit = sub { CORE::exit($_[0]) };
    use warnings 'redefine';

    {
        local $ENV{PAX_JOBS} = 2;
        my @seen;
        my $fake = Cov::SimaFake->new(parent => $$, delay => { '/p/b.pm' => 0.3, '/p/d.pm' => 0.3 });
        my @units = PAX::StandaloneImage::_compile_jobs_parallel($fake, \@jobs, sub { push @seen, $_[0] });
        is_deeply([ map { $_->{path} } @units ], [ map { $_->{path} } @jobs ], 'parallel results keep job order');
        ok(!(grep { $_->{pid_kind} ne 'child' } @units), 'parallel compile happens in workers');
        is_deeply([ sort { $a <=> $b } @seen ], [ 1 .. 5 ], 'callback receives running counts');
        my @plain = PAX::StandaloneImage::_compile_jobs_parallel(Cov::SimaFake->new(parent => $$), \@jobs, undef);
        is(scalar(@plain), 5, 'parallel without callback');
    }
    {
        # auto-reaped workers make waitpid report -1; their results are then read by the fallback
        local $ENV{PAX_JOBS} = 2;
        local $SIG{CHLD} = 'IGNORE';
        my $first = 1;
        local $main::WAITPID_HOOK = sub {
            return if !$first;
            $first = 0;
            wait_for_workers();
        };
        my $fake = Cov::SimaFake->new(parent => $$, delay => { '/p/a.pm' => 0.2, '/p/b.pm' => 0.3 });
        my @units = PAX::StandaloneImage::_compile_jobs_parallel($fake, [ @jobs[0, 1] ], undef);
        is_deeply([ map { $_->{path} } @units ], [ '/p/a.pm', '/p/b.pm' ], 'results survive auto-reaped workers');
        ok(!(grep { $_->{pid_kind} ne 'child' } @units), 'auto-reaped results came from the workers');
    }
    {
        local $ENV{PAX_JOBS} = 8;
        my @units = PAX::StandaloneImage::_compile_jobs_parallel(Cov::SimaFake->new(parent => $$), [ @jobs[0, 1] ], undef);
        is(scalar(@units), 2, 'worker count is clamped to the job count');
        is_deeply([ PAX::StandaloneImage::_compile_jobs_parallel(Cov::SimaFake->new(parent => $$), [], undef) ], [], 'no jobs');
    }
    {
        local $ENV{PAX_JOBS} = 2;
        eval { PAX::StandaloneImage::_compile_jobs_parallel(Cov::SimaFake->new(parent => $$, die_for => '/p/c.pm'), \@jobs, undef) };
        like($@, qr{compile of /p/c\.pm failed: boom for /p/c\.pm}, 'worker compile error is reported');
        eval { PAX::StandaloneImage::_compile_jobs_parallel(Cov::SimaFake->new(parent => $$, undef_for => '/p/b.pm'), \@jobs, undef) };
        like($@, qr{compile of /p/b\.pm failed: compile failed}, 'worker returning nothing is reported');
    }
    {
        # workers that vanish without writing results are compiled serially by the parent
        local $ENV{PAX_JOBS} = 2;
        my @units = PAX::StandaloneImage::_compile_jobs_parallel(Cov::SimaFake->new(parent => $$, die_silently_in_child => 1), \@jobs, undef);
        is_deeply([ map { $_->{path} } @units ], [ map { $_->{path} } @jobs ], 'dead workers fall back to the parent');
        ok(!(grep { $_->{pid_kind} ne 'parent' } @units), 'fallback compiled in the parent');
        eval { PAX::StandaloneImage::_compile_jobs_parallel(Cov::SimaFake->new(parent => $$, die_silently_in_child => 1, parent_string => 1), \@jobs, undef) };
        is($@, '', 'non-reference fallback results are tolerated');
    }
    {
        # results that land after the scan but before workers are polled are picked up by the fallback
        local $ENV{PAX_JOBS} = 2;
        my $first = 1;
        local $main::WAITPID_HOOK = sub {
            return if !$first;
            $first = 0;
            wait_for_workers();
        };
        my $fake = Cov::SimaFake->new(parent => $$, delay => { '/p/a.pm' => 0.4, '/p/b.pm' => 0.4 });
        my @units = PAX::StandaloneImage::_compile_jobs_parallel($fake, [ @jobs[0, 1] ], undef);
        is_deeply([ map { $_->{path} } @units ], [ '/p/a.pm', '/p/b.pm' ], 'late results are read by the fallback');
        ok(!(grep { $_->{pid_kind} ne 'child' } @units), 'late results came from the workers');
    }
    {
        # one worker finishes, the other vanishes: the loaded result is kept, the missing one is rebuilt
        local $ENV{PAX_JOBS} = 2;
        my $fake = Cov::SimaFake->new(parent => $$, die_silently_for => '/p/b.pm', delay => { '/p/a.pm' => 0.1 });
        my @units = PAX::StandaloneImage::_compile_jobs_parallel($fake, [ @jobs[0, 1] ], undef);
        is_deeply([ map { $_->{pid_kind} } @units ], [ 'child', 'parent' ], 'only the vanished worker is rebuilt in the parent');
    }
    {
        # every worker exits between two polls while one result was just loaded
        local $ENV{PAX_JOBS} = 2;
        my $slept = 0;
        my $loaded_now = 0;
        local $main::WAITPID_HOOK = sub {
            return if $slept || !$loaded_now;
            $slept = 1;
            wait_for_workers();
        };
        my $fake = Cov::SimaFake->new(parent => $$, delay => { '/p/a.pm' => 0.1, '/p/b.pm' => 0.6 });
        my @units = PAX::StandaloneImage::_compile_jobs_parallel($fake, [ @jobs[0, 1] ], sub { $loaded_now = 1 });
        is_deeply([ map { $_->{path} } @units ], [ '/p/a.pm', '/p/b.pm' ], 'results are collected after all workers exited');
        ok($slept, 'the poll hook ran');
    }
    {
        local $ENV{PAX_JOBS} = 2;
        local $main::FAIL_FORK = 1;
        eval { PAX::StandaloneImage::_compile_jobs_parallel(Cov::SimaFake->new(parent => $$), \@jobs, undef) };
        like($@, qr/cannot fork compile worker/, 'fork failure dies');
    }
}

# _code_manifest
{
    my $dir = "$root/cm";
    write_file("$dir/bin/app.pl", "#!/usr/bin/perl\nuse strict;\nuse Mod::Main;\nprint 1;\n");
    write_file("$dir/lib/Mod/Main.pm", "package Mod::Main; use strict; sub m { return 1 }\n1;\n");
    write_file("$dir/lib/Mod/Other.pm", "package Mod::Other; use strict; sub o { return 1 }\n1;\n");
    write_file("$dir/src/tool.pl", "use strict; sub t { return 1 }\n1;\n");
    write_file("$dir/extra/Ext/Thing.pm", "package Ext::Thing; use strict; sub e { return 1 }\n1;\n");
    my $entry = "$dir/bin/app.pl";

    my @events;
    my @manifest = PAX::StandaloneImage::_code_manifest(
        $entry, ["$dir/lib"], ["$dir/src"],
        [
            { dir => "$dir/extra", files => [ "$dir/extra/Ext/Thing.pm", "$dir/lib/Mod/Main.pm" ] },
        ],
        sub { push @events, $_[0] },
    );
    my %by_path = map { $_->{source_path} => $_ } @manifest;
    is($by_path{$entry}{unit_kind}, 'entrypoint', 'entrypoint unit');
    is($by_path{"$dir/lib/Mod/Main.pm"}{unit_kind}, 'lib', 'lib unit');
    ok($by_path{"$dir/lib/Mod/Other.pm"}, 'second lib unit');
    is($by_path{"$dir/src/tool.pl"}{unit_kind}, 'source', 'source unit kind');
    like($by_path{"$dir/src/tool.pl"}{logical_path}, qr{\Asrc/src/tool}, 'source logical path');
    is($by_path{"$dir/extra/Ext/Thing.pm"}{unit_kind}, 'lib', 'app file set without kind defaults to lib');
    like($by_path{"$dir/extra/Ext/Thing.pm"}{logical_path}, qr{\Alib/extra/Ext/Thing}, 'app file set without prefix derives one');
    is((grep { $_->{source_path} eq "$dir/lib/Mod/Main.pm" } @manifest), 1, 'duplicate files compiled once');
    ok(length $by_path{$entry}{source_bytes}, 'entrypoint source bytes stored');
    is((grep { ($_->{unit_kind} // '') eq 'dependency' } @manifest), 0, 'no dependencies discovered');
    is($events[0]{task_id}, 'discover_code_units', 'discovery reported first');
    ok((grep { $_->{task_id} eq 'compile_dependency_units' && $_->{status} eq 'done' } @events), 'dependency stage finished');
    ok((grep { $_->{task_id} eq 'compile_application_units' && ($_->{label} // '') =~ /src:tool\.pl/ } @events), 'source label reported');
    ok((grep { $_->{task_id} eq 'compile_application_units' && ($_->{label} // '') =~ m{lib:Mod/Main\.pm} } @events), 'lib label reported');

    # application files without a progress callback, module names resolved through @INC, blank roots
    {
        local @INC = ("$dir/lib", @INC);
        my @quiet = PAX::StandaloneImage::_code_manifest($entry, ["$dir/lib"], [], [], undef);
        is(scalar(@quiet), 3, 'entrypoint plus two lib units without progress');
        my @blank = PAX::StandaloneImage::_code_manifest($entry, [''], [''], [], undef);
        is(scalar(grep { $_->{unit_kind} ne 'dependency' } @blank), 1, 'blank roots contribute no application units');
        my @undef_root = do { local $SIG{__WARN__} = sub { }; PAX::StandaloneImage::_code_manifest($entry, [undef], [], [], undef) };
        is(scalar(grep { $_->{unit_kind} ne 'dependency' } @undef_root), 1, 'undefined roots contribute no application units');
    }

    # units lacking kind or packaging metadata are tolerated by the dependency scan
    {
        no warnings 'redefine';
        my $real = \&PAX::CodeUnitCompiler::compile;
        local *PAX::CodeUnitCompiler::compile = sub {
            my ($self, %args) = @_;
            my $unit = $real->($self, %args);
            delete $unit->{unit_kind} if $args{kind} eq 'lib';
            delete $unit->{packaging} if $args{kind} eq 'entrypoint';
            return $unit;
        };
        my @odd = PAX::StandaloneImage::_code_manifest($entry, ["$dir/lib"], [], [], undef);
        is(scalar(@odd), 3, 'units without metadata still listed');
    }

    # no progress callback, no sets
    my @bare = PAX::StandaloneImage::_code_manifest($entry, [], [], undef, undef);
    is(scalar(grep { $_->{unit_kind} eq 'entrypoint' } @bare), 1, 'bare entrypoint');

    # dependencies are found through the entrypoint directory
    my $dir2 = "$root/cm2";
    write_file("$dir2/Dep/Helper.pm", "package Dep::Helper; use strict; use Dep::Chain; sub h { return 1 }\n1;\n");
    write_file("$dir2/Dep/Chain.pm", "package Dep::Chain; use strict; sub c { return 1 }\n1;\n");
    write_file("$dir2/Dep/Empty.pm", "package Dep::Empty; use strict;\n1;\n");
    my $depentry = write_file("$dir2/dep.pl", "use strict;\nuse Dep::Helper;\nuse Dep::Chain;\nuse Dep::Empty;\n1;\n");
    @events = ();
    my @with_deps = PAX::StandaloneImage::_code_manifest($depentry, [], [], [], sub { push @events, $_[0] });
    my @deps = grep { ($_->{unit_kind} // '') eq 'dependency' } @with_deps;
    is(scalar(@deps), 3, 'dependency units discovered transitively without duplicates');
    ok((grep { ($_->{label} // '') =~ /\(3 discovered/ } grep { $_->{task_id} eq 'compile_dependency_units' } @events), 'dependency progress counts');

    # an entrypoint that is a module found on @INC is remembered as seen
    {
        local @INC = ($dir2, @INC);
        my @mod = PAX::StandaloneImage::_code_manifest("$dir2/Dep/Helper.pm", [], [], [], undef);
        is((grep { ($_->{unit_kind} // '') eq 'dependency' && $_->{source_path} eq "$dir2/Dep/Helper.pm" } @mod), 0, 'entrypoint module not duplicated as dependency');
    }

    # entrypoints that fall back to source are not scanned for dependencies
    {
        no warnings 'redefine';
        my $real = \&PAX::CodeUnitCompiler::compile;
        local *PAX::CodeUnitCompiler::compile = sub {
            my ($self, %args) = @_;
            my $unit = $real->($self, %args);
            $unit->{packaging} = 'source_payload_fallback' if $args{kind} eq 'entrypoint';
            return $unit;
        };
        my $fb_entry = write_file("$dir2/fb.pl", "use strict;\nuse Dep::Helper;\n1;\n");
        my @fb = PAX::StandaloneImage::_code_manifest($fb_entry, [], [], [], undef);
        is(scalar(@fb), 1, 'source fallback entrypoint skips dependency scan');
    }

    # sibling script warning is wired into the entrypoint step
    write_file("$dir/bin/real", "#!/usr/bin/perl\nprint 1;\n");
    my $alias = write_file("$dir/bin/alias", "#!/usr/bin/perl\nuse FindBin qw(\$Bin);\nuse File::Spec;\nexec \$^X, File::Spec->catfile(\$Bin, 'real'), \@ARGV;\n");
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    PAX::StandaloneImage::_code_manifest($alias, [], [], [], undef);
    is(scalar(@warnings), 1, 'manifest build warns about an unpackaged sibling script');
}

done_testing;
