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

=pod

=head1 NAME

t/fixtures/dynamic.pl - provide the dynamic fixture used by the PAX test suite.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to provide the dynamic fixture used by the PAX test suite.

=cut

