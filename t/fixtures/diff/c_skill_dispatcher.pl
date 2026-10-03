# Differential fixture: SkillDispatcher lookup/config/route helpers over a layered fake skill tree.
use strict; use warnings;
use Cwd qw(getcwd);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Spec;
use JSON::XS ();
use Developer::Dashboard::SkillDispatcher;
use Developer::Dashboard::PathRegistry;
my $home = tempdir(CLEANUP => 1);
sub put { my ($rel, $text, $mode) = @_; my $p = "$home/$rel"; (my $d = $p) =~ s{/[^/]+\z}{}; make_path($d); open my $o, '>', $p or die "$p: $!"; print {$o} $text; close $o; chmod($mode, $p) if $mode; }
sub clean { my $m = shift; $m =~ s/\Q$home\E/HOME/g; $m =~ s/ at (?:PAX::StandaloneRuntime op \w+|\S+) line \d+\.?//g; $m =~ s/\n/ /g; return $m; }
sub show { my ($v, $d) = @_; $d //= 0; return 'undef' if !defined $v; if (ref $v eq 'HASH') { return '{' . join(',', map { "$_=" . show($v->{$_}, $d + 1) } sort keys %$v) . '}' } if (ref $v eq 'ARRAY') { return '[' . join(',', map { show($_, $d + 1) } @$v) . ']' } if (ref $v) { return ref $v } return clean($v); }
sub try { my ($l, $c) = @_; my @r = eval { $c->() }; print "$l: ", ($@ ? 'died ' . clean($@) : join(' | ', map { show($_) } @r)), "\n"; }
my $sk = '.developer-dashboard/skills';
my $SEP = ':' . ('-' x 80) . ':';
put("$sk/alpha/cli/hello", "#!/bin/sh\necho hi\n", 0755);
put("$sk/alpha/cli/run.pl", "print 1;\n", 0755);
put("$sk/alpha/cli/hello.d/10-pre", "#!/bin/sh\ntrue\n", 0755);
put("$sk/alpha/cli/hello.d/20-post", "#!/bin/sh\ntrue\n", 0755);
put("$sk/alpha/cli/hello.d/notes.txt", "plain\n", 0644);
put("$sk/alpha/cli/sub.cmd.pl", "print 2;\n", 0755);
put("$sk/alpha/dashboards/index", "TITLE: Alpha Index\n$SEP\nBOOKMARK: index\n$SEP\nHTML: <p>alpha</p>\n");
put("$sk/alpha/dashboards/page1", "TITLE: Page One\n$SEP\nBOOKMARK: page1\n$SEP\nHTML: <p>one</p>\n");
put("$sk/alpha/dashboards/routes.json", "{}\n");
put("$sk/alpha/dashboards/nav/b.tt", "<b>nav b</b>\n");
put("$sk/alpha/dashboards/nav/a.tt", "<b>nav a</b>\n");
put("$sk/alpha/config/config.json", '{"collectors":[{"name":"c1","command":"echo 1"},{"name":"c2","command":"echo 2"}],"providers":[{"id":"p1","x":1}],"deep":{"a":1,"b":{"c":2}},"list":[1,2],"scalar":"s"}');
put("$sk/alpha/skills/inner/cli/deep", "#!/bin/sh\necho deep\n", 0755);
put("$sk/alpha/skills/inner/dashboards/index", "TITLE: Inner\n$SEP\nBOOKMARK: index\n$SEP\nHTML: <p>inner</p>\n");
put("$sk/beta/cli/off", "#!/bin/sh\necho off\n", 0755);
put("$sk/beta/.disabled", "");
put("$sk/gamma/cli/g", "#!/bin/sh\necho g\n", 0755);
put("$sk/gamma/config/config.json", "not json");
put("$sk/delta/config/config.json", "[1,2]");
put("$sk/delta/cli/d", "x", 0644);
put("proj/.developer-dashboard/skills/alpha/cli/hello", "#!/bin/sh\necho proj\n", 0755);
put("proj/.developer-dashboard/skills/alpha/cli/hello.d/15-proj", "#!/bin/sh\ntrue\n", 0755);
put("proj/.developer-dashboard/skills/alpha/dashboards/page2", "TITLE: Page Two\n$SEP\nBOOKMARK: page2\n$SEP\nHTML: <p>two</p>\n");
put("proj/.developer-dashboard/skills/alpha/dashboards/nav/c.tt", "<b>nav c</b>\n");
put("proj/.developer-dashboard/skills/alpha/config/config.json", '{"collectors":[{"name":"c2","command":"echo two"},{"name":"c3","command":"echo 3"}],"providers":[{"id":"p1","x":2},{"id":"p2"}],"deep":{"b":{"d":4}},"scalar":"t"}');
for my $cwd ($home, "$home/proj") {
    chdir $cwd or die;
    print "== cwd ", ($cwd eq $home ? 'home' : 'proj'), "\n";
    my $paths = Developer::Dashboard::PathRegistry->new(home => $home, workspace_roots => [], project_roots => []);
    my $d = Developer::Dashboard::SkillDispatcher->new(paths => $paths);
    print "layers alpha: ", clean(join(',', $d->_skill_layers('alpha'))), "\n";
    try('get_skill_path alpha', sub { $d->get_skill_path('alpha') });
    try('get_skill_path none', sub { $d->get_skill_path('') });
    try('get_skill_path missing', sub { $d->get_skill_path('nope') });
    try('get_skill_path disabled', sub { $d->get_skill_path('beta') });
    for my $s ('alpha', 'beta', 'gamma', 'delta', 'nope', '', 'alpha/inner') {
        try("get_skill_config '$s'", sub { $d->get_skill_config($s) });
        try("config_fragment '$s'", sub { $d->config_fragment($s) });
        try("lookup_roots '$s'", sub { $d->_skill_lookup_roots($s) });
        try("lookup_roots incl '$s'", sub { $d->_skill_lookup_roots($s, include_disabled => 1) });
        try("bookmark_entries '$s'", sub { $d->_skill_bookmark_entries($s) });
        try("skill_nav_pages '$s'", sub { my $p = $d->skill_nav_pages($s); [map { $_->{id} . ':' . $_->{title} } @$p] });
    }
    try('all_skill_nav_pages', sub { my $p = $d->all_skill_nav_pages; [map { $_->{id} } @$p] });
    for my $c (['alpha', 'hello'], ['alpha', 'run'], ['alpha', 'sub.cmd'], ['alpha', 'inner.deep'], ['alpha', 'deep'], ['alpha', ''], ['', 'hello'], ['nope', 'hello'], ['beta', 'off'], ['gamma', 'g'], ['delta', 'd'], ['alpha', 'a..b']) {
        try("command_path @$c", sub { $d->command_path(@$c) });
        try("command_spec @$c", sub { my $s = $d->command_spec(@$c); $s ? { %$s, skill_layers => scalar @{$s->{skill_layers}} } : undef });
        try("hook_paths @$c", sub { $d->command_hook_paths(@$c) });
    }
    try('merge arrays', sub { $d->_merge_array_items_by_identity([{ n => 'a', v => 1 }, 'x', { v => 2 }, { n => '' }], [{ n => 'a', v => 9 }, { n => 'b' }, 'x', undef, { n => 'b', v => 3 }], 'n') });
    try('merge arrays bad', sub { $d->_merge_array_items_by_identity(undef, 'str', 'n') });
    try('merge arrays one', sub { $d->_merge_array_items_by_identity([{ n => 1 }], undef, 'n') });
    try('merge hashes', sub { $d->_merge_skill_hashes({ a => 1, h => { x => 1, y => { z => 1 } }, collectors => [{ name => 'a', v => 1 }], providers => [{ id => 'i', v => 1 }], l => [1] }, { a => 2, h => { y => { w => 2 } }, collectors => [{ name => 'a', v => 2 }, { name => 'b' }], providers => [{ id => 'i', v => 2 }, { id => 'j' }], l => [2], n => undef }) });
    try('merge hashes undef', sub { $d->_merge_skill_hashes(undef, undef) });
    try('merge hashes type clash', sub { $d->_merge_skill_hashes({ h => { a => 1 }, c => [1] }, { h => [1], c => { z => 1 } }) });
    for my $r (['alpha', ''], ['alpha', 'page1'], ['alpha', 'page2'], ['alpha', 'nope'], ['alpha', 'bookmarks'], ['alpha', 'bookmarks/page1'], ['alpha', 'bookmarks/zzz'], ['alpha', '/page1/'], ['alpha', 'nav/a.tt'], ['alpha/inner', ''], ['gamma', ''], ['beta', 'x'], ['nope', 'x'], ['', 'x'], ['alpha', undef]) {
        try("route_response $r->[0] " . ($r->[1] // 'undef'), sub { my $x = $d->route_response(skill_name => $r->[0], route => $r->[1]); [$x->[0], $x->[1], ($x->[1] =~ m{json} ? show(JSON::XS::decode_json($x->[2])) : $x->[2])] });
    }
    try('route_response no args', sub { my $x = $d->route_response(); $x });
}
chdir '/';
