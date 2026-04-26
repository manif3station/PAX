use strict;
use warnings;

our $AUTOLOAD;

sub AUTOLOAD {
    return "autoloaded";
}

my $code = '1 + 1';
my $result = eval "$code";
die "bad eval" unless $result == 2;
1;
