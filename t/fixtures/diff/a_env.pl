# Differential fixture: EnvAudit and EnvLoader helpers, including .env function calls.
use strict; no warnings; local $SIG{__WARN__} = sub { };
use File::Temp qw(tempdir);
use Developer::Dashboard::EnvAudit;
use Developer::Dashboard::EnvLoader;
my $home = tempdir(CLEANUP => 1);
my $A = 'Developer::Dashboard::EnvAudit'; my $L = 'Developer::Dashboard::EnvLoader';
sub clean { my $e = shift; $e =~ s/ at .*? line \d+\.?\n?//g; $e =~ s/\(eval \d+\)/(eval N)/g; $e =~ s/\Q$home\E/HOME/g; return $e }
sub dump_v { my $v = shift; return 'undef' if !defined $v; if (ref $v eq 'HASH') { return '{' . join(',', map { "$_=>" . dump_v($v->{$_}) } sort keys %$v) . '}' } if (ref $v eq 'ARRAY') { return '[' . join(',', map { dump_v($_) } @$v) . ']' } my $s = "$v"; $s =~ s/\Q$home\E/HOME/g; return "'$s'"; }
sub t { my ($l, $c) = @_; my @r = eval { $c->() }; my $e = $@; $e =~ s/\Q$home\E/HOME/g; $e =~ s/\(eval \d+\)/(eval N)/g; $e =~ s/\n/\\n/g; my $o = join('|', map { dump_v($_) } @r); $o =~ s/\n/\\n/g; print "$l=$o", ($e ne '' ? " ERR[$e]" : ''), "\n"; }
delete $ENV{DEVELOPER_DASHBOARD_ENV_AUDIT};
$A->clear;
# audit
t('key-none', sub { $A->key('X') });
t('key-undef', sub { $A->key(undef) });
t('key-empty', sub { $A->key('') });
t('keys-none', sub { $A->keys });
t('record-nokey', sub { $A->record(undef, 'v', 'f') });
t('record-emptykey', sub { $A->record('', 'v', 'f') });
t('record-nofile', sub { $A->record('K', 'v', undef) });
t('record-emptyfile', sub { $A->record('K', 'v', '') });
t('record', sub { $A->record('K1', 'v1', '/f/one') });
t('record2', sub { $A->record('K2', undef, '/f/two') });
t('record3', sub { $A->record('K1', 'v1b', '/f/three') });
t('key', sub { $A->key('K1') });
t('key-undef-value', sub { $A->key('K2') });
t('key-missing', sub { $A->key('K3') });
t('key-zero', sub { $A->key('0') });
t('keys', sub { $A->keys });
t('key-class-extra', sub { $A->key('K1', 'extra') });
t('key-copy-isolated', sub { my $c = $A->key('K1'); $c->{envfile} = 'mutated'; $A->key('K1') });
t('audit_copy', sub { $A->_audit_copy });
print "env-audit=", (defined $ENV{DEVELOPER_DASHBOARD_ENV_AUDIT} ? $ENV{DEVELOPER_DASHBOARD_ENV_AUDIT} : 'undef'), "\n";
# reload from env
{ %Developer::Dashboard::EnvAudit::AUDIT = (); local $ENV{K1} = 'envval'; local $ENV{K2} = 'e2';
  t('key-reloaded', sub { $A->key('K1') });
  t('keys-reloaded', sub { $A->keys }); }
{ %Developer::Dashboard::EnvAudit::AUDIT = (); local $ENV{DEVELOPER_DASHBOARD_ENV_AUDIT} = '[1]'; t('load-bad-shape', sub { $A->key('K1') }); }
{ %Developer::Dashboard::EnvAudit::AUDIT = (); local $ENV{DEVELOPER_DASHBOARD_ENV_AUDIT} = '{bad'; t('load-bad-json', sub { $A->keys }); }
{ %Developer::Dashboard::EnvAudit::AUDIT = (); local $ENV{DEVELOPER_DASHBOARD_ENV_AUDIT} = ''; t('load-empty', sub { $A->keys }); }
{ %Developer::Dashboard::EnvAudit::AUDIT = (); local $ENV{DEVELOPER_DASHBOARD_ENV_AUDIT} = '{"ZK":{"envfile":"/z"},"NK":{}}'; local $ENV{ZK} = 'zv'; t('load-json', sub { $A->keys }); t('key-json', sub { $A->key('ZK') }); }
$A->clear; t('after-clear', sub { $A->keys }); print "env-audit-after-clear=", (exists $ENV{DEVELOPER_DASHBOARD_ENV_AUDIT} ? 'exists' : 'gone'), "\n";
# env functions
package My::EnvFn { sub ok { return 'fn-ok' } sub undef_val { return undef } sub empty { return '' } sub dies { die "inner failure\n" } sub dies_nonl { die "inner" } sub list { return (1, 2, 3) } sub zero { return 0 } sub args { return scalar @_ } }
sub My::EnvFn::Deep::f { return 'deep' }
sub toplevel_fn { return 'top' }
for my $f ('My::EnvFn::ok()', 'My::EnvFn::ok', 'My::EnvFn::undef_val()', 'My::EnvFn::empty()', 'My::EnvFn::dies()', 'My::EnvFn::dies_nonl()', 'My::EnvFn::list()', 'My::EnvFn::zero()', 'My::EnvFn::args()', 'My::EnvFn::Deep::f()', 'main::toplevel_fn()', 'toplevel_fn()', 'My::EnvFn::missing()', 'Nope::nope()', 'bad name()', 'a-b()', '::x()', 'x::()', '1x()', 'X::1y()', '()', '', undef, 'My::EnvFn::ok()()', 'My::EnvFn::ok ()', " My::EnvFn::ok()", 'CORE::GLOBAL::die()', 'My\\::x()', 'My::EnvFn::ok();system(1)') {
  t('call[' . (defined $f ? $f : 'undef') . ']', sub { $L->_call_env_function(function => $f, file => '/e/.env', line_no => 7) });
}
t('call-nofile', sub { $L->_call_env_function(function => 'Nope::x()') });
t('call-noargs', sub { $L->_call_env_function() });
t('call-fail-nofile', sub { $L->_call_env_function(function => 'My::EnvFn::dies()') });
# expansion
$ENV{PAXV} = 'pv'; $ENV{PAXE} = '';
for my $v ('plain', '$PAXV', '${PAXV}', '${PAXE:-dflt}', '${PAXMISSING:-d$PAXV}', '${PAXMISSING}', '${My::EnvFn::ok():-x}', '${My::EnvFn::empty():-fallback}', '${My::EnvFn::undef_val():-$PAXV}', '${My::EnvFn::dies():-x}', '${Nope::x():-x}', '~', '~/x', 'a~b', '$HOME/x', '${PAXV:-a:-b}', '${PAXMISSING:-a:-b}', '${', '$', '$$', '${}', '${:-d}', '${ PAXV }', '${PAXV}${PAXV}', '\\$PAXV', '"$PAXV"') {
  t('expand[' . $v . ']', sub { local $ENV{HOME} = '/h'; $L->_expand_env_value(value => $v, file => '/e/.env', line_no => 3) });
}
for my $e ('PAXV', 'PAXE:-d', 'My::EnvFn::ok()', 'My::EnvFn::ok():-d', 'My::EnvFn::dies()', 'Zz::q():-dd$PAXV', '', ':-d', 'PAXMISSING:-') {
  t('braced[' . $e . ']', sub { $L->_expand_braced_env_expression(expression => $e, file => '/e/.env', line_no => 4) });
}
for my $n ('PAXV', 'PAXE', 'PAXNOPE', '', undef, '0') { t('lookup[' . (defined $n ? $n : 'undef') . ']', sub { $L->_lookup_env_symbol($n) }); }
# files
mkdir "$home/d"; 
open my $f, '>', "$home/d/.env"; print {$f} "# c\nA1=one\nA2=\${My::EnvFn::ok():-x}\nA3=\$A1-\${A1}\n\n// c2\n/* block\nB=ignored\n*/\nA4=\${NOPE:-dflt}\n"; close $f;
open $f, '>', "$home/d/.env.pl"; print {$f} "\$ENV{P1} = 'plval'; \$ENV{A1} = 'overridden'; 1;\n"; close $f;
open $f, '>', "$home/d/bad.env"; print {$f} "A=1\nbad line\n"; close $f;
open $f, '>', "$home/d/badkey.env"; print {$f} "1A=1\n"; close $f;
open $f, '>', "$home/d/fn.env"; print {$f} "FNV=\${My::EnvFn::dies():-x}\n"; close $f;
open $f, '>', "$home/d/unterm.env"; print {$f} "A=1\n/* never ends\n"; close $f;
open $f, '>', "$home/d/missing_fn.env"; print {$f} "M=\${Nope::q():-x}\n"; close $f;
$A->clear;
t('load_files', sub { $L->load_files(files => [ "$home/d/.env", "$home/d/.env.pl", "$home/d/.env", undef, '', "$home/none" ]) });
t('env-after', sub { map { "$_=" . ($ENV{$_} // 'undef') } qw(A1 A2 A3 A4 P1 B) });
t('audit-after', sub { my $k = $A->keys; { map { $_ => $k->{$_}{envfile} } sort grep { /^(A\d|P1)$/ } keys %$k } });
for my $b (qw(bad badkey fn unterm missing_fn)) { t("load[$b]", sub { $L->load_files(files => ["$home/d/$b.env"]) }); }
t('into_hash', sub { my $r = $L->load_files_into_hash(files => [ "$home/d/.env" ], base_env => { BASEK => 'b', A1 => 'old' }); { files => $r->{files}, env => $r->{env} } });
t('into_hash-noenv', sub { my $r = $L->load_files_into_hash(files => []); $r->{files} });
t('candidates', sub { $L->_env_file_candidates('/r') });
t('strip', sub { my $b = 0; my $r = $L->_strip_env_comments(line => 'K=v # c', file => 'f', line_no => 1, in_block_comment => \$b); "$r;$b" });
t('strip2', sub { my $b = 0; my @r = map { $L->_strip_env_comments(line => $_, file => 'f', line_no => 1, in_block_comment => \$b) . ";$b" } ('K=v /* a */ x', '/* open', 'inside', 'close */ K2=v2', '// whole', '  # whole', 'K=a#b', 'K=a//b', 'K=http://x'); @r });
