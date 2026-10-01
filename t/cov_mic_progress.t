use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::CLI::Progress;

=pod

=head1 NAME

t/cov_mic_progress.t - behaviour tests for the build progress board

=head1 DESCRIPTION

Renders the progress board into in-memory streams in static, dynamic and
coloured modes and drives it through status updates, covering every status
prefix, colour and early-return branch.

=head1 WHY IT EXISTS

PAX::CLI::Progress was never loaded under Devel::Cover, and the project
requires full coverage of lib/.

=cut

# board(%args)
# Builds a progress board writing into a scalar. Input: constructor args.
# Output: the board and a reference to the captured output.
sub board {
    my (%args) = @_;
    my $out = '';
    open my $fh, '>', \$out or die $!;
    my $p = PAX::CLI::Progress->new(stream => $fh, %args);
    return ($p, \$out);
}

# ---------------------------------------------------------------- constructor
eval { PAX::CLI::Progress->new(tasks => 'x') };
like($@, qr/must be an array reference/, 'non-array tasks rejected');
eval { PAX::CLI::Progress->new(tasks => [{ label => 'no id' }], stream => \*STDOUT) };
like($@, qr/task missing id/, 'task without id rejected');

{
    my ($p, $out) = board();
    is($$out, "pax progress\n", 'empty board shows only the default title');
    is($p->{dynamic}, 0, 'static by default');
    is($p->{color}, 0, 'colourless by default');
}

{
    # Default stream is STDERR; redirect it so nothing leaks to the terminal.
    open my $saved, '>&', \*STDERR or die $!;
    my $err = '';
    close STDERR;
    open STDERR, '>', \$err or die $!;
    my $p = PAX::CLI::Progress->new;
    close STDERR;
    open STDERR, '>&', $saved or die $!;
    is($err, "pax progress\n", 'defaults to STDERR');
    is($p->{stream}, \*STDERR, 'stream default');
}

# ---------------------------------------------------------------- updates
{
    my ($p, $out) = board(title => 'T', tasks => [{ id => 'a', label => 'Alpha' }, { id => 'b' }, { id => 'c' }, { id => 'd' }]);
    is($$out, "T\n[ ] Alpha\n[ ] b\n[ ] c\n[ ] d\n", 'initial board');

    is($p->update(undef), 1, 'undef event ignored');
    is($p->update('x'), 1, 'non-hash event ignored');
    is($p->update({}), 1, 'event without task ignored');
    is($p->update({ task_id => 'zzz', status => 'done' }), 1, 'unknown task ignored');
    $p->update({ task_id => 'a', status => 'done' });
    $p->update({ task_id => 'b', status => 'running', label => 'Beta' });
    $p->update({ task_id => 'c', status => 'failed' });
    $p->update({ task_id => 'd', status => '', label => '' });
    $p->update({ task_id => 'd' });
    like($$out, qr/\[OK\] Alpha\n-> Beta\n\[X\] c\n\[ \] d\n$/, 'statuses rendered');
    is($p->{tasks}{d}{status}, 'pending', 'empty status ignored');
    is($p->{tasks}{d}{label}, 'd', 'empty label ignored');

    my $before = length $$out;
    $p->callback->({ task_id => 'd', status => 'done' });
    ok(length($$out) > $before, 'callback updates the board');
    is($p->{tasks}{d}{status}, 'done', 'callback applied the event');

    is($p->finish, 1, 'static finish does nothing');
    my $len = length $$out;
    $p->finish;
    is(length $$out, $len, 'static finish writes nothing');

    delete $p->{tasks}{b};
    unlike($p->render_text, qr/Beta/, 'task missing from the table is skipped');
}

# ---------------------------------------------------------------- dynamic and colour
{
    my ($p, $out) = board(dynamic => 1, color => 1, tasks => [{ id => 'a' }, { id => 'b' }, { id => 'c' }, { id => 'd' }]);
    $p->update({ task_id => 'a', status => 'done' });
    $p->update({ task_id => 'b', status => 'running' });
    $p->update({ task_id => 'c', status => 'failed' });
    like($$out, qr/\e\[32m\[OK\]\e\[0m a/, 'done is green');
    like($$out, qr/\e\[33m->\e\[0m b/, 'running is yellow');
    like($$out, qr/\e\[31m\[X\]\e\[0m c/, 'failed is red');
    like($$out, qr/\[ \] d/, 'pending is uncoloured');
    like($$out, qr/(?:\e\[1A\e\[2K){5}/, 'redraw erases the previous board');
    my $len = length $$out;
    $p->finish;
    is(substr($$out, $len), "\n", 'dynamic finish ends the line');

    my ($fresh, $fout) = board(dynamic => 1);
    $fresh->{rendered} = 0;
    $fresh->finish;
    is($$fout, "pax progress\n", 'dynamic finish before any render writes nothing');

    is($p->_status_prefix(undef), '[ ]', 'undef status prefix');
    is($p->_colorize('x', undef), 'x', 'undef status is uncoloured');
    is($p->_colorize('x', 'weird'), 'x', 'unknown status is uncoloured');
}

done_testing;
