# Differential fixture: sandpit helper names must exist only inside generated sandpit packages, not on PageRuntime itself.
use strict; no warnings;
use Developer::Dashboard::PageRuntime;
for my $n (qw(stash hide void stop params __add_error __errors __initial_context __run_code)) {
  print "$n: ", (Developer::Dashboard::PageRuntime->can($n) ? 'defined' : 'absent'), " ", (defined &{"Developer::Dashboard::PageRuntime::$n"} ? 'sub' : 'nosub'), "\n";
}
