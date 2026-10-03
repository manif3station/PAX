# Differential fixture: PageRuntime private helpers and stream handle, called directly.
use strict; no warnings; local $SIG{__WARN__} = sub { };
use Developer::Dashboard::PageRuntime;
my $C = 'Developer::Dashboard::PageRuntime';
sub clean { my $e = shift; $e =~ s/ at .*? line \d+\.?\n?//g; $e =~ s/\(eval \d+\)/(eval N)/g; $e =~ s/Sandpit::\d+::\d+::\d+/Sandpit::N/g; return $e }
sub t { my ($l, $c) = @_; my @r = eval { $c->() }; my $e = clean($@); print "$l=", join('|', map { defined $_ ? $_ : 'undef' } @r), ($e ne '' ? " ERR[$e]" : ''), "\n"; }
my $rt = $C->new(paths => undef, aliases => {});
# value text / legacy quoting
for my $v (undef, 'str', 5, [], {}, [1, 'a', undef], { b => 1, a => [2, "x'y"] }, \'sref', sub { 1 }) {
  t('value_text', sub { $rt->_runtime_value_text($v) });
}
for my $v (undef, 0, -1, 1.5, '1.', '.5', '-', "a\\b", "it's", "a\nb", '007', '1e5', ' 1', [undef], { k => undef }) {
  t('legacy_value', sub { Developer::Dashboard::PageRuntime::_runtime_legacy_value($v) });
}
for my $s ('', "a'b", 'a\\b', "\\'", "'") { t('legacy_quote', sub { Developer::Dashboard::PageRuntime::_runtime_legacy_quote($s) }); }
for my $s ('', 'plain', 'a.b', 'a*b+c?', '^$|()[]{}\\', 'sp ace', 'x-y_z') { t('quote_pat', sub { $rt->_quote_process_pattern_literal($s) }); }
for my $e (undef, '', "__DD_AJAX_STREAM_DISCONNECTED__\n", 'Broken Pipe', 'client disconnected', 'Connection reset by peer', 'stream closed', 'connection aborted', 'write failed', 'print on closed handle', 'closed handle', 'other failure', "x\nbroken pipe\ny", 0, '0') {
  t('disc', sub { $rt->_looks_like_stream_disconnect_error($e) });
}
t('noop', sub { Developer::Dashboard::PageRuntime::_noop_writer('x', 'y') });
t('noop-none', sub { scalar Developer::Dashboard::PageRuntime::_noop_writer() });
t('noop-list', sub { my @a = Developer::Dashboard::PageRuntime::_noop_writer(); scalar @a });
# temp files
{
  my @made;
  for my $args ([ prefix => 'pfx-', suffix => '.txt', content => "hello\n" ], [ content => '' ], [], [ content => undef, suffix => '.json' ]) {
    t('temp', sub {
      my $p = Developer::Dashboard::PageRuntime::_saved_ajax_temp_file(@$args);
      push @made, $p;
      my ($base) = $p =~ m{([^/]+)$};
      $base =~ s/[A-Za-z0-9_]{6}(\.\w+)?$/XXXXXX$1/ if $base =~ /^(?:pfx-|developer-dashboard-ajax-)/;
      open my $fh, '<', $p or die 'unreadable'; local $/; my $c = <$fh>; close $fh;
      sprintf '%s;%s;%o', $base =~ s/XXXXXX/R/r, $c, (stat $p)[2] & 07777;
    });
  }
  t('cleanup', sub { $rt->_cleanup_saved_ajax_temp_files(@made, undef, '', '/nonexistent/zzz') });
  t('cleanup-gone', sub { scalar grep { -e } @made });
}
# singleton kill (pattern cannot match any real process)
t('kill-undef', sub { $rt->_kill_saved_ajax_singleton(undef) });
t('kill-empty', sub { $rt->_kill_saved_ajax_singleton('') });
t('kill-name', sub { $rt->_kill_saved_ajax_singleton('pax-nonexistent-singleton-qq.(1)') });
t('norm-single', sub { $rt->_normalize_saved_ajax_singleton("ok name") });
t('norm-single-ctl', sub { $rt->_normalize_saved_ajax_singleton("bad\nname") });
t('norm-single-undef', sub { $rt->_normalize_saved_ajax_singleton(undef) });
# stream handle via tie
{
  my @got;
  tie *FH, 'Developer::Dashboard::PageRuntime::StreamHandle', writer => sub { push @got, join('<>', @_); return 'w' };
  my $r1 = print FH 'a', undef, 'b', 3;
  my $r2 = printf FH '%s-%03d-%s', 'x', 7, 'z';
  my $r3 = printf FH 'plain';
  my $r4 = print FH;
  my $r5 = close FH;
  { no warnings; my $r6 = printf FH undef; my $r7 = print FH (); }
  untie *FH;
  print "stream: ", join('|', map { "[$_]" } @got), " r=$r1,$r2,$r3,", (defined $r4 ? $r4 : 'u'), ",$r5\n";
  tie *FH2, 'Developer::Dashboard::PageRuntime::StreamHandle';
  print "default-writer: ", (print FH2 'x') ? 'ok' : 'fail', "\n"; untie *FH2;
  { local $, = '-'; local $\ = "!"; my @g2;
    tie *FH3, 'Developer::Dashboard::PageRuntime::StreamHandle', writer => sub { push @g2, @_ };
    print FH3 'p', 'q'; untie *FH3; print "sep: @g2\n"; }
}
# stream_code_block and the sandpit helpers
{
  my (@out, @err, @ret);
  for my $case (
    [ 'basic', "print 'out1'; print STDERR 'err1'; printf('%s|%d', 'pf', 4); printf STDERR ('%s', 'ep'); return { a => 1 }, [2], 'skip';", {} ],
    [ 'state', 'print "x=$x y=@{$y}"; $x_r = \\"new"; return;', { x => 'sx', y => [1,2] } ],
    [ 'die', 'print "before"; die "oops\n"; print "after";', {} ],
    [ 'syntax', 'print "a" "b" ;', {} ],
    [ 'stash', 'stash({ k => "v" }); print stash("k"); print join(",", sort keys %{ params() }); void({ w => 1 }); hide({ h => 2 }); return;', {} ],
    [ 'stop', 'print "pre"; stop("halting"); print "post"', {} ],
    [ 'stop-undef', 'stop();', {} ],
    [ 'empty', '', {} ],
    [ 'undef-ret', 'return (undef, 0, "s");', {} ],
  ) {
    my ($name, $code, $state) = @$case;
    my (@o, @e, @r);
    my $res = eval { $rt->stream_code_block(code => $code, state => $state, runtime_context => { params => { p1 => 'v1' } },
      stdout_writer => sub { push @o, join('', @_); 1 }, stderr_writer => sub { push @e, join('', @_); 1 }, return_writer => sub { push @r, join('', @_) }) };
    my $x = clean($@);
    my $error = $res ? clean($res->{error}) : '';
    $error =~ s/\n/\\n/g;
    print "scb[$name]: out=", join('|', map { s/\n/\\n/gr } @o), " err=", join('|', map { s/\n/\\n/gr } @e), " ret=", join('|', map { s/\n/\\n/gr } @r),
      " error=$error died=$x state=", ($res ? join(',', map { "$_=" . (ref $res->{merge}{$_} || $res->{merge}{$_}) } sort keys %{ $res->{merge} }) : ''),
      " returns=", ($res ? scalar @{ $res->{returns} } : 'none'), "\n";
  }
  my $res = $rt->stream_code_block(code => 'print "dflt"; print STDERR "dflt-err"; 1');
  print "scb-default-writers: ", ref $res, " error=[", $res->{error}, "]\n";
}
# sandpit lifecycle
{
  my $sp = $rt->_new_sandpit(state => { s => 1 }, runtime_context => { params => { z => 9 } });
  my $pk = $sp->{package};
  print "pkg-shape: ", ($pk =~ /\ADeveloper::Dashboard::Sandpit::\d+::\d+::\d+\z/ ? 'ok' : $pk), "\n";
  t('sp-initial', sub { $pk->__initial_context({ a => 1 }, { params => { q => 2 } }) });
  t('sp-initial-undef', sub { $pk->__initial_context(undef, undef) });
  t('sp-params-empty', sub { scalar keys %{ $pk->params } });
  $pk->__initial_context({ a => 1 }, { params => { q => 2 } });
  t('sp-params', sub { join ',', %{ $pk->params } });
  t('sp-stash-get', sub { $pk->can('stash')->('a') });
  t('sp-stash-set', sub { join ',', sort keys %{ $pk->can('stash')->({ b => 2 }) } });
  t('sp-stash-undef', sub { $pk->can('stash')->(undef) });
  t('sp-hide', sub { $pk->can('hide')->({ c => 3 }) });
  t('sp-hide-str', sub { $pk->can('hide')->('c') });
  t('sp-void', sub { scalar(() = $pk->can('void')->({ d => 4 })) });
  t('sp-void-undef', sub { scalar(() = $pk->can('void')->(undef)) });
  t('sp-stash-after', sub { join ',', map { "$_=" . $pk->can('stash')->($_) } qw(a b c d) });
  t('sp-stop', sub { $pk->can('stop')->('msg') });
  t('sp-stop-undef', sub { $pk->can('stop')->() });
  t('sp-add-error', sub { $pk->can('__add_error')->('e1', undef, '', 'e2'); $pk->can('__add_error')->(); $pk->can('__add_error')->('e3'); 'added' });
  t('sp-errors', sub { join '|', $pk->__errors });
  t('sp-errors-again', sub { scalar(() = $pk->__errors) });
  t('sp-run-ok', sub { join ',', $pk->__run_code('(1, 2, 3)') });
  t('sp-run-list', sub { scalar(() = $pk->__run_code('()')) });
  t('sp-run-die', sub { my @r = $pk->__run_code('die "dead\n"; 1'); join('|', scalar(@r), $pk->__errors) });
  t('sp-run-syntax', sub { my @r = $pk->__run_code('1 +* 2'); my @e = $pk->__errors; scalar(@r) . ':' . scalar(@e) });
  t('sp-run-multi', sub { my @r = $pk->__run_code("my \$x = 1;\nmy \@y = (\$x, 2);\n\@y"); join ',', @r });
  t('sp-run-line', sub { join ',', $pk->__run_code("\n\n__LINE__") });
  t('sp-run-pkg', sub { my ($p) = $pk->__run_code('__PACKAGE__'); $p eq $pk ? 'same' : "diff:$p" });
  t('sp-run-strict', sub { my @r = $pk->__run_code('$undeclared = 1; 5'); scalar(@r) . ':' . scalar($pk->__errors) });
  t('sp-run-j', sub { join ',', $pk->__run_code('j({a=>1}) . je("x")') });
  t('sp-run-sees-stash', sub { $pk->__initial_context({ k => 'vv' }, {}); join ',', $pk->__run_code('$stash->{k}') });
  t('sp-run-want', sub { my $s = $pk->__run_code('(7,8,9)'); $s });
  $rt->_destroy_sandpit($sp);
  t('destroyed', sub { $pk->can('stash') ? 'still' : 'gone' });
  t('destroy-bad', sub { $rt->_destroy_sandpit(undef); $rt->_destroy_sandpit({}); $rt->_destroy_sandpit('x'); 'ok' });
}
t('code_header-none', sub { $rt->_code_header({}) });
t('code_header-undef', sub { $rt->_code_header(undef) });
t('code_header-keys', sub { $rt->_code_header({ a => 1, 'b-c' => 2, _d => 3, '9x' => 1, B2 => 1 }) });
t('code_header-lines', sub { scalar(() = $rt->_code_header({ a => 1 }) =~ /\n/g) });
