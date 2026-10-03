# Differential fixture: usage strings and error helpers of CLI::Source, CLI::Upgrade and CLI::Skills plus Source file listing.
use strict; use warnings;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Developer::Dashboard::CLI::Source;
use Developer::Dashboard::CLI::Upgrade;
use Developer::Dashboard::CLI::Skills;
$| = 1;
my $home = tempdir(CLEANUP => 1);
sub clean { my $m = shift; $m =~ s/\Q$home\E/HOME/g; $m =~ s/ at (?:PAX::StandaloneRuntime op \w+|\S+) line \d+\.?//g; $m =~ s/\n/ /g; return $m; }
sub try { my ($l, $c) = @_; my @r = eval { $c->() }; print "$l: ", ($@ ? 'died ' . clean($@) : join(' | ', map { defined $_ ? clean($_) : 'undef' } @r)), "\n"; }
try('source usage', sub { Developer::Dashboard::CLI::Source::_usage() });
try('upgrade usage', sub { Developer::Dashboard::CLI::Upgrade::_usage() });
try('skills usage_error', sub { my $rc = Developer::Dashboard::CLI::Skills::_usage_error("bad thing\n"); "rc=$rc" });
try('skills usage_error empty', sub { my $rc = Developer::Dashboard::CLI::Skills::_usage_error(''); "rc=$rc" });
make_path("$home/perl5/lib/A", "$home/perl5/bin");
for my $f ("perl5/lib/A/B.pm", "perl5/lib/z.pl", "perl5/bin/tool") { open my $o, '>', "$home/$f" or die; print {$o} "x"; close $o; }
for my $a ([], ['--files'], ['--nofiles'], ['--bogus'], ['--files', 'extra']) {
    my $out = '';
    try("source @$a", sub { my $rc = Developer::Dashboard::CLI::Source::run_source_command(command => 'source', args => [@$a], home => $home, out => \$out); "rc=$rc out=" . join('~', split /\n/, $out) });
}
try('source wrong command', sub { Developer::Dashboard::CLI::Source::run_source_command(command => 'other', args => ['--files'], home => $home) });
try('source no command', sub { Developer::Dashboard::CLI::Source::run_source_command(args => []) });
try('source no args', sub { Developer::Dashboard::CLI::Source::run_source_command(command => 'source') });
try('source bad args', sub { Developer::Dashboard::CLI::Source::run_source_command(command => 'source', args => 'x') });
try('source empty home', sub { my $out = ''; Developer::Dashboard::CLI::Source::run_source_command(command => 'source', args => ['--files'], home => "$home/none", out => \$out); "out=[$out]" });
{
    my $out = '';
    open my $fh, '>', \$out or die;
    try('source filehandle', sub { Developer::Dashboard::CLI::Source::run_source_command(command => 'source', args => ['--files'], home => $home, out => $fh); close $fh; join '~', split /\n/, $out });
}
for my $a (['--bogus'], ['x'], ['--dry-run', 'x']) {
    try("upgrade @$a", sub { Developer::Dashboard::CLI::Upgrade::run_upgrade(command => 'upgrade', args => [@$a], dry_run_only => 1) });
}
for my $a ([], ['bogus'], ['install'], ['install', '--bogus'], ['uninstall'], ['enable'], ['disable']) {
    try("skills @$a", sub { my $rc = Developer::Dashboard::CLI::Skills::run_skills_command(command => 'skills', args => [@$a]); "rc=$rc" });
}
try('skills wrong command', sub { Developer::Dashboard::CLI::Skills::run_skills_command(command => 'nope', args => []) });
