# Differential fixture: Runtime::Result API with many inputs.
use strict; use warnings;
use Developer::Dashboard::Runtime::Result;
my $R = 'Developer::Dashboard::Runtime::Result';
sub show { my ($l, @v) = @_; print "$l=", join('|', map { my $x = $_; !defined $x ? 'undef' : ref $x eq 'HASH' ? '{' . join(',', map { my $k = $_; "$k=>" . (defined $x->{$k} ? (ref $x->{$k} ? 'ref' : $x->{$k}) : 'undef') } sort keys %$x) . '}' : $x } @v), "\n"; }
sub t { my ($l, $c) = @_; my @r = eval { $c->() }; my $e = $@; $e =~ s/ at .*? line \d+\.?\n?//; show($l, @r); print "  err=", ($e ne '' ? $e : 'none'), "\n"; }
delete @ENV{qw(RESULT RESULT_FILE LAST_RESULT LAST_RESULT_FILE DEVELOPER_DASHBOARD_RESULT_INLINE_MAX DEVELOPER_DASHBOARD_COMMAND)};
t('current-empty', sub { $R->can('current')->() });
t('names-empty', sub { scalar(() = $R->can('names')->()) });
t('report-empty', sub { $R->can('report')->() });
t('last_name-empty', sub { $R->can('last_name')->() });
t('last_entry-empty', sub { $R->can('last_entry')->() });
t('has-undef', sub { Developer::Dashboard::Runtime::Result::has(undef) });
t('has-empty', sub { Developer::Dashboard::Runtime::Result::has('') });
t('entry-undef', sub { Developer::Dashboard::Runtime::Result::entry(undef) });
t('entry-empty', sub { Developer::Dashboard::Runtime::Result::entry('') });
t('stdout-missing', sub { Developer::Dashboard::Runtime::Result::stdout('x') });
t('exit-missing', sub { Developer::Dashboard::Runtime::Result::exit_code('x') });
t('last_result-none', sub { Developer::Dashboard::Runtime::Result::last_result() });
t('last_result-class', sub { $R->last_result });
t('set-nonhash', sub { Developer::Dashboard::Runtime::Result::set_current([]) });
t('set-last-nonhash', sub { Developer::Dashboard::Runtime::Result::set_last_result('x') });
t('set-last-class-nonhash', sub { $R->set_last_result('x') });
t('set-empty', sub { Developer::Dashboard::Runtime::Result::set_current({}) });
t('set-last-empty', sub { Developer::Dashboard::Runtime::Result::set_last_result({}) });
t('set', sub { Developer::Dashboard::Runtime::Result::set_current({ '10-b' => { stdout => "out b\n", stderr => '', exit_code => 0 }, '05-a' => { stdout => 'a', stderr => "[[STOP]]", exit_code => 3 }, '20-c' => 'scalar', '30-d' => { stdout => undef, stderr => undef } }) });
print "env=", (defined $ENV{RESULT} ? 'set' : 'unset'), " file=", (defined $ENV{RESULT_FILE} ? 'set' : 'unset'), "\n";
t('names', sub { Developer::Dashboard::Runtime::Result::names() });
t('has-a', sub { Developer::Dashboard::Runtime::Result::has('05-a') });
t('has-zz', sub { Developer::Dashboard::Runtime::Result::has('zz') });
t('entry-a', sub { Developer::Dashboard::Runtime::Result::entry('05-a') });
t('entry-c', sub { Developer::Dashboard::Runtime::Result::entry('20-c') });
t('stdout-b', sub { Developer::Dashboard::Runtime::Result::stdout('10-b') });
t('stdout-c', sub { Developer::Dashboard::Runtime::Result::stdout('20-c') });
t('stdout-d', sub { Developer::Dashboard::Runtime::Result::stdout('30-d') });
t('stderr-a', sub { Developer::Dashboard::Runtime::Result::stderr('05-a') });
t('stderr-d', sub { Developer::Dashboard::Runtime::Result::stderr('30-d') });
t('stderr-undef', sub { Developer::Dashboard::Runtime::Result::stderr(undef) });
t('exit-a', sub { Developer::Dashboard::Runtime::Result::exit_code('05-a') });
t('exit-b', sub { Developer::Dashboard::Runtime::Result::exit_code('10-b') });
t('exit-c', sub { Developer::Dashboard::Runtime::Result::exit_code('20-c') });
t('exit-d', sub { Developer::Dashboard::Runtime::Result::exit_code('30-d') });
t('last_name', sub { Developer::Dashboard::Runtime::Result::last_name() });
t('last_entry', sub { Developer::Dashboard::Runtime::Result::last_entry() });
$ENV{RESULT} = '[1]'; t('bad-array', sub { Developer::Dashboard::Runtime::Result::current() });
$ENV{RESULT} = '{bad'; t('bad-json', sub { eval { Developer::Dashboard::Runtime::Result::current() }; 'caught=' . ($@ ? 1 : 0) });
$ENV{LAST_RESULT} = '"x"'; t('bad-last', sub { Developer::Dashboard::Runtime::Result::last_result() });
$ENV{LAST_RESULT} = '{}'; t('empty-last', sub { Developer::Dashboard::Runtime::Result::last_result() });
delete $ENV{LAST_RESULT};
t('set-last', sub { Developer::Dashboard::Runtime::Result::set_last_result({ STDERR => "x [[STOP]] y", name => 'n' }) });
t('last', sub { $R->last_result });
t('last-class-set', sub { $R->set_last_result({ k => 1 }) });
t('last2', sub { Developer::Dashboard::Runtime::Result::last_result() });
for my $v (undef, '', 'plain', "a [[STOP]]", "[[stop]]", { STDERR => '[[STOP]]' }, { stderr => '[[STOP]]' }, { STDERR => '', stderr => '[[STOP]]' }, { STDERR => undef, stderr => 'ok' }, {}, [], 0) {
  t('stop', sub { Developer::Dashboard::Runtime::Result::stop_requested($v) });
  t('stop-class', sub { $R->stop_requested($v) });
}
t('clear-last', sub { Developer::Dashboard::Runtime::Result::clear_last_result() });
t('clear-last-class', sub { $R->clear_last_result() });
print "last-after=", (defined $ENV{LAST_RESULT} ? 'set' : 'unset'), "\n";
# restore sane state and report
Developer::Dashboard::Runtime::Result::set_current({ '10-b' => { exit_code => 0 }, '05-a' => { exit_code => 3 }, '07-n' => { stdout => 'x' }, '08-u' => { exit_code => undef } });
for my $args ([], [command => 'cmd'], [command => ''], [command => undef], [bogus => 1]) {
  t('report', sub { my $r = Developer::Dashboard::Runtime::Result::report(@$args); utf8::decode($r) if defined $r; length($r) . ':' . join('/', map { sprintf '%vx', $_ } split /\n/, $r) });
  t('report-class', sub { my $r = $R->report(@$args); utf8::decode($r); join('/', map { sprintf '%vx', $_ } split /\n/, $r) });
}
t('report-line1', sub { (split /\n/, Developer::Dashboard::Runtime::Result::report(command => 'zz'))[1] });
t('report-default', sub { (split /\n/, Developer::Dashboard::Runtime::Result::report())[1] });
{ local $0 = '/a/b/run'; t('report-run', sub { (split /\n/, Developer::Dashboard::Runtime::Result::report())[1] }); }
{ local $0 = '/a/b/mycmd'; t('report-mycmd', sub { (split /\n/, Developer::Dashboard::Runtime::Result::report())[1] }); }
{ local $0 = '/a/b/mycmd/'; t('report-trail', sub { (split /\n/, Developer::Dashboard::Runtime::Result::report())[1] }); }
{ local $0 = 'run'; t('report-barerun', sub { (split /\n/, Developer::Dashboard::Runtime::Result::report())[1] }); }
{ local $0 = '/'; t('report-root', sub { (split /\n/, Developer::Dashboard::Runtime::Result::report())[1] }); }
{ local $0 = ''; t('report-empty0', sub { (split /\n/, Developer::Dashboard::Runtime::Result::report())[1] }); }
{ local $ENV{DEVELOPER_DASHBOARD_COMMAND} = 'envcmd';
  for my $z ('', '/', 'C:\\', 'run', '/x/run', '/x/y.pl') { local $0 = $z; t("report-env-[$z]", sub { (split /\n/, Developer::Dashboard::Runtime::Result::report())[1] }); } }
# overflow into file
{ local $ENV{DEVELOPER_DASHBOARD_RESULT_INLINE_MAX} = 10;
  t('set-file', sub { Developer::Dashboard::Runtime::Result::set_current({ a => { stdout => 'x' x 50, exit_code => 0 } }) });
  print "env=", (defined $ENV{RESULT} ? 'set' : 'unset'), " file=", (defined $ENV{RESULT_FILE} ? 'set' : 'unset'), "\n";
  t('cur-file', sub { length Developer::Dashboard::Runtime::Result::stdout('a') });
  t('set-file2', sub { Developer::Dashboard::Runtime::Result::set_current({ b => { stdout => 'y' x 80, exit_code => 0 } }) });
  t('cur-file2', sub { Developer::Dashboard::Runtime::Result::names() });
  t('set-inline-again', sub { Developer::Dashboard::Runtime::Result::set_current({ b => 1 }) });
  print "env=", (defined $ENV{RESULT} ? 'set' : 'unset'), " file=", (defined $ENV{RESULT_FILE} ? 'set' : 'unset'), "\n";
  t('set-arg-override', sub { Developer::Dashboard::Runtime::Result::set_current({ b => 1 }, max_inline_bytes => 100000) });
  t('set-arg-zero', sub { Developer::Dashboard::Runtime::Result::set_current({ b => 1 }, max_inline_bytes => 0) });
  t('set-arg-bad', sub { Developer::Dashboard::Runtime::Result::set_current({ b => 1 }, max_inline_bytes => 'x') });
  t('last-file', sub { Developer::Dashboard::Runtime::Result::set_last_result({ big => 'z' x 40 }) });
  print "lenv=", (defined $ENV{LAST_RESULT} ? 'set' : 'unset'), " lfile=", (defined $ENV{LAST_RESULT_FILE} ? 'set' : 'unset'), "\n";
  t('last-file-read', sub { Developer::Dashboard::Runtime::Result::last_result() });
  t('clear', sub { Developer::Dashboard::Runtime::Result::clear_current() });
  t('clear-last2', sub { Developer::Dashboard::Runtime::Result::clear_last_result() });
}
{ local $ENV{DEVELOPER_DASHBOARD_RESULT_INLINE_MAX} = 'abc'; t('set-bad-env', sub { Developer::Dashboard::Runtime::Result::set_current({ q => 1 }) }); }
$ENV{RESULT_FILE} = '/nonexistent/zz'; delete $ENV{RESULT}; t('missing-file', sub { Developer::Dashboard::Runtime::Result::current() });
t('current_json', sub { Developer::Dashboard::Runtime::Result::_current_json() });
delete $ENV{RESULT_FILE};
t('current_json2', sub { Developer::Dashboard::Runtime::Result::_current_json() });
t('channel_json', sub { Developer::Dashboard::Runtime::Result::_channel_json('NOPE_A', 'NOPE_B') });
{ local $ENV{NOPE_A} = 'val'; t('channel_json3', sub { Developer::Dashboard::Runtime::Result::_channel_json('NOPE_A', 'NOPE_B') }); }
t('open_channel', sub { my ($fh, $p) = Developer::Dashboard::Runtime::Result::_open_channel_file(); print {$fh} "hi"; ref($fh) . ':' . ($p =~ m{^/(?:dev|proc)/} ? 'fdpath' : 'other') });
t('cmdname', sub { Developer::Dashboard::Runtime::Result::_command_name() });
