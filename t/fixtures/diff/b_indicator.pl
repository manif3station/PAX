use strict; use warnings;
use File::Path qw(make_path);
use Developer::Dashboard::PathRegistry;
use Developer::Dashboard::IndicatorStore;
use Developer::Dashboard::JSON qw(json_encode);
sub clean { my $d = shift; return undef if !defined $d; if (ref $d eq 'HASH') { return { map { $_ => ($_ eq 'updated_at' ? 'T' : clean($d->{$_})) } keys %$d } } if (ref $d eq 'ARRAY') { return [ map { clean($_) } @$d ] } return $d }
sub show { my ($l,$v)=@_; print "$l=", (defined $v ? json_encode(clean($v)) : 'undef'), "\n"; }
sub try { my ($l,$c)=@_; my @r = eval { $c->() }; my $e=$@; $e =~ s/ at .* line \d+.*//s; print "$l: ", ($e ne '' ? "died($e)" : 'ok'), "\n"; return @r }
my $home = $ENV{HOME};
my $proj = "$home/work/proj/sub"; make_path("$proj/.developer-dashboard", "$home/work/proj/.developer-dashboard");
my $paths = Developer::Dashboard::PathRegistry->new(home => $home, cwd => $proj);
my $store = Developer::Dashboard::IndicatorStore->new(paths => $paths);
my $hpaths = Developer::Dashboard::PathRegistry->new(home => $home, cwd => $home);
my $hstore = Developer::Dashboard::IndicatorStore->new(paths => $hpaths);
# template text
for my $t (undef, '', 'plain', '[% x %]', 'a[%b', '[', '%]', 0, '[%') { print "tt=", ($store->_is_template_toolkit_text($t) // 'undef'), "\n" }
# placeholder
for my $i (undef, 'str', [], {}, {managed_by_collector=>0,status=>'missing'}, {managed_by_collector=>1}, {managed_by_collector=>1,status=>'missing'}, {managed_by_collector=>1,status=>'MISSING'}, {managed_by_collector=>1,status=>'ok'}, {managed_by_collector=>'yes',status=>undef}) {
    print "ph=", $store->_is_placeholder_missing_indicator($i), "\n";
}
# local / inherited with no indicator
show('local_none', scalar $store->_local_indicator('nothere'));
show('inh_none', scalar $store->_nearest_inherited_indicator('nothere'));
$hstore->set_indicator('bq_home', label=>'Home', status=>'ok', updated_at=>1);
show('local_home_only', scalar $store->_local_indicator('bq_home'));
show('inh_home_only', scalar $store->_nearest_inherited_indicator('bq_home'));
$store->set_indicator('bq_home', label=>'Deep', status=>'error', updated_at=>2);
show('local_both', scalar $store->_local_indicator('bq_home'));
show('inh_both', scalar $store->_nearest_inherited_indicator('bq_home'));
show('get_both', scalar $store->get_indicator('bq_home'));
$store->set_indicator('bq_deep', label=>'DeepOnly', status=>'ok', updated_at=>3);
show('local_deep', scalar $store->_local_indicator('bq_deep'));
show('inh_deep', scalar $store->_nearest_inherited_indicator('bq_deep'));
# mark_stale
show('stale_missing', scalar $store->mark_stale('bq_nosuch'));
my $r = $store->mark_stale('bq_deep'); $r->{updated_at}=0 if $r; show('stale_default', $r);
$r = $store->mark_stale('bq_deep', status=>'error'); show('stale_status', $r);
$r = $store->mark_stale('bq_home', status=>undef); show('stale_undef_status', $r);
$r = $store->mark_stale('bq_home', status=>''); show('stale_empty_status', $r);
show('is_stale', [ map { $store->is_stale($_) } ({stale=>1}, {updated_at=>1}) ]);
# delete
show('del_undef', scalar $store->delete_indicator(undef));
show('del_empty', scalar $store->delete_indicator(''));
show('del_missing', scalar $store->delete_indicator('bq_nosuch'));
show('del_deep', scalar $store->delete_indicator('bq_deep'));
show('after_del_deep', scalar $store->get_indicator('bq_deep'));
show('del_home_layered', scalar $store->delete_indicator('bq_home'));
show('after_del_home', scalar $store->get_indicator('bq_home'));
# dir with extra file isn't removed
$hstore->set_indicator('bq_extra', label=>'E', status=>'ok', updated_at=>1);
my ($root) = $hpaths->indicators_roots;
open my $fh, '>', "$root/bq_extra/keep.txt" or die; print $fh "x"; close $fh;
show('del_extra', scalar $hstore->delete_indicator('bq_extra'));
print "extra_dir_exists=", (-d "$root/bq_extra" ? 1 : 0), " status_exists=", (-f "$root/bq_extra/status.json" ? 1:0), "\n";
unlink "$root/bq_extra/keep.txt"; $hstore->delete_indicator('bq_extra');
print "extra_dir_after=", (-d "$root/bq_extra" ? 1 : 0), "\n";
# collector sync exercising placeholder + candidate
my $jobs = [ { name=>'bq_c1', command=>'true', indicator=>{ label=>'C1', icon=>'[% x %]' } }, { name=>'bq_c2', command=>'true', indicator=>{ label=>'C2', icon=>'i', alias=>'a' } } ];
show('need_sync1', scalar $store->collectors_need_sync($jobs));
show('sync1', scalar $store->sync_collectors($jobs));
show('need_sync2', scalar $store->collectors_need_sync($jobs));
show('list', [ $store->list_indicators ]);
$store->set_indicator('bq_c2', %{ $store->get_indicator('bq_c2') }, label=>'Custom', status=>'ok');
show('sync2', scalar $store->sync_collectors($jobs));
show('get_c2', scalar $store->get_indicator('bq_c2'));
show('sync_removed', scalar $store->sync_collectors([ $jobs->[0] ]));
show('list2', [ $store->list_indicators ]);
show('sync_removed_all', scalar $store->sync_collectors([ { name=>'zzz', command=>'x', indicator=>{label=>'Z'} } ]));
show('list3', [ $store->list_indicators ]);
$store->delete_indicator($_) for qw(bq_c1 bq_c2 zzz bq_home bq_deep bq_extra);
show('final', [ $store->list_indicators ]);
