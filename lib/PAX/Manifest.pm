package PAX::Manifest;

our $VERSION = '0.014';

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use JSON::PP ();
use PAX::Compatibility;

use constant TARGET_PERL_FAMILY => '5.42.x';

sub new {
    my ($class, %args) = @_;
    return bless {
        capture => $args{capture},
    }, $class;
}

sub to_hash {
    my ($self) = @_;
    my $capture = $self->{capture} // {};
    my $runtime = $capture->{runtime} // {};
    my $config = $runtime->{config} // {};
    my $version = $runtime->{config_version} // '';
    my $baseline_match = $version =~ /^5\.42\./ ? 1 : 0;
    my $abi_stamp = _abi_stamp($runtime);
    my $compatibility = PAX::Compatibility->new(
        capture => $capture,
        baseline_match => $baseline_match,
    )->report;

    return {
        schema_version => 1,
        pax_version => '0.0.1',
        source_entrypoint => $capture->{source_entrypoint},
        runtime => {
            perl_version => $runtime->{perl_version},
            perl_config_version => $version,
            perl_family_target => TARGET_PERL_FAMILY,
            baseline_match => $baseline_match ? JSON::PP::true() : JSON::PP::false(),
            archname => $runtime->{archname},
            executable => $runtime->{executable},
            config => $config,
            pax_abi_stamp => $abi_stamp,
        },
        capture => {
            status => $capture->{status},
            mode => $capture->{mode},
        },
        module_graph => {
            modules => $capture->{capture}{loaded_files} // [],
        },
        package_state => {
            packages => $capture->{capture}{package_shapes} // {},
        },
        optree_units => {
            subs => $capture->{capture}{sub_optrees} // [],
        },
        lexical_pads => {
            subs => _sub_field_map($capture, 'pad_layout'),
        },
        closure_descriptors => {
            subs => _sub_field_map($capture, 'closure_descriptor'),
        },
        method_resolution => $capture->{capture}{method_resolution} // {},
        regex_metadata => $capture->{capture}{regex_metadata} // [],
        compile_phase_events => $capture->{capture}{compile_phase_events} // [],
        runtime_epochs => _initial_epochs($capture),
        source_features => $capture->{source_features} // {},
        compatibility => $compatibility,
        diagnostics => $capture->{diagnostics} // [],
    };
}

sub _sub_field_map {
    my ($capture, $field) = @_;
    my %map;
    for my $sub (@{ $capture->{capture}{sub_optrees} // [] }) {
        next if !defined $sub->{name};
        $map{ $sub->{name} } = $sub->{$field};
    }
    return \%map;
}

sub _abi_stamp {
    my ($runtime) = @_;
    my $config = $runtime->{config} // {};
    my $input = join "\n",
        map { $_ . '=' . (defined $config->{$_} ? $config->{$_} : '') }
        sort keys %$config;
    $input .= "\nversion=" . ($runtime->{config_version} // '');
    $input .= "\narchname=" . ($runtime->{archname} // '');
    return sha256_hex($input);
}

sub _initial_epochs {
    my ($capture) = @_;
    return {
        package_symbols => 0,
        method_resolution => 0,
        loaded_modules => scalar @{ $capture->{capture}{loaded_files} // [] },
        locale_mode => 0,
        unicode_mode => 0,
        regex_assumptions => 0,
        overload_tables => 0,
        eval_created_code => 0,
        interpreter_hooks => 0,
    };
}

1;
