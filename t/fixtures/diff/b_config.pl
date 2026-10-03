use strict; use warnings;
use File::Path qw(make_path);
use Developer::Dashboard::PathRegistry;
use Developer::Dashboard::Config;
use Developer::Dashboard::JSON qw(json_encode json_decode);
sub show { my ($l,$v)=@_; local $@; print "$l=", (defined $v ? json_encode($v) : 'undef'), "\n"; }
sub try { my ($l,$c)=@_; my @r = eval { $c->() }; my $e=$@; $e =~ s/ at .* line \d+.*//s; print "$l: ", ($e ne '' ? "died($e)" : 'ok'), "\n"; return @r }
my $home = $ENV{HOME};
my $paths = Developer::Dashboard::PathRegistry->new(home => $home);
my $cfg = Developer::Dashboard::Config->for_paths($paths);
show('merge_non_hash_l', scalar $cfg->_merge_named_hash_item('a', {x=>1}));
show('merge_non_hash_r', scalar $cfg->_merge_named_hash_item({x=>1}, 'b'));
show('merge_undef', scalar $cfg->_merge_named_hash_item(undef, undef));
show('merge_hashes', scalar $cfg->_merge_named_hash_item({a=>1,n=>{p=>1}}, {b=>2,n=>{q=>2}}));
show('merge_override', scalar $cfg->_merge_named_hash_item({a=>1}, {a=>2}));
show('empty_global_paths', scalar $cfg->global_path_aliases);
show('empty_global_files', scalar $cfg->global_file_aliases);
show('workers_default', scalar $cfg->web_workers);
show('settings_default', scalar $cfg->web_settings);
try('workers_undef', sub { $cfg->save_global_web_workers(undef) });
try('workers_empty', sub { $cfg->save_global_web_workers('') });
try('workers_zero', sub { $cfg->save_global_web_workers(0) });
try('workers_neg', sub { $cfg->save_global_web_workers(-3) });
try('workers_alpha', sub { $cfg->save_global_web_workers('x') });
try('workers_float', sub { $cfg->save_global_web_workers('2.5') });
show('workers_ok', scalar $cfg->save_global_web_workers('3'));
show('workers_after', scalar $cfg->web_workers);
show('workers_ok_lead0', scalar $cfg->save_global_web_workers('007'));
show('workers_after2', scalar $cfg->web_workers);
for my $bad (['host',''],['port','abc'],['port',0],['port',70000],['port','65535'],['workers','x'],['workers',0],['workers','4']) {
    my @r = try("settings_$bad->[0]_$bad->[1]", sub { my $r = $cfg->save_global_web_settings($bad->[0] => $bad->[1]); show("  res", $r); });
}
show('settings_all', scalar $cfg->save_global_web_settings(host=>'127.0.0.1', port=>'8080', workers=>'2', ssl=>'yes', no_editor=>0, no_indicators=>1, ssl_subject_alt_names=>[' a.test ', undef, '', {}, 'b.test', '  ']));
show('settings_san_nonarray', scalar $cfg->save_global_web_settings(ssl_subject_alt_names=>'x'));
show('settings_san_undef', scalar $cfg->save_global_web_settings(ssl_subject_alt_names=>undef));
show('settings_none', scalar $cfg->save_global_web_settings());
show('settings_now', scalar $cfg->web_settings);
show('workers_now', scalar $cfg->web_workers);
show('san_norm', scalar $cfg->_normalize_ssl_subject_alt_names([' x ', 'y']));
# defaults merge
show('defaults_ret', scalar $cfg->save_global_defaults({web=>{port=>1111, extra=>1}, newkey=>'n', collectors=>[]}));
show('global_after_defaults', scalar $cfg->load_global);
show('defaults_undef', scalar $cfg->save_global_defaults());
show('global_after_defaults2', scalar $cfg->load_global);
# aliases in global config
my $dir = "$home/projx"; make_path($dir);
$cfg->save_global({ path_aliases => { proj => $dir, home => '~', rel => '$HOME/zz' }, file_aliases => { f1 => "$dir/f.txt", bad => [] }, web=>{workers=>'abc', ssl_validity_days=>400} });
my $gp = $cfg->global_path_aliases; $gp = { map { $_ => do { my $v=$gp->{$_}; $v =~ s/\Q$home\E/HOME/g; $v } } keys %$gp };
show('global_paths', $gp);
my $gf = $cfg->global_file_aliases; $gf = { map { my $v=$gf->{$_}; $v = ref($v) ? 'REF' : $v; $v =~ s/\Q$home\E/HOME/g; ($_ => $v) } keys %$gf };
show('global_files', $gf);
show('workers_bad_cfg', scalar $cfg->web_workers);
my $s = $cfg->web_settings; show('settings_bad_cfg', $s);
$cfg->save_global({ path_aliases => 'str', file_aliases => 5, web=>{workers=>0}});
show('global_paths_bad', scalar $cfg->global_path_aliases);
show('global_files_bad', scalar $cfg->global_file_aliases);
show('workers_zero_cfg', scalar $cfg->web_workers);
$cfg->save_global({ web=>{workers=>'5'} });
show('workers_5', scalar $cfg->web_workers);
$cfg->save_global({ web=>{workers=>'5.5'} });
show('workers_55', scalar $cfg->web_workers);
$cfg->save_global({ web=>'str' });
try('workers_webstr', sub { show('w', scalar $cfg->web_workers) });
try('save_workers_webstr', sub { show('w', scalar $cfg->save_global_web_workers(2)) });
show('final', scalar $cfg->load_global);
