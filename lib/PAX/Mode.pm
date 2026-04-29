package PAX::Mode;

our $VERSION = '0.024';

use strict;
use warnings;

sub policy {
    my ($class, $mode) = @_;
    $mode //= 'dev';
    my %policies = (
        dev => {
            explainability => 'max',
            cache_persistence => 'low',
            undeclared_inputs => 'warn',
            telemetry => 'verbose',
        },
        ci => {
            explainability => 'structured',
            cache_persistence => 'content-addressed',
            undeclared_inputs => 'fail',
            telemetry => 'strict',
        },
        prod => {
            explainability => 'summary',
            cache_persistence => 'persistent',
            undeclared_inputs => 'record',
            telemetry => 'low_overhead',
        },
    );
    return $policies{$mode} // $policies{dev};
}

1;

=pod

=head1 NAME

PAX::Mode - document the Mode component within the PAX compiler, packaging, or runtime stack.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to document the Mode component within the PAX compiler, packaging, or runtime stack.

=cut

