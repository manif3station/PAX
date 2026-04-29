package PAX::Backend::Tier2LLVM;
our $VERSION = '0.014';

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Spec;

sub new {
    my ($class, %args) = @_;
    return bless {
        enabled => exists $args{enabled} ? ($args{enabled} ? 1 : 0) : 1,
        out_dir => $args{out_dir} // '.pax/native',
    }, $class;
}

sub metadata {
    my ($self) = @_;
    return {
        tier => 2,
        name => 'llvm-optimising-backend',
        role => 'optimising_aot_jit_backend',
        status => $self->{enabled} ? 'enabled' : 'disabled_by_configuration',
        contract => 'guarded_ssa_to_llvm_ir_module_emission',
    };
}

sub emit_module {
    my ($self, $ssa_unit) = @_;
    return {
        status => 'disabled',
        reason => 'LLVM backend disabled by configuration',
    } if !$self->{enabled};

    my $module = $self->module_for($ssa_unit);
    return $module if ($module->{status} // '') ne 'llvm_ir';

    make_path($self->{out_dir});
    my $id = sha256_hex(join "\n",
        $ssa_unit->{region_id} // '',
        $ssa_unit->{region_name} // '',
        $module->{ir},
    );
    my $path = File::Spec->catfile($self->{out_dir}, "$id.ll");
    open my $fh, '>', $path or return {
        status => 'fallback',
        reason => "cannot write LLVM IR module: $!",
    };
    print {$fh} $module->{ir};
    close $fh;

    return {
        status => 'llvm_ir_artifact',
        path => $path,
        module_id => $id,
        entry_symbol => 'pax_region_i64',
        reason => $module->{reason},
    };
}

sub module_for {
    my ($self, $ssa_unit) = @_;
    my $shape = $ssa_unit->{native_shape} // $ssa_unit->{source}{native_shape} // {};
    my $region_id = $ssa_unit->{region_id} // 'unknown';
    my $region_name = $ssa_unit->{region_name} // 'unknown';

    if (($shape->{kind} // '') eq 'i64_binary_leaf') {
        my $op = $shape->{op} // '';
        my $body = _llvm_binary_body($op);
        return _module($region_id, $region_name, $body, "LLVM IR emitted for guarded i64 $op leaf");
    }

    if (($shape->{kind} // '') eq 'i64_sum_loop') {
        return _module($region_id, $region_name, _llvm_sum_loop_body(), 'LLVM IR emitted for guarded i64 sum loop');
    }

    return {
        status => 'fallback',
        reason => 'no LLVM lowering for this guarded SSA shape',
    };
}

sub _module {
    my ($region_id, $region_name, $body, $reason) = @_;
    my $escaped_region_id = $region_id;
    $escaped_region_id =~ s/\\/\\\\/g;
    $escaped_region_id =~ s/"/\\"/g;
    my $escaped_region_name = $region_name;
    $escaped_region_name =~ s/\\/\\\\/g;
    $escaped_region_name =~ s/"/\\"/g;
    return {
        status => 'llvm_ir',
        reason => $reason,
        ir => <<"LLVM",
; PAX Tier 2 LLVM module
; region_id: $escaped_region_id
; region_name: $escaped_region_name
target triple = "unknown-unknown-unknown"

define i64 \@pax_region_i64(i64 %left, i64 %right) {
$body
}

define i64 \@pax_region_probe() {
entry:
  %probe = call i64 \@pax_region_i64(i64 2, i64 3)
  ret i64 %probe
}
LLVM
    };
}

sub _llvm_binary_body {
    my ($op) = @_;
    return <<"LLVM" if $op eq 'add';
entry:
  %result = add nsw i64 %left, %right
  ret i64 %result
LLVM
    return <<"LLVM" if $op eq 'subtract';
entry:
  %result = sub nsw i64 %left, %right
  ret i64 %result
LLVM
    return <<"LLVM" if $op eq 'multiply';
entry:
  %result = mul nsw i64 %left, %right
  ret i64 %result
LLVM
    return <<"LLVM" if $op eq 'greater_than';
entry:
  %cmp = icmp sgt i64 %left, %right
  %result = zext i1 %cmp to i64
  ret i64 %result
LLVM
    return <<"LLVM";
entry:
  ret i64 0
LLVM
}

sub _llvm_sum_loop_body {
    return <<'LLVM';
entry:
  %non_positive = icmp sle i64 %left, 0
  br i1 %non_positive, label %done_zero, label %loop

loop:
  %i = phi i64 [ 1, %entry ], [ %next_i, %loop ]
  %sum = phi i64 [ 0, %entry ], [ %next_sum, %loop ]
  %next_sum = add nsw i64 %sum, %i
  %next_i = add nsw i64 %i, 1
  %again = icmp sle i64 %next_i, %left
  br i1 %again, label %loop, label %done_sum

done_zero:
  ret i64 0

done_sum:
  ret i64 %next_sum
LLVM
}

1;
