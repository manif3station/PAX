use strict; use warnings;
use Developer::Dashboard::PathRegistry;
use Developer::Dashboard::FileRegistry;
use Developer::Dashboard::Collector;
use Developer::Dashboard::CollectorRunner;
use Developer::Dashboard::JSON qw(json_encode);
sub show { my ($l,$v)=@_; print "$l=", (defined $v ? (ref $v ? json_encode($v) : "'$v'") : 'undef'), "\n"; }
sub try { my ($l,$c)=@_; my @r = eval { $c->() }; my $e=$@; $e =~ s/ at .* line \d+.*//s; print "$l: ", ($e ne '' ? "died($e)" : 'ok'), "\n"; return @r }
my $paths = Developer::Dashboard::PathRegistry->new(home => $ENV{HOME}, cwd => $ENV{HOME});
my $runner = Developer::Dashboard::CollectorRunner->new(paths => $paths, files => Developer::Dashboard::FileRegistry->new(paths => $paths), collectors => Developer::Dashboard::Collector->new(paths => $paths));
# _cron_match
my @specs = (undef, '', '*', '5', '05', '5,10,15', '*/5', '*/0', '*/1', '1-3', '3-1', '0-59', 'x', '5-', '-5', '*/5,7', '1-2,*/7', ' 5', '5 ', '2.5', '*/', '**', '10-20/2', '0');
for my $s (@specs) {
    my @r = map { Developer::Dashboard::CollectorRunner::_cron_match($s, $_) } (0, 1, 2, 3, 5, 7, 10, 14, 15, 20, 31, 59);
    print "cron(", (defined $s ? "'$s'" : 'undef'), ")=", join('', @r), "\n";
}
show('cron_novalue_str', scalar Developer::Dashboard::CollectorRunner::_cron_match('5', 'abc'));
show('cron_undef_value', scalar Developer::Dashboard::CollectorRunner::_cron_match('*/5', undef)) if 0;
# _append_error_text
my @cases = ([undef,undef],[undef,'e'],['',''],['s',''],['s','e'],["s\n",'e'],["s\n\n",'e'],['', 'e'],["a\nb",'x y'],['s',"e\n"],[0,0],['0','0'],['s',undef]);
for my $c (@cases) { my $r = $runner->_append_error_text(@$c); $r =~ s/\n/\\n/g; print "append(", join(',', map { defined $_ ? "'$_'" : 'undef' } @$c), ")='$r'\n"; }
# template vars
for my $out ('{"a":1,"b":{"c":2}}', '[1,2,3]', '"str"', '5', 'null', 'true', '', undef, '{bad', '{"a":', "{\"x\":\"y\"}\n") {
    my $r = eval { $runner->_indicator_template_vars(collector_name => 'cn', stdout => $out) }; my $e = $@; $e =~ s/ at .* line \d+.*//s if 0;
    $e =~ s/\(offset \d+\)//; print "vars(", (defined $out ? "'$out'" : 'undef'), ")=", ($e ne '' ? "died($e)" : json_encode($r)), "\n";
}
try('vars_noname', sub { $runner->_indicator_template_vars(stdout => '{}') });
try('vars_emptyname', sub { $runner->_indicator_template_vars(collector_name => '', stdout => '{}') });
try('vars_name0', sub { $runner->_indicator_template_vars(collector_name => '0', stdout => '{}') });
# render
for my $t ('[% a %]', 'x[% b.c %]y', '[% data.0 %]', '[% IF a == 1 %]one[% ELSE %]other[% END %]', 'plain', '[% a | html %]', '[% FOREACH i IN data %]<[% i %]>[% END %]', '[% syntax error %', '[% INCLUDE nosuchfile %]', '[% undefined_var %]|', "multi\nline [% a %]") {
    for my $out ('{"a":1,"b":{"c":2}}', '[1,2,3]', '{"a":"<&>"}') {
        my $r = eval { $runner->_render_indicator_icon_template(collector_name => 'cn', template => $t, stdout => $out) }; my $e = $@; $e =~ s/\n/\\n/g;
        print "render(", $t =~ s/\n/\\n/gr, " | $out)=", ($e ne '' ? "died($e)" : "'" . ($r =~ s/\n/\\n/gr =~ s/0x[0-9a-f]+/ADDR/gr) . "'"), "\n";
    }
}
try('render_noname', sub { $runner->_render_indicator_icon_template(template => 'x', stdout => '{}') });
try('render_notemplate', sub { $runner->_render_indicator_icon_template(collector_name => 'n', stdout => '{}') });
try('render_emptytemplate', sub { $runner->_render_indicator_icon_template(collector_name => 'n', template => '', stdout => '{}') });
try('render_badjson', sub { $runner->_render_indicator_icon_template(collector_name => 'n', template => 'x', stdout => 'nojson') });
# materialize
try('mat_nojob', sub { $runner->_materialize_indicator_state(indicator => {}) });
try('mat_noind', sub { $runner->_materialize_indicator_state(job => {name=>'n'}) });
show('mat_plain', scalar $runner->_materialize_indicator_state(job => {name=>'n'}, indicator => {label=>'L', icon=>'i'}));
show('mat_empty_tpl', scalar $runner->_materialize_indicator_state(job => {name=>'n'}, indicator => {label=>'L', icon=>'i', icon_template=>''}));
show('mat_tpl', scalar $runner->_materialize_indicator_state(job => {name=>'n'}, indicator => {label=>'L', icon=>'', icon_template=>'v=[% v %]'}, stdout => '{"v":42}'));
show('mat_tpl_arr', scalar $runner->_materialize_indicator_state(job => {name=>'n'}, indicator => {icon_template=>'[% data.1 %]'}, stdout => '[7,8]'));
try('mat_tpl_badjson', sub { $runner->_materialize_indicator_state(job => {name=>'n'}, indicator => {icon_template=>'x'}, stdout => 'oops') });
try('mat_tpl_noname', sub { $runner->_materialize_indicator_state(job => {}, indicator => {icon_template=>'x'}, stdout => '{}') });
my $orig = { label=>'L', icon_template=>'[% v %]' }; my $m = $runner->_materialize_indicator_state(job => {name=>'n'}, indicator => $orig, stdout => '{"v":1}');
print "copy_not_alias=", ($m != $orig && !exists $orig->{icon} ? 1 : 0), "\n";
