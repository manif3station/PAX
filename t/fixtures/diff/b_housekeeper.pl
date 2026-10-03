use strict; use warnings;
use File::Path qw(make_path remove_tree);
use File::Spec;
my $home = $ENV{HOME};
my $st = "$home/bqstate";
make_path($st);
$ENV{DEVELOPER_DASHBOARD_STATE_ROOT} = $st;
require Developer::Dashboard::PathRegistry;
require Developer::Dashboard::Housekeeper;
require Developer::Dashboard::JSON;
sub json_encode { Developer::Dashboard::JSON::json_encode(@_) }
sub norm { my $s = shift; $s =~ s/\Q$home\E/HOME/g; $s }
sub show { my ($l,$v)=@_; print "$l=", norm(defined $v ? (ref $v ? json_encode($v) : "'$v'") : 'undef'), "\n"; }
sub try { my ($l,$c)=@_; my @r = eval { $c->() }; my $e=$@; $e =~ s/ at .* line \d+.*//s; $e = norm($e); $e =~ s/\n/\\n/g; print "$l: ", ($e ne '' ? "died($e)" : 'ok'), "\n"; return @r }
my $paths = Developer::Dashboard::PathRegistry->new(home => $home, cwd => $home);
my $hk = Developer::Dashboard::Housekeeper->new(paths => $paths);
sub age { my ($p, $secs) = @_; my $t = time - $secs; utime $t, $t, $p or die "utime $p: $!"; }
sub wr { my ($p, $c) = @_; open my $fh, '>', $p or die "$p: $!"; print $fh $c; close $fh; }
# _collector_store / _config memoisation
my $cs = $hk->_collector_store; print "store_class=", ref($cs), " same=", ($cs == $hk->_collector_store ? 1 : 0), "\n";
my $cf = $hk->_config; print "config_class=", ref($cf), " same=", ($cf == $hk->_config ? 1 : 0), "\n";
print "config_collectors=", scalar(@{ $cf->collectors }), "\n";
# _only_missing_tree_errors
my @err = (undef, 'x', [], [ {a=>'No such file or directory'} ], [ {a=>'x: No such file or directory'}, {b=>'No such file or directory'} ], [ {a=>'Permission denied'} ], [ {a=>'No such file or directory'}, {b=>'Permission denied'} ], [ {} ], [ undef ], [ {a=>undef} ], [ 'str' ]);
for my $e (@err) { my $r = eval { $hk->_only_missing_tree_errors($e) }; print "missing_errs=", (defined $r ? $r : 'died'), "\n" }
# _path_is_old_enough
wr("$home/bq_file", 'x'); age("$home/bq_file", 100);
for my $a (0, 50, 99, 100, 101, 1000, '0') { print "old_enough($a)=", $hk->_path_is_old_enough("$home/bq_file", $a), "\n" }
print "old_enough_missing=", $hk->_path_is_old_enough("$home/bq_nosuch", 0), "\n";
print "old_enough_dir=", $hk->_path_is_old_enough($home, 0), "\n";
# _read_state_metadata
make_path("$home/md1", "$home/md2", "$home/md3", "$home/md4", "$home/md5", "$home/md0");
wr("$home/md1/runtime.json", '{"runtime_root":"/x","app_name":"a"}');
wr("$home/md2/runtime.json", 'not json');
wr("$home/md3/runtime.json", '[1,2]');
wr("$home/md4/runtime.json", 'null');
wr("$home/md5/runtime.json", '');
for my $d (qw(md0 md1 md2 md3 md4 md5 nosuchdir)) { my $r = $hk->_read_state_metadata("$home/$d"); print "meta($d)=", (defined $r ? json_encode($r) : 'undef'), "\n" }
# _state_root_is_stale
my $live = "$home/live_rt"; make_path($live);
my %roots = (
  young_nometa => [undef, 0], old_nometa => [undef, 5000], old_meta_gone => ['{"runtime_root":"/nonexistent/bq"}', 5000],
  old_meta_exists => [qq({"runtime_root":"$live"}), 5000], old_meta_empty => ['{"runtime_root":""}', 5000], old_meta_noroot => ['{"app_name":"x"}', 5000],
  old_meta_bad => ['garbage', 5000], young_meta_gone => ['{"runtime_root":"/nonexistent/bq"}', 0],
);
make_path("$home/roots");
for my $n (sort keys %roots) { my $d = "$home/roots/$n"; make_path($d); wr("$d/runtime.json", $roots{$n}[0]) if defined $roots{$n}[0]; age($d, $roots{$n}[1]); }
for my $n (sort keys %roots) { print "stale($n,3600)=", $hk->_state_root_is_stale("$home/roots/$n", 3600), " stale($n,0)=", $hk->_state_root_is_stale("$home/roots/$n", 0), "\n" }
print "stale_missing_dir=", $hk->_state_root_is_stale("$home/roots/nosuch", 0), "\n";
# live collectors: dead pid file and non-managed pid file
make_path("$home/roots/old_nometa/collectors");
wr("$home/roots/old_nometa/collectors/a.pid", "999999\n"); wr("$home/roots/old_nometa/collectors/b.pid", "notapid\n"); wr("$home/roots/old_nometa/collectors/c.pid", "$$\n"); wr("$home/roots/old_nometa/collectors/.pid", "$$\n"); wr("$home/roots/old_nometa/collectors/d.txt", "$$\n");
age("$home/roots/old_nometa", 5000);
print "live_nometa=", $hk->_state_root_has_live_collectors("$home/roots/old_nometa"), " stale=", $hk->_state_root_is_stale("$home/roots/old_nometa", 3600), "\n";
# _remove_tree
make_path("$home/rm1/sub"); wr("$home/rm1/sub/f", 'x');
show('rm_dry', scalar $hk->_remove_tree("$home/rm1", 'state-root', dry_run => 1));
print "rm1_after_dry=", (-d "$home/rm1" ? 1 : 0), "\n";
show('rm_real', scalar $hk->_remove_tree("$home/rm1", 'state-root'));
print "rm1_after_real=", (-d "$home/rm1" ? 1 : 0), "\n";
show('rm_missing', scalar $hk->_remove_tree("$home/rm_nosuch", 'x'));
# _cleanup_state_roots through the isolated state base
my $base = $paths->state_base_root; print "base=", norm($base), "\n";
for my $n (sort keys %roots) { my $d = "$base/$n"; make_path($d); wr("$d/runtime.json", $roots{$n}[0]) if defined $roots{$n}[0]; age($d, $roots{$n}[1]); }
make_path("$base/active_check");
my $active = $paths->_state_root_for_layer(($paths->runtime_layers)[0]); age($active, 5000);
for my $dry (1, 0) {
    my $scanned = { state_roots => 0 };
    my @r = $hk->_cleanup_state_roots(min_age_seconds => 3600, scanned => $scanned, dry_run => $dry);
    show("cleanup_dry$dry", [ sort { $a->{path} cmp $b->{path} } @r ]);
    show("scanned_dry$dry", $scanned);
    opendir my $dh, $base or die; my @left = sort grep { !/^\.\.?$/ } readdir $dh; closedir $dh;
    print "left_dry$dry=", join(',', map { /^[0-9a-f]{32}$/ ? 'HASH' : $_ } @left), "\n";
}
# run() summaries with huge min age so nothing else is touched
for my $dry (1, 0) {
    my $r = $hk->run(min_age_seconds => 1000000000, dry_run => $dry);
    delete $r->{happened_at};
    show("run_dry$dry", $r);
}
try('run_bad_age', sub { $hk->run(min_age_seconds => 'x') });
try('run_neg_age', sub { $hk->run(min_age_seconds => -1) });
try('run_float_age', sub { $hk->run(min_age_seconds => '1.5') });
# temp files
my $tmpdir = File::Spec->tmpdir;
my @mine = ("$tmpdir/dashboard-result-bq-$$", "$tmpdir/developer-dashboard-ajax-bq-$$", "$tmpdir/dashboard-result-bq-young-$$");
wr($_, 'x') for @mine; age($mine[0], 2000000000 - 0 > time ? 100 : time - 1000); age($mine[1], 1500000000 > time ? 100 : time - 1000);
my $sc = { ajax_temp_files => 0, result_temp_files => 0 };
my @cand = grep { /bq-/ } $hk->_temp_file_candidates;
print "cand_count=", scalar(@cand), "\n";
print "kinds=", join(';', map { join(',', $hk->_temp_file_kind($_)) } 'developer-dashboard-ajax-x', 'dashboard-result-y', 'other', 'xdashboard-result-', 'developer-dashboard-ajax-'), "\n";
unlink @mine;
# collector rotation merge
for my $job ({}, {rotation=>{a=>1}}, {rotations=>{b=>2}}, {rotation=>{a=>1,c=>1}, rotations=>{a=>9}}, {rotation=>'x', rotations=>[1]}) { show('rotation', scalar $hk->_collector_rotation($job)) }
