# Differential fixture: PageStore ids, urls, tokens, raw nav fragments, legacy icon repair and saved page IO.
use strict; no warnings; local $SIG{__WARN__} = sub { };
use utf8;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Developer::Dashboard::PathRegistry;
use Developer::Dashboard::PageStore;
use Developer::Dashboard::PageDocument;
binmode STDOUT, ':encoding(UTF-8)';
sub use_codec { require Developer::Dashboard::Codec; }
my $home = tempdir(CLEANUP => 1);
my $paths = Developer::Dashboard::PathRegistry->new(home => $home);
my $S = Developer::Dashboard::PageStore->new(paths => $paths);
my $D = 'Developer::Dashboard::PageDocument';
sub clean { my $e = shift; $e =~ s/ at .*? line \d+\.?\n?//g; $e =~ s/\(eval \d+\)/(eval N)/g; $e =~ s/\Q$home\E/HOME/g; return $e }
sub dump_v { my $v = shift; return 'undef' if !defined $v; if (ref $v eq 'HASH') { return '{' . join(',', map { "$_=>" . dump_v($v->{$_}) } sort keys %$v) . '}' } if (ref $v eq 'ARRAY') { return '[' . join(',', map { dump_v($_) } @$v) . ']' } if (ref $v && eval { $v->isa($D) }) { return 'DOC' . dump_v({ %$v }) } my $s = "$v"; $s =~ s/\Q$home\E/HOME/g; return ref $v ? ref $v : "'$s'"; }
sub t { my ($l, $c) = @_; my @r = eval { $c->() }; my $e = clean($@); $e =~ s/\n/\\n/g; my $o = join('|', map { dump_v($_) } @r); $o =~ s/\n/\\n/g; print "$l=$o", ($e ne '' ? " ERR[$e]" : ''), "\n"; }
# id normalization
for my $id (undef, '', ' a ', "\tb\n", '/app/x', '//app//y/z', '/app/', '/app', '/x/y', '///q', 'app/x', '/APP/x', '/apps/x', ' /app/ x ', 'a b', "a\nb", '/app//app/z') {
  t('norm[' . (defined $id ? $id : 'undef') . ']', sub { $S->_normalized_page_id($id) });
}
# fragment detection
for my $i (undef, '', ' ', 'plain', '[% x %]', '<div>', '< div>', '<!-- c -->', '</p>', '<1>', '<>', 'a < b > c', "multi\n<span class='x'>y</span>", '[%', '[', '<a', '<a >', '<!>', '</>', '< /x>') {
  t('raw_nav?[' . (defined $i ? $i : 'undef') . ']', sub { $S->_looks_like_raw_nav_fragment($i) });
}
# raw nav page
t('raw_nav_page', sub { $S->_raw_nav_fragment_page(id => 'nav/a.tt', instruction => '<b>x</b>') });
t('raw_nav_page-noinstr', sub { $S->_raw_nav_fragment_page(id => 'nav/dir/b.tt') });
t('raw_nav_page-undefinstr', sub { $S->_raw_nav_fragment_page(id => 'c.tt', instruction => undef) });
t('raw_nav_page-noid', sub { $S->_raw_nav_fragment_page(instruction => 'x') });
t('raw_nav_page-emptyid', sub { $S->_raw_nav_fragment_page(id => '', instruction => 'x') });
t('raw_nav_page-zero', sub { $S->_raw_nav_fragment_page(id => '0', instruction => 'x') });
# legacy icon markup
my @icons = (undef, '', 'plain', "\x{1F9D1}\x{FFFD}\x{1F4BB}", "a\x{1F9D1}\x{FFFD}\x{1F4BB}b\x{1F9D1}\x{FFFD}\x{1F4BB}c", "<h2>\x{FFFD} Title</h2>", "<h2>\x{FFFD}Title</h2>", "<h2>\x{FFFD}\n x", "<span class=\"icon\">ab\x{FFFD}cd</span>", "<span  class=\"icon\">\x{FFFD}</span>", "<span class=\"icon\">ok</span>", "<span class=\"icon\"><b>\x{FFFD}</b></span>", "<h2>x</h2>", "\x{FFFD}", "<h2>\x{FFFD} A</h2><span class=\"icon\">\x{FFFD}</span>\x{1F9D1}\x{FFFD}\x{1F4BB}");
for my $i (@icons) {
  t('icon[' . (defined $i ? join('', map { $_ > 126 ? sprintf('\\x{%x}', $_) : chr } unpack 'U*', $i) : 'undef') . ']', sub { my $r = $S->_normalize_legacy_icon_markup($i); defined $r ? join('', map { $_ > 126 ? sprintf('\\x{%x}', $_) : chr } unpack 'U*', $r) : undef });
}
# urls and tokens
my $doc = $D->new(id => 'u1', title => 'T', layout => { body => 'b&c' }, state => { a => 1 }, meta => { codes => [ { id => 'CODE1', body => 'print 1;' } ] });
my $raw = $D->new(id => 'u2', title => 'R', meta => { raw_instruction => "TITLE: Raw é\n" });
my $rawempty = $D->new(id => 'u3', title => 'E', meta => { raw_instruction => '' });
for my $p ([doc => $doc], [raw => $raw], [rawempty => $rawempty], [hash => { id => 'h', title => 'H' }], [hashbad => 'str'], [hashundef => undef]) {
  my ($n, $page) = @$p;
  use_codec();
  t("encode_page[$n]", sub { Developer::Dashboard::Codec::decode_payload($S->encode_page($page)) });
  for my $kind (qw(editable_url render_url source_url)) {
    t("$kind\[$n]", sub { my $u = $S->$kind($page); my ($pre, $tok) = $u =~ /\A(.*?token=)(.*)\z/s; $tok =~ s/%([0-9A-Fa-f]{2})/chr hex $1/ge; "$pre|" . Developer::Dashboard::Codec::decode_payload($tok) });
  }
  t("transient-roundtrip[$n]", sub { my $tok = $S->encode_page($page); my $pg = $S->load_transient_page($tok); $pg->canonical_instruction . '|' . $pg->{meta}{source_kind} });
}
t('transient-bad', sub { $S->load_transient_page('!!!notbase64') });
t('transient-empty', sub { $S->load_transient_page('') });
t('transient-undef', sub { $S->load_transient_page(undef) });
t('transient-garbage', sub { $S->load_transient_page('YWJj') });
# saved page IO
t('page_file', sub { $S->page_file('a/b') });
t('page_file-app', sub { $S->page_file('/app/x') });
t('page_file-undef', sub { $S->page_file(undef) });
t('page_file-empty', sub { $S->page_file('') });
t('page_file-dotdot', sub { $S->page_file('../x') });
t('page_file-abs', sub { $S->page_file('/etc/passwd') });
t('page_file-drive', sub { $S->page_file('C:x') });
t('page_file-empty-seg', sub { $S->page_file('a//b') });
t('save-noid', sub { $S->save_page({ title => 'x' }) });
t('save-doc', sub { $S->save_page($D->new(id => 'sv1', title => 'Saved', layout => { body => 'hello' }, state => { k => 'v' })) });
t('save-hash', sub { $S->save_page({ id => 'dir/sv2', title => 'Nested', layout => { body => 'n' } }) });
t('save-app-prefix', sub { $S->save_page({ id => '/app/sv3', title => 'App' }) });
t('save-bad', sub { $S->save_page({ id => '../esc', title => 'x' }) });
t('load', sub { my $p = $S->load_saved_page('sv1'); $p->{meta}{raw_instruction} =~ s/\n/\\n/g; $p });
t('load-nested', sub { $S->load_saved_page('dir/sv2')->{title} });
t('load-app', sub { $S->load_saved_page('/app/sv3')->{id} });
t('load-missing', sub { $S->load_saved_page('nope') });
t('load-bad', sub { $S->load_saved_page('../x') });
t('read_entry', sub { $S->read_saved_entry('sv1') });
t('read_entry-missing', sub { $S->read_saved_entry('nope') });
t('existing', sub { scalar $S->_existing_page_file('sv1') });
t('existing-list', sub { my @r = $S->_existing_page_file('sv1'); scalar @r });
t('existing-none', sub { my @r = $S->_existing_page_file('zzz'); scalar @r });
t('candidates', sub { map { $_->{file} } $S->_page_file_candidates('c/d') });
my $droot = $paths->dashboards_root;
make_path("$droot/nav");
for my $f (['nav/frag.tt', "<li>[% x %]</li>\n"], ['nav/plain.tt', "just text\n"], ['nav/bad.txt', "<b>html</b>"], ['legacy', "TITLE: Leg\n:" . ('-' x 80) . ":\nHTML: <h2>\x{FFFD} Head</h2>\n"], ['empty', ''], ['junk', "no sections here"]) {
  open my $fh, '>:raw', "$droot/$f->[0]" or die; print {$fh} Encode::encode('UTF-8', $f->[1]); close $fh;
}
{ open my $fh, '>:raw', "$droot/badutf"; print {$fh} "TITLE: Bad \xff\xfe\n:" . ('-' x 80) . ":\nHTML: ok\n"; close $fh; }
for my $id ('nav/frag.tt', 'nav/plain.tt', 'nav/bad.txt', 'legacy', 'empty', 'junk', 'badutf') {
  t("load[$id]", sub { my $p = $S->load_saved_page($id); my $r = delete $p->{meta}{raw_instruction}; dump_v($p) . '|' . length($r) });
  t("read[$id]", sub { $S->read_saved_entry($id) });
  t("loadfile[$id]", sub { dump_v($S->_load_page_file("$droot/$id", id => $id)) });
  t("readinstr[$id]", sub { $S->_read_saved_instruction("$droot/$id") });
  t("readinstr-root[$id]", sub { $S->_read_saved_instruction("$droot/$id", root => $droot, id => $id) });
}
t('loadfile-missing', sub { $S->_load_page_file("$droot/zzz-missing", id => 'x') });
t('loadinstr-nav', sub { dump_v($S->_load_page_instruction("[% x %]", id => 'nav/q.tt')) });
t('loadinstr-nav-notfrag', sub { dump_v($S->_load_page_instruction("", id => 'nav/q.tt')) });
t('loadinstr-notnav', sub { dump_v($S->_load_page_instruction("", id => 'other')) });
t('loadinstr-noid', sub { dump_v($S->_load_page_instruction("")) });
t('list', sub { $S->list_saved_pages });
t('entries-root', sub { sort map { $_->{id} } $S->_saved_page_entries_for_root($droot) });
t('entries-undef', sub { scalar(() = $S->_saved_page_entries_for_root(undef)) });
t('entries-missing', sub { scalar(() = $S->_saved_page_entries_for_root("$home/nonexistent")) });
# symlink and traversal handling
symlink '/etc/passwd', "$droot/linkfile";
mkdir "$home/outside"; open my $o, '>', "$home/outside/secret"; print {$o} "TITLE: Secret\n"; close $o;
symlink "$home/outside", "$droot/linkdir";
t('list-with-links', sub { $S->list_saved_pages });
t('load-link', sub { $S->load_saved_page('linkfile') });
t('load-linkdir', sub { $S->load_saved_page('linkdir/secret') });
# migration
open my $j, '>', "$droot/old1.json"; print {$j} '{"id":"mig1","title":"Migrated","layout":{"body":"mb"}}'; close $j;
open $j, '>', "$droot/old2.json"; print {$j} '{"title":"NoId"}'; close $j;
open $j, '>', "$droot/old3.json"; print {$j} 'not json'; close $j;
open $j, '>', "$droot/old4.json"; print {$j} '{"id":"../esc","title":"Bad"}'; close $j;
mkdir "$droot/dir.json";
symlink "$droot/sv1", "$droot/linked.json";
t('migrate', sub { my $r = $S->migrate_legacy_json_pages; join ';', map { dump_v({ %$_, file => ($_->{file} =~ s{.*/}{}r) }) } sort { $a->{from} cmp $b->{from} } @$r });
t('migrate-again', sub { scalar @{ $S->migrate_legacy_json_pages } });
t('after-migrate', sub { $S->list_saved_pages });
t('after-migrate-load', sub { $S->load_saved_page('mig1')->{title} });
t('after-migrate-files', sub { opendir my $dh, $droot; join ',', sort grep { /\.json$|^old/ } readdir $dh });
# containment helpers
t('contained-ok', sub { $S->_assert_page_path_contained("$droot/sv1", root => $droot) });
t('contained-bad', sub { $S->_assert_page_path_contained("/etc/passwd", root => $droot) });
t('contained-undef', sub { $S->_assert_page_path_contained(undef) });
t('contained-write', sub { $S->_assert_page_path_contained("$droot/new/deep/file", root => $droot, for_write => 1) });
t('contained-root', sub { $S->_assert_page_path_contained($droot, root => $droot) });
t('validated', sub { map { eval { $S->_validated_page_id($_) } // 'ERR' } ('ok', 'a/b', '..', '.', 'a/./b', 'a/../b', '/', ' ', 'C:\\x', 'a\\..\\b') });
