# Differential fixture: UpdateManager (update scripts, collector stop/restart order) and ActionRunner (payloads, trust, builtin actions).
use strict; use warnings;
use File::Temp qw(tempdir);
use Capture::Tiny ();
use File::Path qw(make_path);
use Developer::Dashboard::UpdateManager;
use Developer::Dashboard::ActionRunner;
use Developer::Dashboard::PathRegistry;
use Developer::Dashboard::FileRegistry;
use Developer::Dashboard::PageDocument;
my $home = tempdir(CLEANUP => 1);
sub clean { my $m = shift; $m =~ s/\Q$home\E/HOME/g; $m =~ s/ at (?:PAX::StandaloneRuntime op \w+|\S+) line \d+\.?//g; $m =~ s/\n/ /g; return $m; }
sub show { my ($v) = @_; return 'undef' if !defined $v; if (ref $v eq 'HASH') { return '{' . join(',', map { "$_=" . show($v->{$_}) } sort keys %$v) . '}' } if (ref $v eq 'ARRAY') { return '[' . join(',', map { show($_) } @$v) . ']' } return clean($v); }
sub try { my ($l, $c) = @_; my @r = eval { $c->() }; print "$l: ", ($@ ? 'died ' . clean($@) : join(' | ', map { show($_) } @r)), "\n"; }
my $paths = Developer::Dashboard::PathRegistry->new(home => $home, workspace_roots => [], project_roots => []);
my $files = Developer::Dashboard::FileRegistry->new(paths => $paths);
{
    package FakeRunner;
    sub new { bless { log => [], running => [@{ $_[1] }] }, $_[0] }
    sub running_loops { push @{ $_[0]{log} }, 'running_loops'; return map { { name => $_ } } @{ $_[0]{running} } }
    sub stop_loop { push @{ $_[0]{log} }, "stop:$_[1]"; die "boom\n" if $_[1] eq 'bad'; return 1 }
    sub start_loop { push @{ $_[0]{log} }, "start:$_[1]{name}"; die "boom\n" if $_[1]{name} eq 'bad'; return 1 }
    package FakeConfig;
    sub new { bless {}, shift }
    sub collectors { return [ { name => 'c1' }, 'junk', { name => 'bad' }, { name => 'c2' }, { name => 'other' } ] }
}
my $work = "$home/work"; make_path("$work/updates");
sub put { my ($p, $text, $mode) = @_; open my $o, '>', $p or die; print {$o} $text; close $o; chmod $mode, $p if $mode; }
put("$work/updates/01-first.sh", "#!/bin/sh\necho first-out\necho first-err >&2\nexit 3\n", 0755);
put("$work/updates/02-second.pl", "print qq{second\\n}; exit 0;\n", 0644);
put("$work/updates/03-plain", "#!/bin/sh\necho plain\n", 0755);
put("$work/updates/04-notrun", "data\n", 0644);
make_path("$work/updates/subdir");
$| = 1;
my $um_make = sub { my $r = FakeRunner->new([@_]); my $m = Developer::Dashboard::UpdateManager->new(config => FakeConfig->new, files => $files, paths => $paths, runner => $r); return ($m, $r); };
try('new missing config', sub { Developer::Dashboard::UpdateManager->new(files => $files, paths => $paths, runner => 1) });
try('new missing files', sub { Developer::Dashboard::UpdateManager->new(config => 1, paths => $paths, runner => 1) });
try('new missing paths', sub { Developer::Dashboard::UpdateManager->new(config => 1, files => $files, runner => 1) });
try('new missing runner', sub { Developer::Dashboard::UpdateManager->new(config => 1, files => $files, paths => $paths) });
chdir $home or die;
{
    my ($m, $r) = $um_make->('c1', 'bad', 'c2');
    try('updates_dir', sub { $m->updates_dir });
    try('run without updates dir', sub { my $res = $m->run; scalar(@$res) . ' log=' . join(',', @{ $r->{log} }) });
}
chdir $work or die;
for my $p (undef, '', 'a.pl', 'a.PL', 'a.sh', 'a.bash', 'a.ps1', 'a.cmd', 'a.bat', 'a.txt', "$work/updates/03-plain", "$work/updates/04-notrun", "$work/updates/nonexistent") {
    my ($m) = $um_make->();
    try('supported ' . (defined $p ? clean($p) : 'undef'), sub { $m->_is_supported_update_script($p) });
}
{
    my ($m, $r) = $um_make->('c1', 'bad', 'c2');
    try('running', sub { $m->_running_collectors });
    try('stop', sub { $m->_stop_collectors('c1', 'bad', 'c2'); join ',', @{ $r->{log} } });
    $r->{log} = [];
    try('restart none', sub { $m->_restart_collectors(); join ',', @{ $r->{log} } });
    try('restart some', sub { $m->_restart_collectors('c2', 'bad', 'nothere', 'c1'); join ',', @{ $r->{log} } });
}
{
    my ($m, $r) = $um_make->('c1', 'bad', 'c2');
    my $res;
    my ($out, $err) = Capture::Tiny::capture(sub { local $? = 7; $res = eval { $m->run }; print STDERR "run died: ", clean($@), "\n" if $@; print STDERR "status after run: $?\n"; });
    print "results: ", join(' ; ', map { "$_->{file} exit=$_->{exit_code} out=" . join('~', split /\n/, clean($_->{output})) } @{ $res || [] }), "\n";
    print "log: ", join(',', @{ $r->{log} }), "\n";
    $err = clean($err); print "stderr: $err\n";
    $out =~ s/\Q$home\E/HOME/g; $out =~ s/>> \S*perl\S* [^\n]*02-second\.pl/>> PERL 02-second.pl/;
    print "captured: ", join('~', split /\n/, $out), "\n";
}
chdir $home;
my $ar = Developer::Dashboard::ActionRunner->new(files => $files, paths => $paths);
try('new no files', sub { Developer::Dashboard::ActionRunner->new(paths => $paths) });
try('new no paths', sub { Developer::Dashboard::ActionRunner->new(files => $files) });
my $page = Developer::Dashboard::PageDocument->from_hash({ id => 'ap', title => 'AP', layout => { body => 'b' }, state => { k => 'v', n => [1, 2] } });
my $perm = Developer::Dashboard::PageDocument->from_hash({ id => 'perm', title => 'P', layout => { body => 'b' }, permissions => { allow_untrusted_actions => 1, trusted_actions => ['ok'] } });
my $perm2 = Developer::Dashboard::PageDocument->from_hash({ id => 'perm2', title => 'P', layout => { body => 'b' }, permissions => { allow_untrusted_actions => 1 } });
for my $c (
    ['safe', $page, { id => 'x', safe => 1 }, 'weird'], ['saved', $page, { id => 'x' }, 'saved'], ['provider', $page, { id => 'x' }, 'provider'],
    ['transient none', $page, { id => 'x' }, 'transient'], ['no source', $page, { id => 'x' }, undef], ['perm allowed', $perm, { id => 'ok' }, 'transient'],
    ['perm denied', $perm, { id => 'no' }, 'transient'], ['perm2', $perm2, { id => 'ok' }, 'transient'],
) {
    my ($l, $pg, $act, $src) = @$c;
    try("trusted $l", sub { $ar->_is_action_trusted(page => $pg, action => $act, source => $src) });
}
for my $a ({ builtin => 'page.source' }, { id => 'page.state' }, { builtin => 'paths.list' }, { id => 'nope' }, {}) {
    try('builtin ' . join(',', %$a), sub { my $r = $ar->_run_builtin_action(action => $a, page => $page); $r });
}
try('run_page_action no page', sub { $ar->run_page_action(action => { id => 'page.source' }) });
try('run_page_action no action', sub { $ar->run_page_action(page => $page) });
try('run_page_action non-hash', sub { $ar->run_page_action(page => $page, action => 'x') });
try('run_page_action builtin', sub { $ar->run_page_action(page => $page, action => { id => 'page.source' }) });
try('run_page_action kind', sub { $ar->run_page_action(page => $page, action => { kind => 'weird', id => 'w' }) });
try('run_page_action untrusted cmd', sub { $ar->run_page_action(page => $page, action => { kind => 'command', id => 'c', command => 'echo hi' }, source => 'transient') });
try('run_page_action trusted cmd', sub { $ar->run_page_action(page => $page, action => { kind => 'command', id => 'c', command => 'echo hi-from-cmd', timeout_ms => 5000 }, source => 'saved') });
try('run_page_action safe cmd env', sub { $ar->run_page_action(page => $page, action => { kind => 'command', id => 'c', safe => 1, command => 'echo "v=$AR_V"; exit 4', env => { AR_V => 'zz' } }, source => 'transient') });
try('run_page_action bad cwd', sub { $ar->run_page_action(page => $page, action => { kind => 'command', id => 'c', command => 'true', cwd => '/nonexistent-dir-xyz' }, source => 'saved') });
try('run_page_action cwd accessor', sub { $ar->run_page_action(page => $page, action => { kind => 'command', id => 'c', command => 'pwd', cwd => 'home' }, source => 'saved') });
my $tokens = {};
for my $src (undef, 'saved', 'transient') {
    my $l = $src // 'undef';
    try("encode $l", sub { my $t = $ar->encode_action_payload(page => $page, action => { id => 'page.source' }, source => $src); $tokens->{$l} = $t; my $p = $ar->decode_action_payload($t); +{ %$p } });
}
try('encode no page', sub { $ar->encode_action_payload(action => { id => 'a' }) });
try('encode no action', sub { $ar->encode_action_payload(page => $page) });
try('decode garbage', sub { $ar->decode_action_payload('!!!notatoken') });
try('decode empty', sub { $ar->decode_action_payload('') });
try('decode non-hash', sub { require Developer::Dashboard::Codec; $ar->decode_action_payload(Developer::Dashboard::Codec::encode_payload('[1,2]')) });
for my $l (sort keys %$tokens) {
    try("run_encoded $l", sub { $ar->run_encoded_action(token => $tokens->{$l}) });
}
require Developer::Dashboard::Codec; require Developer::Dashboard::JSON;
my $enc = sub { Developer::Dashboard::Codec::encode_payload(Developer::Dashboard::JSON::json_encode($_[0])) };
my $psrc = $page->canonical_instruction;
try('run_encoded command action', sub { $ar->run_encoded_action(token => $enc->({ page_source => $psrc, action => { kind => 'command', id => 'c', command => 'echo no', safe => 1 }, source => 'saved' })) });
try('run_encoded builtin kind', sub { $ar->run_encoded_action(token => $enc->({ page_source => $psrc, action => { kind => 'builtin', id => 'page.state' }, source => 'saved' })) });
try('run_encoded claims saved, untrusted', sub { $ar->run_encoded_action(token => $enc->({ page_source => $psrc, action => { kind => 'weird', id => 'w' }, source => 'saved' })) });
try('run_encoded no action', sub { $ar->run_encoded_action(token => $enc->({ page_source => $psrc })) });
try('run_encoded action not hash', sub { $ar->run_encoded_action(token => $enc->({ page_source => $psrc, action => 'str' })) });
try('run_encoded no token', sub { $ar->run_encoded_action() });
try('run_encoded params', sub { $ar->run_encoded_action(token => $tokens->{saved}, params => { a => 1 }) });
try('fork_process', sub { my $pid = $ar->_fork_process; if (defined $pid && $pid == 0) { exit 0 } waitpid($pid, 0); defined $pid ? 'forked' : 'undef' });
chdir '/';
