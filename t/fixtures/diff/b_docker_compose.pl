use strict; use warnings;
use File::Path qw(make_path remove_tree);
use Developer::Dashboard::PathRegistry;
use Developer::Dashboard::Config;
use Developer::Dashboard::DockerCompose;
use Developer::Dashboard::JSON qw(json_encode);
my $home = $ENV{HOME};
sub norm { my $s = shift; $s =~ s/\Q$home\E/HOME/g; $s }
sub show { my ($l,$v)=@_; print "$l=", norm(defined $v ? (ref $v ? json_encode($v) : "'$v'") : 'undef'), "\n"; }
sub try { my ($l,$c)=@_; my @r = eval { $c->() }; my $e=$@; $e =~ s/ at .* line \d+.*//s; $e = norm($e); $e =~ s/\n/\\n/g; print "$l: ", ($e ne '' ? "died($e)" : 'ok'), "\n"; return @r }
my $proj = "$home/work/proj"; make_path("$proj/.developer-dashboard");
my %dc;
for my $mode (qw(home deep)) {
    my $paths = Developer::Dashboard::PathRegistry->new(home => $home, cwd => ($mode eq 'home' ? $home : $proj));
    my $cfg = Developer::Dashboard::Config->for_paths($paths);
    $dc{$mode} = Developer::Dashboard::DockerCompose->new(config => $cfg, paths => $paths);
}
# env path expansion
$ENV{BQ_A} = 'alpha'; $ENV{BQ_B} = '$BQ_A'; $ENV{BQ_C} = '${BQ_A}'; $ENV{BQ_E} = ''; delete $ENV{BQ_UNSET};
for my $p (undef, '', '/plain', '$BQ_A/x', '${BQ_A}/x', '$BQ_B', '${BQ_B}', '$BQ_C', '${BQ_C}/$BQ_A', '$BQ_UNSET/x', '${BQ_UNSET}', '$BQ_E.yml', '$1x', '$', '${', '${}', '${BQ_A', '$BQ_A$BQ_A', '$$BQ_A', '\\$BQ_A', '${BQ_A}${BQ_B}', '$BQ_AB', '${BQ_A}B', '$_x', '${ BQ_A }', '$BQ-A', '0') {
    my $r = $dc{home}->_expand_env_path($p); print "expand(", (defined $p ? "'$p'" : 'undef'), ")=", (defined $r ? "'$r'" : 'undef'), "\n";
}
for my $mode (qw(home deep)) {
    my $d = $dc{$mode};
    print "[$mode]\n";
    show('docker_root', scalar $d->_docker_config_root);
    show('home_docker_root', scalar $d->_home_docker_config_root);
    show('toggle_root', scalar $d->_service_toggle_root);
    show('toggle_root_args', scalar $d->_service_toggle_root(project_root => '/x'));
    show('disabled_none', scalar $d->_service_folder_is_disabled(service => 'bqsvc'));
    show('disabled_noservice', scalar $d->_service_folder_is_disabled());
    show('disabled_emptyservice', scalar $d->_service_folder_is_disabled(service => ''));
    show('marker', scalar $d->_service_disabled_marker_path(service => 'bqsvc'));
    show('marker_nested', scalar $d->_service_disabled_marker_path(service => 'a/b'));
    show('marker_dots', scalar $d->_service_disabled_marker_path(service => './a//b/../c/'));
    show('marker_escape', scalar $d->_service_disabled_marker_path(service => '../evil'));
    show('marker_escape2', scalar $d->_service_disabled_marker_path(service => 'a/../../evil'));
    show('marker_only_dots', scalar $d->_service_disabled_marker_path(service => '..'));
    show('marker_backslash', scalar $d->_service_disabled_marker_path(service => 'a\\..\\..\\b'));
    try('marker_noservice', sub { $d->_service_disabled_marker_path() });
    try('disable_noservice', sub { $d->disable_service() });
    try('enable_noservice', sub { $d->enable_service() });
    try('disable_escape', sub { show('r', scalar $d->disable_service(service => '../evil')) });
    try('enable_escape', sub { show('r', scalar $d->enable_service(service => '../evil')) });
    try('disable_dot', sub { show('r', scalar $d->disable_service(service => '.')) });
    try('disable_empty', sub { show('r', scalar $d->disable_service(service => '')) });
    show('enable_before', scalar $d->enable_service(service => 'bqsvc'));
    show('disable', scalar $d->disable_service(service => 'bqsvc'));
    my $m = $d->_service_disabled_marker_path(service => 'bqsvc');
    print "marker_exists=", (-f $m ? 1 : 0), "\n";
    open my $fh, '<', $m or die; local $/; my $c = <$fh>; close $fh; $c =~ s/\n/\\n/g; print "marker_content=$c\n";
    show('disabled_after', scalar $d->_service_folder_is_disabled(service => 'bqsvc'));
    show('disabled_after_args', scalar $d->_service_folder_is_disabled(service => 'bqsvc', project_root => '/nonexistent'));
    show('disable_nested', scalar $d->disable_service(service => 'n1/n2'));
    show('disabled_nested', scalar $d->_service_folder_is_disabled(service => 'n1/n2'));
    show('disable_traverse_inside', scalar $d->disable_service(service => 'a/../ok'));
    show('list', scalar $d->list_services());
    show('enable', scalar $d->enable_service(service => 'bqsvc'));
    print "marker_exists_after=", (-f $m ? 1 : 0), "\n";
    show('disabled_after_enable', scalar $d->_service_folder_is_disabled(service => 'bqsvc'));
    show('enable_again', scalar $d->enable_service(service => 'bqsvc'));
    $d->enable_service(service => $_) for qw(n1/n2 ok);
}
remove_tree("$home/.developer-dashboard/config/docker", "$proj/.developer-dashboard/config", "$proj/.developer-dashboard/docker");
