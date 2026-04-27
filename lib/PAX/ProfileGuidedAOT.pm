package PAX::ProfileGuidedAOT;

our $VERSION = '0.011';

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use JSON::PP ();

sub new {
    my ($class, %args) = @_;
    return bless {
        threshold => $args{threshold} // 2,
    }, $class;
}

sub plan {
    my ($self, %args) = @_;
    my $manifest = $args{manifest} // {};
    my $ssa_units = $args{ssa_units} // [];
    my $profile = $args{profile} // {};
    my @artifacts;

    for my $unit (@$ssa_units) {
        my $name = $unit->{region_name} // $unit->{region_id};
        my $stats = $profile->{$name} // {};
        next if ($stats->{dispatches} // 0) < $self->{threshold};
        next if !$unit->{native_shape} && !$unit->{source}{native_shape};
        push @artifacts, {
            region_id => $unit->{region_id},
            region_name => $unit->{region_name},
            tier => 'tier-1',
            profile_dispatches => $stats->{dispatches},
            cache_key => sha256_hex(join "\0",
                $manifest->{runtime}{pax_abi_stamp} // '',
                $manifest->{source_entrypoint} // '',
                $unit->{region_id} // '',
                $stats->{dispatches} // 0,
            ),
        };
    }

    return {
        status => @artifacts ? 'planned' : 'no_hot_native_regions',
        threshold => $self->{threshold},
        artifacts => \@artifacts,
        provenance => {
            source_entrypoint => $manifest->{source_entrypoint},
            perl_abi_stamp => $manifest->{runtime}{pax_abi_stamp},
            capture_manifest_hash => sha256_hex(JSON::PP->new->canonical(1)->encode($manifest)),
        },
    };
}

1;
