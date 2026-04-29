package PAX::Mode;

our $VERSION = '0.016';

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
