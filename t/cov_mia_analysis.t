use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON::PP ();
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::StandaloneAnalysis;

=pod

=head1 NAME

t/cov_mia_analysis.t - coverage tests for PAX::StandaloneAnalysis

=head1 DESCRIPTION

Drives dependency analysis, native-artifact discovery and the helper routines of
PAX::StandaloneAnalysis in-process with fabricated sources, code-unit records,
and stubbed capture/tier-1 stages.

=head1 WHY IT EXISTS

Covers every statement, branch and condition of the analyzer, including its
failure diagnostics, without running real captures or compilers.

=cut

my $tmp = tempdir('pax-cov-mia-analysis-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# write_file($path, $text)
# Writes a fixture file, creating parent directories.
# Input: path and text. Output: path.
sub write_file {
    my ($path, $text) = @_;
    my ($dir) = $path =~ m{\A(.*)/[^/]+\z};
    make_path($dir) if defined $dir && !-d $dir;
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print {$fh} $text;
    close $fh;
    return $path;
}

my $an = PAX::StandaloneAnalysis->new;
isa_ok($an, 'PAX::StandaloneAnalysis');

# ---------------------------------------------------------------- dependencies
{
    my $lib = "$tmp/inc";
    write_file("$lib/Zed/Pure.pm", "package Zed::Pure;\nuse Zed::Child;\n1;\n");
    write_file("$lib/Zed/Child.pm", "package Zed::Child;\nuse strict;\n1;\n__END__\nuse Not::Seen;\n");
    write_file("$lib/Zed/Xs.pm", "package Zed::Xs;\nrequire XSLoader;\n1;\n");
    write_file("$lib/Zed/Cycle.pm", "package Zed::Cycle;\nuse Zed::Cycle2;\n1;\n");
    write_file("$lib/Zed/Cycle2.pm", "package Zed::Cycle2;\nuse Zed::Cycle;\nuse Zed::Child;\n1;\n");

    my $app_lib = "$tmp/app/lib";
    write_file("$app_lib/App/Own.pm", "package App::Own;\nuse Zed::Pure;\nuse Missing::Thing;\n1;\n");
    write_file("$app_lib/App/Dep.pm", "package App::Dep;\n1;\n");
    my $script = write_file("$tmp/app/bin/tool.pl", "use strict;\nuse App::Own;\nuse App::Dep;\nuse Zed::Xs;\nuse Zed::Cycle;\n=pod\n\nuse In::Pod;\n\n=cut\n");
    my $cpanfile = write_file("$tmp/cpanfile", "requires 'Zed::Pure';\nrecommends \"Declared::Only\";\n# comment\n");

    local @INC = ($lib, @INC);
    eval { $an->dependencies };
    like($@, qr/entrypoint required/, 'dependencies requires an entrypoint');

    my $empty = $an->dependencies(entrypoint => $script);
    is_deeply($empty->{items}, [], 'no code units and no cpanfiles gives no items');

    my $res = $an->dependencies(
        entrypoint => $script,
        code_units => [
            { source_path => $script, unit_kind => 'script' },
            { source_path => "$app_lib/App/Own.pm", unit_kind => 'lib', packaging => 'pcu' },
            { source_path => "$app_lib/App/Dep.pm", unit_kind => 'dependency', packaging => 'hybrid' },
            { source_path => "$tmp/app/bin/tool.pl" },
            { source_path => $script, unit_kind => 'lib' },
        ],
        cpanfiles => [$cpanfile],
    );
    my %by = map { $_->{module} => $_ } @{ $res->{items} };
    my %lib_by_path = ($app_lib => 1);
    is($by{'App::Own'}{class}, 'packaged_app', 'lib unit classified packaged_app');
    is($by{'App::Own'}{provider}, 'application', 'packaged_app provider');
    is($by{'App::Own'}{packaging}, 'pcu', 'packaging passed through');
    is($by{'App::Dep'}{class}, 'compiled_dependency', 'dependency unit classified compiled');
    is($by{'App::Dep'}{provider}, 'pax_compiler', 'compiled dependency provider');
    is($by{'Zed::Pure'}{class}, 'bundled_pure_perl', 'plain installed module is bundled pure perl');
    is($by{'Zed::Pure'}{source_path}, "$lib/Zed/Pure.pm", 'bundled module path recorded');
    ok(!$by{'Zed::Pure'}{xs}, 'pure module not xs');
    is(scalar @{ $by{'Zed::Pure'}{declared_in_cpanfile} }, 1, 'cpanfile declaration attached');
    is($by{'Zed::Xs'}{class}, 'bundled_xs', 'XSLoader module is bundled xs');
    ok($by{'Zed::Xs'}{xs}, 'xs flag true');
    is($by{'Missing::Thing'}{class}, 'missing', 'unresolvable module is missing');
    is($by{'Missing::Thing'}{provider}, 'unresolved', 'missing provider');
    is($by{'Declared::Only'}{class}, 'missing', 'cpanfile-only module is missing');
    ok(!$by{'Declared::Only'}{used_in_code}, 'cpanfile-only module not used in code');
    ok($by{'Zed::Child'}{used_in_code}, 'transitive dependency marked used');
    ok(!exists $by{'In::Pod'} && !exists $by{'Not::Seen'}, 'POD and __END__ text ignored');
    is($res->{summary}{packaged_app}, 1, 'summary packaged_app');
    is($res->{summary}{compiled_dependency}, 1, 'summary compiled_dependency');
    is($res->{summary}{missing}, 2, 'summary missing');
    is($res->{summary}{bundled_xs}, 3, 'summary bundled_xs (Zed::Xs plus the XSLoader and DynaLoader core modules it pulls in)');
}

# ------------------------------------------------------------ source helpers
is(PAX::StandaloneAnalysis::_analysis_source(undef), '', '_analysis_source tolerates undef');
is(PAX::StandaloneAnalysis::_analysis_source("a\n=pod\nx\n=cut\nb\n__DATA__\nc\n"), "a\nb\n", '_analysis_source strips POD and data');
is_deeply([ PAX::StandaloneAnalysis::_source_module_refs("use A::B;\nuse A::B;\nrequire C::D;\nuse strict;\nrequire x::y;\nuse X;\nrequire Z;\n") ],
    [ 'A::B', 'C::D' ], '_source_module_refs dedupes and skips pragmas and one-letter names');
ok(!PAX::StandaloneAnalysis::_is_dependency_candidate(undef), 'undef is not a candidate');
ok(!PAX::StandaloneAnalysis::_is_dependency_candidate('X'), 'one-letter name is not a candidate');
ok(!PAX::StandaloneAnalysis::_is_dependency_candidate('strict'), 'pragma is not a candidate');
ok(PAX::StandaloneAnalysis::_is_dependency_candidate('Foo::Bar'), 'normal module is a candidate');
is(PAX::StandaloneAnalysis::_slurp("$tmp/absent"), '', '_slurp returns empty for a missing file');
is(PAX::StandaloneAnalysis::_slurp($tmp), '', '_slurp returns empty when readline fails on a directory');

# closure: undefined/empty seeds are dropped, unresolved paths skipped, repeated paths scanned once
{
    my $shared = write_file("$tmp/closure/Shared.pm", "use Child::One;\n");
    my %mods;
    PAX::StandaloneAnalysis::_expand_dependency_closure(
        \%mods, [ undef, '', 'A::One', 'A::Two', 'A::One', 'Nowhere::Mod' ],
        { 'A::One' => { source_path => $shared }, 'A::Two' => { source_path => $shared } },
    );
    ok($mods{'Child::One'}{used_in_code}, 'closure follows children of packaged modules');
    ok(!exists $mods{'Nowhere::Mod'}, 'unresolvable seeds add nothing');
    $mods{'Child::One'}{used_in_code} = 0;
    PAX::StandaloneAnalysis::_expand_dependency_closure(\%mods, ['A::One'], { 'A::One' => { source_path => $shared } });
    is($mods{'Child::One'}{used_in_code}, 0, 'closure keeps an existing used_in_code value');
}

# ------------------------------------------------------- module name / locate
{
    my $inc = "$tmp/names/inc";
    make_path("$inc/A", "$tmp/names/other/lib/B", "$tmp/names/plain");
    write_file("$inc/A/B.pm", '1;');
    write_file("$inc/.pm", '1;');
    write_file("$tmp/names/other/lib/B/C.pm", '1;');
    write_file("$tmp/names/other/lib/.pm", '1;');
    write_file("$tmp/names/plain/Solo.pm", '1;');
    write_file("$tmp/names/plain/.pm", '1;');
    local @INC = (sub { return }, "$tmp/names/missing-inc", "$tmp/names/other/lib/B", $inc);
    is(PAX::StandaloneAnalysis::_module_name_from_path(undef), undef, 'no path -> undef');
    is(PAX::StandaloneAnalysis::_module_name_from_path("$inc/A/B.txt"), undef, 'non-.pm path -> undef');
    is(PAX::StandaloneAnalysis::_module_name_from_path("$inc/A/B.pm"), 'A::B', 'name derived relative to @INC');
    is(PAX::StandaloneAnalysis::_module_name_from_path("$tmp/names/other/lib/B/C.pm"), 'C', 'inc match wins over lib heuristic');
    local @INC = ($inc);
    is(PAX::StandaloneAnalysis::_module_name_from_path("$tmp/names/other/lib/B/C.pm"), 'B::C', 'falls back to the lib/ heuristic');
    is(PAX::StandaloneAnalysis::_module_name_from_path("$tmp/names/plain/Solo.pm"), 'Solo', 'falls back to the basename');
    is(PAX::StandaloneAnalysis::_module_name_from_path("$inc/.pm"), '', 'empty relative name in @INC falls through to basename logic');
    is(PAX::StandaloneAnalysis::_module_name_from_path("$tmp/names/other/lib/.pm"), '', 'empty lib tail falls through to basename');
    is(PAX::StandaloneAnalysis::_module_name_from_path("$tmp/names/gone/lib/X/Y.pm"), 'X::Y', 'unresolvable path uses the raw path');
    is(PAX::StandaloneAnalysis::_module_name_from_path("$tmp/names/gone/Y.pm"), 'Y', 'unresolvable path without lib dir uses basename');

    local @INC = (sub { return }, $inc);
    is(PAX::StandaloneAnalysis::_locate_module('A::B'), "$inc/A/B.pm", '_locate_module finds a module');
    is(PAX::StandaloneAnalysis::_locate_module('A::Nope'), undef, '_locate_module returns nothing for a miss');
}

# -------------------------------------------------------------- XS detection
{
    write_file("$tmp/xs/Dyn.pm", "package Dyn; require DynaLoader;\n1;\n");
    write_file("$tmp/xs/Sib.pm", "package Sib;\n1;\n");
    write_file("$tmp/xs/Sib.bundle", "x");
    write_file("$tmp/xs/Clean.pm", "package Clean;\n1;\n");
    ok(PAX::StandaloneAnalysis::_module_uses_xs("$tmp/xs/Dyn.pm"), 'DynaLoader reference means xs');
    ok(PAX::StandaloneAnalysis::_module_uses_xs("$tmp/xs/Sib.pm"), 'sibling shared object means xs');
    ok(!PAX::StandaloneAnalysis::_module_uses_xs("$tmp/xs/Clean.pm"), 'plain module is not xs');
}

# ------------------------------------------------------ native probe heuristics
my $leaf_src = "sub add {\n    my (\$a, \$b) = \@_;\n    return \$a + \$b;\n}\n";
my $loop_src = "sub total {\n    my (\$n) = \@_;\n    my \$sum = 0;\n    for (my \$i = 1; \$i <= \$n; \$i++) { \$sum += \$i; }\n    return \$sum;\n}\n";
ok(PAX::StandaloneAnalysis::_source_has_native_candidate($leaf_src), 'leaf shape is a native candidate');
ok(PAX::StandaloneAnalysis::_source_has_native_candidate($loop_src), 'loop shape is a native candidate');
ok(!PAX::StandaloneAnalysis::_source_has_native_candidate("sub x { return 1; }\n"), 'plain source is not a candidate');
ok(!PAX::StandaloneAnalysis::_source_has_native_candidate("sub broken {\n return \$a + \$b;\n"), 'unterminated sub body is skipped');
ok(!PAX::StandaloneAnalysis::_source_has_native_candidate("sub wrong { my (\$a) = \@_; return \$a - \$b; }\n"), 'candidate-looking regex without a real shape is rejected');

{
    my $good = write_file("$tmp/probe/good.pl", $leaf_src);
    my $dull = write_file("$tmp/probe/dull.pl", "print 1;\n");
    my $blank = write_file("$tmp/probe/blank.pl", '');
    ok(PAX::StandaloneAnalysis::_native_probe_worthwhile([ undef, "$tmp/probe/none.pl", $blank, $dull, $good ]), 'worthwhile when any file has a candidate');
    ok(!PAX::StandaloneAnalysis::_native_probe_worthwhile([ $dull, $blank, "$tmp/probe/none.pl", '' ]), 'not worthwhile when nothing qualifies');
    {
        no warnings 'redefine';
        local *PAX::StandaloneAnalysis::_slurp = sub { return undef };
        ok(!PAX::StandaloneAnalysis::_native_probe_worthwhile([$good]), 'an unreadable (undef) source is skipped');
    }
    is_deeply([ PAX::StandaloneAnalysis::_native_probe_paths($good, [ { source_path => $dull }, { source_path => $good }, {}, { source_path => $dull } ]) ],
        [ $good, $dull ], '_native_probe_paths dedupes and drops undef');
}

# ------------------------------------------------- static native units / artifacts
# unit_json(%record)
# Encodes a code-unit record to JSON bytes as the compiler stores them.
# Input: record fields. Output: JSON string.
sub unit_json {
    return JSON::PP::encode_json({@_});
}
{
    my $shape = { kind => 'i64_binary_leaf', op => 'add' };
    my $units = PAX::StandaloneAnalysis::_static_native_units_from_code_units([
        'not a hash',
        { },
        { bytes => '' },
        { bytes => 'not json {' },
        { bytes => '[1,2]' },
        { bytes => unit_json(
            package => 'Pkg',
            subs => [ 'scalar', { name => 'noshape' }, { name => 'badshape', native_shape => 'x' }, { name => 'emptyshape', native_shape => {} },
                      { full_name => 'Full::Name', native_shape => $shape }, { name => 'leaf', native_shape => $shape }, { native_shape => $shape } ],
            compiled_subs => [ { name => 'viaCompiled', native_shape => $shape } ],
        ) },
        { bytes => unit_json(subs => [ { name => 'mainsub', native_shape => $shape } ]) },
    ]);
    is_deeply([ map { $_->{region_name} } @$units ], [ 'Full::Name', 'Pkg::leaf', 'Pkg::viaCompiled', 'main::mainsub' ],
        'static units collected from subs and compiled_subs with qualified names');
    is($units->[0]{region_id}, 'static-region-0001', 'region ids are sequential');
    is($units->[3]{deopt}{safepoint}, 'static-region-0004:entry', 'safepoint named after the region');
    is(scalar @{ $units->[0]{guards} }, 3, 'default guards attached');
    is_deeply(PAX::StandaloneAnalysis::_default_runtime_epochs(), { package_symbols => 1, method_resolution => 1, loaded_modules => 1 }, 'default epochs');
}

{
    no warnings 'redefine';
    my @compiled;
    local *PAX::Tier1::compile = sub {
        my ($self, $unit) = @_;
        push @compiled, $unit->{region_name};
        return { status => 'ok', entry_kind => 'native_i64_leaf', executable_path => '/x/exe', library_path => '/x/lib', reason => 'r', tier2_artifact => 't2' }
            if $unit->{region_name} eq 'ready';
        return { status => 'ok', entry_kind => 'native_i64_loop' } if $unit->{region_name} eq 'noexe';
        return { status => 'fallback', reason => 'nope' };
    };
    my $res = PAX::StandaloneAnalysis::_native_artifacts_from_units(
        [ { region_id => 1, region_name => 'ready', guards => [ 'g' ], deopt => { s => 1 } },
          { region_id => 2, region_name => 'noexe' },
          { region_id => 3, region_name => 'other' } ],
        { e => 1 },
    );
    is_deeply($res->{summary}, { total => 3, native_ready => 1, fallback_only => 2 }, 'artifact summary counts native vs fallback');
    is($res->{items}[0]{executable_path}, '/x/exe', 'native item carries the executable path');
    is($res->{items}[0]{library_path}, '/x/lib', 'native item carries the library path');
    is_deeply($res->{items}[1]{guards}, [], 'guards default to empty');
    is_deeply($res->{items}[1]{deopt}, {}, 'deopt defaults to empty');
    ok(!exists $res->{items}[1]{executable_path}, 'unready item has no executable path');
    is_deeply($res->{runtime_epochs}, { e => 1 }, 'epochs passed through');

    # native_artifacts: static units short-circuit capture
    my $cu = [ { bytes => unit_json(package => 'P', subs => [ { name => 's', native_shape => { kind => 'k' } } ]) } ];
    my $static = $an->native_artifacts(entrypoint => 'x.pl', code_units => $cu);
    is($static->{summary}{total}, 1, 'native_artifacts uses static units when available');
    is_deeply($static->{runtime_epochs}, PAX::StandaloneAnalysis::_default_runtime_epochs(), 'static artifacts use default epochs');

    eval { $an->native_artifacts };
    like($@, qr/entrypoint required/, 'native_artifacts requires an entrypoint');

    # no worthwhile probe
    my $dull = write_file("$tmp/na/dull.pl", "print 1;\n");
    my $none = $an->native_artifacts(entrypoint => $dull);
    is_deeply($none, { items => [], summary => { native_ready => 0, fallback_only => 0, total => 0 }, runtime_epochs => undef }, 'no candidate -> empty artifacts');

    my $good = write_file("$tmp/na/good.pl", $leaf_src);
    my $cap_mode;
    my $cap_result;
    local *PAX::Capture::new = sub { my ($c, %a) = @_; $cap_mode = $a{mode}; return bless {}, $c };
    local *PAX::Capture::capture = sub { die "boom capture\n" if !ref $cap_result; return $cap_result };

    $cap_result = undef;
    my $failed = $an->native_artifacts(entrypoint => $good);
    is($cap_mode, 'live', 'live capture requested');
    is($failed->{diagnostics}[0]{code}, 'native_capture_failed', 'capture exception reported as diagnostic');
    like($failed->{diagnostics}[0]{message}, qr/boom capture/, 'diagnostic carries the error');

    local *PAX::Capture::capture = sub { return undef };
    my $undef_cap = $an->native_artifacts(entrypoint => $good);
    is($undef_cap->{diagnostics}[0]{code}, 'native_capture_failed', 'undefined capture reported as failure');
    local *PAX::Capture::capture = sub { return $cap_result };

    $cap_result = { status => 'error' };
    my $bad_status = $an->native_artifacts(entrypoint => $good);
    is_deeply($bad_status, { items => [], summary => { native_ready => 0, fallback_only => 0, total => 0 } }, 'non-ok capture status yields empty artifacts');

    $cap_result = { status => 'ok' };
    my $stage = 'manifest';
    local *PAX::Manifest::new = sub { my ($c, %a) = @_; die "manifest boom\n" if $stage eq 'manifest'; return bless {}, $c };
    local *PAX::Manifest::to_hash = sub { return { runtime_epochs => { m => 1 } } };
    local *PAX::RegionSelector::new = sub { return bless {}, shift };
    local *PAX::RegionSelector::select = sub { return { selected => ['r'] } };
    local *PAX::HIR::new = sub { return bless {}, shift };
    local *PAX::HIR::lower_all = sub { return ['hir'] };
    local *PAX::GuardedSSA::new = sub { return bless {}, shift };
    local *PAX::GuardedSSA::build_all = sub { return [ { region_id => 9, region_name => 'ready' } ] };
    my $analysis_failed = $an->native_artifacts(entrypoint => $good);
    is($analysis_failed->{diagnostics}[0]{code}, 'native_analysis_failed', 'pipeline exception reported as diagnostic');
    like($analysis_failed->{diagnostics}[0]{message}, qr/manifest boom/, 'diagnostic carries pipeline error');

    $stage = 'ok';
    my $full = $an->native_artifacts(entrypoint => $good);
    is($full->{summary}{native_ready}, 1, 'full pipeline produces artifacts');
    is_deeply($full->{runtime_epochs}, { m => 1 }, 'epochs come from the manifest');
}

done_testing;
