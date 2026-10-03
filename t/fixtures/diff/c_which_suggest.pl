# Differential fixture: CLI::Which command/hook location and CLI::Suggest typo guidance over a layered fake tree.
use strict; use warnings;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Developer::Dashboard::CLI::Which;
use Developer::Dashboard::CLI::Suggest;
use Developer::Dashboard::PathRegistry;
my $home = tempdir(CLEANUP => 1);
$ENV{HOME} = $home;
delete $ENV{DEVELOPER_DASHBOARD_ENTRYPOINT};
sub put { my ($rel, $text, $mode) = @_; my $p = "$home/$rel"; (my $d = $p) =~ s{/[^/]+\z}{}; make_path($d); open my $o, '>', $p or die "$p: $!"; print {$o} $text; close $o; chmod($mode, $p) if $mode; }
sub clean { my $m = shift; $m =~ s/\Q$home\E/HOME/g; $m =~ s/ at (?:PAX::StandaloneRuntime op \w+|\S+) line \d+\.?//g; $m =~ s/\n/ /g; return $m; }
sub show { my ($v) = @_; return 'undef' if !defined $v; if (ref $v eq 'HASH') { return '{' . join(',', map { "$_=" . show($v->{$_}) } sort keys %$v) . '}' } if (ref $v eq 'ARRAY') { return '[' . join(',', map { show($_) } @$v) . ']' } return clean($v); }
sub try { my ($l, $c) = @_; my @r = eval { $c->() }; print "$l: ", ($@ ? 'died ' . clean($@) : join(' | ', map { show($_) } @r)), "\n"; }
my $dd = '.developer-dashboard';
put("$dd/cli/mycmd", "#!/bin/sh\necho my\n", 0755);
put("$dd/cli/mycmd.d/10-a", "#!/bin/sh\ntrue\n", 0755);
put("$dd/cli/mycmd.d/20-b.pl", "print 1;\n", 0755);
put("$dd/cli/mycmd.d/skip.txt", "x", 0644);
put("$dd/cli/mycmd.d/run", "#!/bin/sh\n", 0755);
put("$dd/cli/dirrun/run", "#!/bin/sh\necho r\n", 0755);
put("$dd/cli/dirrun/10-hook", "#!/bin/sh\ntrue\n", 0755);
put("$dd/cli/dirbash/run.sh", "#!/bin/sh\necho r\n", 0755);
put("$dd/cli/dirnone/readme", "x", 0644);
put("$dd/cli/script.pl", "print 3;\n", 0755);
put("$dd/cli/typo-target", "#!/bin/sh\n", 0755);
put("$dd/cli/dd", "#!/bin/sh\n", 0755);
put("$dd/cli/notexec", "x", 0644);
put("$dd/hooks/00-gate", "#!/bin/sh\ntrue\n", 0755);
put("$dd/hooks/05-gate.pl", "print 1;\n", 0755);
put("$dd/hooks/run", "#!/bin/sh\n", 0755);
put("$dd/hooks/readme", "x", 0644);
put("$dd/skills/sk/cli/go", "#!/bin/sh\necho go\n", 0755);
put("$dd/skills/sk/cli/go.d/10-h", "#!/bin/sh\ntrue\n", 0755);
put("$dd/skills/sk/cli/__init__", "#!/bin/sh\necho init\n", 0755);
put("$dd/skills/sk/cli/other.sh", "#!/bin/sh\n", 0755);
put("$dd/skills/sk/skills/nest/cli/deep", "#!/bin/sh\n", 0755);
put("$dd/skills/off/cli/x", "#!/bin/sh\n", 0755);
put("$dd/skills/off/.disabled", "");
put("proj/$dd/cli/mycmd", "#!/bin/sh\necho proj\n", 0755);
put("proj/$dd/cli/mycmd.d/15-p", "#!/bin/sh\ntrue\n", 0755);
put("proj/$dd/cli/projonly", "#!/bin/sh\n", 0755);
put("proj/$dd/hooks/01-proj-gate", "#!/bin/sh\ntrue\n", 0755);
for my $cwd ($home, "$home/proj") {
    chdir $cwd or die;
    print "== cwd ", ($cwd eq $home ? 'home' : 'proj'), "\n";
    my $W = 'Developer::Dashboard::CLI::Which';
    print "usage: ", $W->can('_usage')->();
    try('entry command', sub { $W->can('_dashboard_entry_command')->() });
    { local $ENV{DEVELOPER_DASHBOARD_ENTRYPOINT} = '/usr/bin/dd-x'; try('entry command env', sub { $W->can('_dashboard_entry_command')->() }); }
    my $paths = Developer::Dashboard::PathRegistry->new(home => $home, workspace_roots => [], project_roots => []);
    for my $d ('dirrun', 'dirbash', 'dirnone', '', "$home/nonexistent") {
        try("resolve_directory_runner '" . clean($d) . "'", sub { $W->can('_resolve_directory_runner')->($d eq '' || $d =~ m{/} ? $d : "$home/$dd/cli/$d") });
    }
    for my $t ('mycmd', 'dirrun', 'dirbash', 'dirnone', 'script', 'script.pl', 'projonly', 'notexec', 'dd', 'nosuch', 'sk.go', 'sk.other', 'sk.nest.deep', 'sk.', '.go', 'sk.nope', 'off.x', 'version', 'help', '') {
        try("locate '$t'", sub { $W->can('_locate_target')->(paths => $paths, target => $t) });
    }
    for my $a ([], ['mycmd'], ['mycmd', 'extra'], ['nosuch'], ['sk.go'], ['--noedit', 'dirrun'], ['--bogus']) {
        my $out = '';
        { open my $fh, '>', \$out or die; my $old = select $fh; try("which @$a", sub { $W->can('run_which_command')->(command => 'which', args => [@$a]) }); select $old; }
        $out =~ s/\Q$home\E/HOME/g; $out =~ s/\n/ | /g; print "run_which [@$a]: $out\n";
    }
    try('run_which wrong command', sub { $W->can('run_which_command')->(command => 'other', args => []) });
    try('run_which no command', sub { $W->can('run_which_command')->(args => []) });
    try('run_which bad args', sub { $W->can('run_which_command')->(command => 'which', args => 'x') });
    my $S = Developer::Dashboard::CLI::Suggest->new(paths => $paths);
    my @top = $S->top_level_candidates;
    print "top_level_candidates count>10: ", (@top > 10 ? 'yes' : 'no'), "; custom: ", join(',', grep { /^(?:mycmd|dirrun|dirbash|dirnone|script|projonly|typo-target|notexec|dd)$/ } @top), "\n";
    print "top_level sample: ", join(',', @top[0 .. 9]), "\n";
    for my $q ('mycmd', 'mycm', 'myc', 'dcoekr', 'versoin', 'scrpt', 'typo', 'typo-targt', 'help', 'x', 'zzzzzzzzzzzz', '', 'MYCMD', 'my-cmd') {
        try("top_level_suggestions '$q'", sub { $S->top_level_suggestions($q) });
        try("unknown_command_message '$q'", sub { $S->unknown_command_message($q) });
    }
    try('skill_commands all', sub { $S->skill_commands });
    for my $sk ('sk', 'sk.nest', 'off', 'nope', '0') {
        try("skill_commands '$sk'", sub { $S->skill_commands($sk) });
    }
    for my $c (['go'], ['gp', 'sk'], ['deep', 'sk.nest'], ['sk.gp'], ['zzzzzzzzzz', 'sk'], ['', 'sk'], [''], ['go', 'off'], ['x', 'nope']) {
        try("skill_command_suggestions @$c", sub { $S->skill_command_suggestions(@$c) });
    }
    for my $c (['sk', 'gp'], ['sk', 'go'], ['off', 'x'], ['nope', 'go'], ['sk', 'zzzzzzzzzzzz'], ['nosuchskill', 'sk.go'], ['sk', '']) {
        try("unknown_skill_command_message @$c", sub { $S->unknown_skill_command_message(@$c) });
    }
    my $SC = 'Developer::Dashboard::CLI::Suggest';
    try('normalize', sub { map { $SC->can('_normalize_token')->($_) } ('Ab-C_d 9', '', undef, '!!!') });
    try('logical', sub { map { $SC->can('_logical_command_name')->($_) } ('a.pl', 'b.SH', 'c.txt', 'd.d', '', undef, 'e.bash', 'f.java', 'g.ps1') });
    try('levenshtein', sub { map { $SC->can('_levenshtein_distance')->(@$_) } (['kitten', 'sitting'], ['', 'abc'], ['abc', ''], ['same', 'same']) });
    try('score', sub { map { $SC->can('_candidate_score')->(@$_) // 'undef' } (['abc', 'abc'], ['ab', 'abcd'], ['abd', 'abc'], ['xyzxyz', 'ab'], ['dockr', 'docker']) });
    try('rank', sub { $S->_rank_candidates('doc', [qw(docker doctor dock docs docx doc doc dcr zzz), undef, '']) });
    try('rank empty', sub { $S->_rank_candidates('', ['a']) });
    try('rank undef', sub { $S->_rank_candidates(undef, ['a']) });
}
chdir '/';
