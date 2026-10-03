# Differential fixture: CLI::Progress board rendering (plain and dynamic, colour, detail lines).
use strict; use warnings;
use Developer::Dashboard::CLI::Progress;
sub show { my ($l, $t) = @_; $t =~ s/\e/<E>/g; $t =~ s/\n/|/g; print "$l: $t\n"; }
my $P = 'Developer::Dashboard::CLI::Progress';
my @tasks = ({ id => 'a', label => 'Alpha' }, { id => 'b' }, { id => 'c', label => 'Gamma' });
for my $st (qw(pending running done failed bogus), undef) {
    show('prefix ' . ($st // 'undef'), $P->_status_prefix($st));
    for my $color (0, 1) {
        my $pr = bless { color => $color }, $P;
        show("colorize c=$color " . ($st // 'undef'), $pr->_colorize('X', $st));
        show("colorize_detail c=$color " . ($st // 'undef'), $pr->_colorize_detail('d', $st));
    }
}
for my $color (0, 1) {
    my $out = '';
    open my $fh, '>', \$out or die;
    my $p = $P->new(title => 'T', tasks => \@tasks, stream => $fh, color => $color);
    my $cb = $p->callback;
    $cb->({ task_id => 'a', status => 'running' });
    $cb->({ task_id => 'a', detail_line => 'line one' });
    $cb->({ task_id => 'a', detail_line => 'line two' });
    $cb->({ task_id => 'b', status => 'failed', label => 'Beta!', detail_lines => ['x', 'y', 'z'] });
    $cb->({ task_id => 'a', status => 'done' });
    $cb->({ task_id => 'nosuch', status => 'done' });
    $cb->({ status => 'done' });
    $cb->('notahash');
    $cb->(undef);
    $cb->({ add_tasks => [{ id => 'd', label => 'Delta' }, { id => 'a' }, 'junk', {}], task_id => 'd', status => 'running' });
    $cb->({ task_id => 'c', status => '', label => '' });
    $p->finish;
    show("static color=$color", $out);
}
for my $max (undef, 2, 0, 'abc') {
    my $out = '';
    open my $fh, '>', \$out or die;
    my $p = $P->new(title => 'Dyn', tasks => \@tasks, stream => $fh, dynamic => 1, color => 1, max_detail_lines => $max);
    $p->update({ task_id => 'a', status => 'running', detail_lines => [map {"d$_"} 1 .. 5] });
    $p->update({ task_id => 'a', detail_line => 'more' });
    $p->update({ task_id => 'b', status => 'done' });
    $p->finish;
    show('dynamic max=' . ($max // 'undef'), $out);
    show('render_text', $p->render_text);
}
{
    my $out = '';
    open my $fh, '>', \$out or die;
    my $p = $P->new(tasks => [], stream => $fh, dynamic => 1);
    $p->finish;
    show('empty finish', $out);
    $p->add_tasks('nope');
    $p->add_tasks([]);
    show('empty out', $out);
}
for my $bad ('str', [{ label => 'noid' }]) {
    eval { $P->new(tasks => $bad) };
    my $e = $@; $e =~ s/ at .*//s;
    print "new error: $e\n";
}
