# Differential fixture: runs identically under stock Perl and the PAX binary.
# Contract: print deterministic text only (sort keys, no addresses, no timestamps, no pids).
use strict; use warnings;
use Developer::Dashboard::Runtime::Result;
my @names = eval { Developer::Dashboard::Runtime::Result->names };
print "names=", join(",", @names), "\n";
print "err=", ($@ ? 'yes' : 'no'), "\n";
