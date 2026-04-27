package PAX::DeoptEngine;

our $VERSION = '0.010';

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {}, $class;
}

sub reconstruct {
    my ($self, %args) = @_;
    my $ssa_unit = $args{ssa_unit} // {};
    my $reason = $args{reason} // 'guard_failed';
    my $guard = $args{guard} // {};
    my $interpreter_result = $args{interpreter_result};
    my $args_value = $args{args} // [];
    my $context = $args{context} // 'scalar';
    my $deopt = $ssa_unit->{deopt} // {};

    return {
        status => 'reconstructed',
        region_id => $ssa_unit->{region_id},
        region_name => $ssa_unit->{region_name},
        reason => $reason,
        guard_id => $guard->{guard_id},
        invalidation_key => $guard->{invalidation_key},
        continuation => $deopt->{safepoint},
        frame => {
            argv => [@$args_value],
            wantarray => _wantarray_for_context($context),
            lexicals => $args{lexicals} // {},
            closure_environment => $args{closure_environment} // {},
            exception_handlers => $args{exception_handlers} // [],
            exception_state => $args{exception_state},
            caller => $args{caller},
            debugger_stack => $args{debugger_stack} // [],
        },
        materialised => $deopt->{materialise} // [],
        interpreter_result => $interpreter_result,
    };
}

sub _wantarray_for_context {
    my ($context) = @_;
    return undef if !defined $context || $context eq 'void';
    return 1 if $context eq 'list';
    return 0;
}

1;
