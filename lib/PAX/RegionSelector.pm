package PAX::RegionSelector;

our $VERSION = '0.019';

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {
        manifest => $args{manifest},
    }, $class;
}

sub select {
    my ($self) = @_;
    my $manifest = $self->{manifest} // {};
    my $subs = $manifest->{optree_units}{subs} // [];
    my @regions;
    my @rejections;
    my $index = 0;

    for my $sub (@$subs) {
        my $name = $sub->{name} // next;
        next if $name =~ /^(main::BEGIN|main::UNITCHECK|main::CHECK|main::INIT)$/;
        next if !_is_application_sub($manifest, $sub);

        if (!$sub->{available}) {
            push @rejections, _reject($name, 'optree_unavailable', $sub->{reason});
            next;
        }

        my $kind = _classify_sub($name);
        my $support = _support_level($manifest, $kind);
        my $id = sprintf 'region-%04d', ++$index;
        push @regions, {
            id => $id,
            name => $name,
            kind => $kind,
            support_level => $support->{level},
            reason => $support->{reason},
            source => {
                entrypoint => $manifest->{source_entrypoint},
                root_class => $sub->{root_class},
                start_class => $sub->{start_class},
                optree_ops => $sub->{optree_ops} // [],
                native_shape => $sub->{native_shape},
            },
            required_epochs => [qw(package_symbols method_resolution loaded_modules)],
            lowering_status => $support->{level} eq 'fallback' ? 'blocked' : 'ready',
        };
    }

    return {
        selected => \@regions,
        rejected => \@rejections,
    };
}

sub _classify_sub {
    my ($name) = @_;
    return 'compile_phase_hook' if $name =~ /::(?:BEGIN|UNITCHECK|CHECK|INIT)$/;
    return 'candidate_leaf_function';
}

sub _is_application_sub {
    my ($manifest, $sub) = @_;
    my $name = $sub->{name} // '';
    my $file = $sub->{closure_descriptor}{file} // '';
    return 0 if $name =~ /^main::_/;
    return 0 if $name =~ /^main::(?:encode_json|decode_json|svref_2object)$/;
    return 1 if $name =~ /^main::/;
    return 1 if $name =~ /^PAX::Fixture::/;
    return 0 if !$file || $file eq '-';
    return 0 if $file !~ /\.(?:pm|pl)\z/;
    return 1 if $sub->{native_shape};
    return 0 if $file =~ m{\A(?:/usr|/System/|[A-Za-z]:/Strawberry/perl/)};
    return 1 if ($manifest->{source_entrypoint} // '') ne '' && $file eq $manifest->{source_entrypoint};
    return 1 if $file !~ m{\A/};
    return 0;
}

sub _support_level {
    my ($manifest, $kind) = @_;
    if (!$manifest->{runtime}{baseline_match}) {
        return {
            level => 'guarded',
            reason => 'runtime baseline mismatch requires guarded portable native packaging',
        };
    }
    return {
        level => 'guarded',
        reason => "$kind can enter HIR with runtime guards",
    };
}

sub _reject {
    my ($name, $code, $detail) = @_;
    return {
        name => $name,
        code => $code,
        detail => defined $detail ? $detail : '',
    };
}

1;
