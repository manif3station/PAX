# Differential fixture: PageDocument construction, parsing, serialization and helpers.
use strict; no warnings; local $SIG{__WARN__} = sub { };
use Developer::Dashboard::PageDocument;
my $C = 'Developer::Dashboard::PageDocument';
sub clean { my $e = shift; $e =~ s/ at .*? line \d+\.?\n?//g; $e =~ s/\(eval \d+\)/(eval N)/g; return $e }
sub dump_v { my $v = shift; return 'undef' if !defined $v; if (ref $v eq 'HASH') { return '{' . join(',', map { (my $k = $_) =~ s/\(0x[0-9a-f]+\)//; "$k=>" . dump_v($v->{$_}) } sort keys %$v) . '}' } if (ref $v eq 'ARRAY') { return '[' . join(',', map { dump_v($_) } @$v) . ']' } return ref $v ? ref $v : "'$v'"; }
sub t { my ($l, $c) = @_; my @r = eval { $c->() }; my $e = clean($@); $e =~ s/\n/\\n/g; print "$l=", join('|', map { my $s = ref $_ && eval { $_->isa($C) } ? 'DOC' . dump_v({%$_}) : dump_v($_); $s =~ s/\n/\\n/g; $s } @r), ($e ne '' ? " ERR[$e]" : ''), "\n"; }
my $sep = ':' . ('-' x 80) . ':';
# from_hash / from_json
t('from_hash-array', sub { $C->from_hash([]) });
t('from_hash-undef', sub { $C->from_hash(undef) });
t('from_hash-empty', sub { $C->from_hash({}) });
t('from_hash-full', sub { $C->from_hash({ id => 'x', title => '', description => undef, mode => 'view', tags => ['a'], state => { s => 1 }, layout => { body => 'b' }, meta => { m => 1 }, source_version => 0, extra => 'ignored' }) });
t('from_json-bad', sub { $C->from_json('{bad') });
t('from_json-array', sub { $C->from_json('[1]') });
t('from_json-undef', sub { $C->from_json(undef) });
t('from_json-ok', sub { $C->from_json('{"id":"p","title":"T","state":{"k":[1,2,{"z":null}]},"layout":{"body":"<b>"}}') });
t('new-defaults', sub { $C->new });
t('new-subclass-class', sub { ref $C->new(id => 1) });
# canonical_json / as_hash round trip
{
  my $d = $C->from_json('{"id":"p","title":"T e","state":{"k":[1,2]},"layout":{"body":"<b>"},"meta":{"codes":[{"id":"CODE1","body":"print 1"}]}}');
  t('canonical_json', sub { $d->canonical_json });
  t('as_hash', sub { $d->as_hash });
  t('with_mode', sub { $d->with_mode('view')->{mode} });
  t('with_mode-empty', sub { $d->with_mode('')->{mode} });
  t('with_mode-undef', sub { $d->with_mode(undef)->{mode} });
  t('merge-nonhash', sub { $d->merge_state([1]) == $d ? 'same' : 'diff' });
  t('merge', sub { $d->merge_state({ m1 => 1, k => 'over' }); $d->{state} });
  t('instruction_text', sub { $d->instruction_text });
  t('instruction_text-extra', sub { $d->instruction_text('ignored', 'args') });
  t('canonical_instruction', sub { $d->canonical_instruction });
  t('render_template', sub { ref($d->render_template) . ':' . ($d->render_template == $d ? 'self' : 'other') });
  t('render_template-args', sub { $d->render_template(a => 1) == $d ? 'self' : 'other' });
}
# instructions
my @inst = (
  [ 'legacy-basic', "TITLE: My Page\n$sep\nBOOKMARK: my-page\n$sep\nNOTE: a note\nsecond line\n$sep\nSTASH: a => 1, b => [1,'x'], c => { d => undef }\n$sep\nHTML: <p>hi</p>\n$sep\nCODE1: print 'x';\n" ],
  [ 'legacy-head', "TITLE: H\n$sep\nHEAD: <style>a{}</style>\nline2\n\n$sep\nHTML: body\n" ],
  [ 'legacy-icon', "TITLE: I\n$sep\nICON: \n  fa-icon  \n$sep\nHTML: b\n" ],
  [ 'legacy-code-order', join("\n$sep\n", 'TITLE: Order', map { "CODE$_: print $_;" } (10, 2, 1, 100, 21, 3)) . "\n" ],
  [ 'legacy-code-0', join("\n$sep\n", 'TITLE: Z', 'CODE0: zero', 'CODE1000: big', 'CODE1001: toobig') . "\n" ],
  [ 'legacy-md-sep', "TITLE: MD\n---\nBOOKMARK: md\n---\nHTML: <i>x</i>\n" ],
  [ 'legacy-unknown', "TITLE: U\n$sep\nFOO: bar\n$sep\nhtml: lowercase\n$sep\nno colon here\n" ],
  [ 'legacy-empty-title', "TITLE:   \n$sep\nHTML: x\n" ],
  [ 'legacy-description', "TITLE: D\n$sep\nDESCRIPTION: not recognized\n" ],
  [ 'legacy-only-sep', "$sep\n" ],
  [ 'empty', '' ],
  [ 'whitespace', "  \n\n" ],
  [ 'undef', undef ],
  [ 'stash-json', "TITLE: J\n$sep\nSTASH: {\"a\":1,\"b\":[2]}\n" ],
  [ 'stash-json-bad', "TITLE: J\n$sep\nSTASH: {bad json\n" ],
  [ 'stash-json-array', "TITLE: J\n$sep\nSTASH: [1,2]\n" ],
  [ 'stash-literal-fn', "TITLE: S\n$sep\nSTASH: a => time, b => 1\n" ],
  [ 'stash-literal-sys', "TITLE: S\n$sep\nSTASH: a => system('true'), b => 1\n" ],
  [ 'stash-literal-var', "TITLE: S\n$sep\nSTASH: a => \$ENV{HOME}, b => 2\n" ],
  [ 'stash-literal-syntax', "TITLE: S\n$sep\nSTASH: a => (\n" ],
  [ 'stash-literal-num', "TITLE: S\n$sep\nSTASH: n => 1+2, s => 'q', l => [1,2,3], u => undef\n" ],
  [ 'stash-literal-oddlist', "TITLE: S\n$sep\nSTASH: a, b, c\n" ],
  [ 'stash-literal-str-interp', "TITLE: S\n$sep\nSTASH: a => \"x\" . \"y\", b => 'it\\'s'\n" ],
  [ 'modern', "=== TITLE ===\nModern\n=== BOOKMARK ===\nmod\n=== NOTE ===\nn1\nn2\n=== ICON ===\n  ic \n=== HEAD ===\n<h>\n\n=== HTML ===\n<p>x</p>\n=== CODE2 ===\nprint 2;\n=== CODE10 ===\nprint 10;\n=== CODE1 ===\nprint 1;\n=== STASH ===\nk => 'v'\n" ],
  [ 'modern-preamble', "ignored before\n=== TITLE ===\nT\n" ],
  [ 'modern-nosections', "=== X.Y ===\n" ],
  [ 'modern-dotted', "=== A.B ===\nz\n=== TITLE ===\nt\n" ],
);
for my $i (@inst) {
  my ($name, $text) = @$i;
  t("fi[$name]", sub { $C->from_instruction($text) });
  t("rt[$name]", sub { my $d = $C->from_instruction($text); $d->canonical_instruction });
  t("rt2[$name]", sub { my $d = $C->from_instruction($C->from_instruction($text)->legacy_instruction); $d->legacy_instruction });
}
# direct legacy instruction building
{
  my $d = $C->new(id => 'i', title => 'T', description => "d\n\n", state => { z => [1, { a => "it's" }], a => 'back\\slash', n => -4.5, e => '', u => undef, 'k k' => 1 }, layout => { body => "\n\nbody\n\n" },
    meta => { icon => 'ic', head => "<h>\n", codes => [ { id => 'CODE2', body => "two\n" }, { id => 'bad', body => 'x' }, 'str', { id => 'CODE1' }, { id => 'CODE3', body => "\n\n3\n\n" } ] });
  t('legacy_instruction', sub { $d->legacy_instruction });
  my $d2 = $C->new(title => undef);
  $d2->{title} = undef; $d2->{meta}{head} = ''; $d2->{meta}{icon} = '';
  t('legacy_instruction-min', sub { $d2->legacy_instruction });
  my $d3 = $C->new(meta => { head => 'only head' }, state => {});
  t('legacy_instruction-head', sub { $d3->legacy_instruction });
  my $d4 = $C->new(meta => { codes => 'notarray' }, state => 'notahash');
  t('legacy_instruction-oddstate', sub { $d4->legacy_instruction });
}
# helpers called directly
for my $v (undef, 'str', 5, [], {}, [1, 'a', undef, [2]], { b => 1, a => [2, "x'y"] }, "a\\b", "it's", '-3', '1.5', '1.', '.5', "a\n") {
  t('_legacy_value', sub { Developer::Dashboard::PageDocument::_legacy_value($v) });
}
for my $v (undef, 'x', [], {}, { b => 1, a => 2 }, { a => undef, 'b c' => { d => [1] } }) {
  t('_legacy_stash_text', sub { Developer::Dashboard::PageDocument::_legacy_stash_text($v) });
}
for my $s ('', "a'b", 'a\\b', "\\'") { t('_legacy_quote', sub { Developer::Dashboard::PageDocument::_legacy_quote($s) }); }
my $ctx = { a => { b => { c => 'deep', n => 0, e => '', u => undef, r => [1] }, s => 'str' }, top => 'T', 0 => 'zero', '' => 'emptykey' };
for my $path ('top', 'a.s', 'a.b.c', 'a.b.n', 'a.b.e', 'a.b.u', 'a.b.r', 'a.b', 'a.x', 'x.y.z', '', '.', 'a..s', ' a.s ', 'a. s', "\ta.b.c\n", '0', 'a.s.t', undef) {
  t("_template_value[" . (defined $path ? $path : 'undef') . "]", sub { Developer::Dashboard::PageDocument::_template_value($path, $ctx) });
}
t('_template_value-ctx-undef', sub { Developer::Dashboard::PageDocument::_template_value('a', undef) });
t('_template_value-ctx-array', sub { Developer::Dashboard::PageDocument::_template_value('0', [5]) });
t('_template_value-ctx-str', sub { Developer::Dashboard::PageDocument::_template_value('', 'str') });
for my $j (undef, '', '  ', '{"a":1}', '[1,2]', '{bad', '"s"', '0', 'null', " {\"x\":[1]} \n", '{"a":') {
  t('_decode_structured_json', sub { Developer::Dashboard::PageDocument::_decode_structured_json($j) });
}
for my $j (undef, '', ' ', '{"a":1}', '[1]', '{bad', "a => 1", "a => 'x', b => [1,2]", 'a => time', 'a => system("true")', "a => `echo hi`", 'a => do { 1 }', 'a => sub { 1 }', "a => 1,\nb => 2", 'a => ', '$x => 1', '__PACKAGE__ => 1', 'a => __PACKAGE__', "a => 'x' x 3", "a => 1 ? 2 : 3", 'a => [ map { $_ } 1,2 ]', 'a => \\"s"', 'a => $0', 'a => qw(x y)') {
  t('_decode_stash_section[' . (defined $j ? $j : 'undef') . ']', sub { Developer::Dashboard::PageDocument::_decode_stash_section($j) });
  t('_safe_eval[' . (defined $j ? $j : 'undef') . ']', sub { Developer::Dashboard::PageDocument::_safe_eval_stash_literal($j) });
}
for my $t (undef, '', "TITLE: x\n$sep\nHTML: y", "TITLE: x\r\n$sep\r\nHTML: y\r\n", "a: b", "TITLE:\n\nbody", "CODE5: x\n---\nCODE6: y") {
  t('_parse_legacy_sections', sub { my %h = Developer::Dashboard::PageDocument::_parse_legacy_sections($t); join ';', map { "$_=" . join('/', @{ $h{$_} }) } sort keys %h });
}
# render_html
{
  my $d = $C->new(id => 'r', title => 'A <b> & "q"', description => 'desc <i>', layout => { body => '<p>body</p>' }, meta => { head => '<meta name="x">', runtime_outputs => [ 'plain', '<script>set_chain_value(1)</script>', '<script>x</script>', '<script>dashboard_ajax_singleton_cleanup("a")</script>', undef, [1], 'tail' ], runtime_errors => [ "e <1>\n", undef, [], "e2 & 'q'" ] });
  my $h = $d->render_html(chrome_html => '<div>chrome</div>', nav_html => '<nav>n</nav>');
  $h =~ s/<style>.*?<\/style>/<style>STYLE<\/style>/s; $h =~ s/<script>\s*function set_chain_value.*?<\/script>/<script>BOOT<\/script>/s;
  print "html1=$h\n";
  my $e = $C->new(title => '', description => '');
  my $h2 = $e->render_html; $h2 =~ s/<style>.*?<\/style>/<style>STYLE<\/style>/s; $h2 =~ s/<script>\s*function set_chain_value.*?<\/script>/<script>BOOT<\/script>/s;
  print "html2=$h2\n";
  my $style = Developer::Dashboard::PageDocument::_html_document_style(); my $boot = Developer::Dashboard::PageDocument::_legacy_bootstrap();
  require Digest::MD5; print "style=", Digest::MD5::md5_hex($style), " boot=", Digest::MD5::md5_hex($boot), " blen=", length($boot), "\n";
  my ($b, $o) = Developer::Dashboard::PageDocument::_split_runtime_output_chunks([ 'a', '<script>set_chain_value</script>', '<script>q</script>', 'b' ]);
  print "split=[$b][$o]\n";
  ($b, $o) = Developer::Dashboard::PageDocument::_split_runtime_output_chunks(undef); print "split-undef=[$b][$o]\n";
  print "errchunks=", Developer::Dashboard::PageDocument::_render_runtime_error_chunks([ 'a<', undef, 'b' ]), Developer::Dashboard::PageDocument::_render_runtime_error_chunks(undef), "\n";
  for my $x (undef, '', 'a&b<c>d"e\'f', "x\ny") { print "html_esc=", dump_v(Developer::Dashboard::PageDocument::_html($x)), "\n"; }
  for my $x (undef, '', '  a b  ', "\n\tx\n", 0) { print "trim=", dump_v(Developer::Dashboard::TextUtils::_trim($x)), "\n"; }
  for my $x (undef, '', "a\n", "a\n\n\n", "\n\na", "a\r\n", 0) { print "trimtr=", dump_v(Developer::Dashboard::PageDocument::_trim_trailing_newline($x)), "\n"; }
}
