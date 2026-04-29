package PAX::InlineCache;

our $VERSION = '0.014';

use strict;
use warnings;
use JSON::PP ();

sub new {
    my ($class, %args) = @_;
    return bless {
        max_polymorphic => $args{max_polymorphic} // 4,
        sites => {},
    }, $class;
}

sub lookup {
    my ($self, %args) = @_;
    my $site = $args{site} // 'default';
    my $class_key = $args{class_key} // 'main';
    my $method = $args{method} // $args{region_name} // '';
    my $slot = $self->{sites}{$site};
    return {
        status => 'miss',
        site => $site,
        class_key => $class_key,
        method => $method,
    } if !$slot;

    for my $entry (@{ $slot->{entries} }) {
        next if $entry->{class_key} ne $class_key || $entry->{method} ne $method;
        $entry->{hits}++;
        return {
            status => $slot->{megamorphic} ? 'megamorphic' : 'hit',
            site => $site,
            class_key => $class_key,
            method => $method,
            target_region_id => $entry->{target_region_id},
            target_region_name => $entry->{target_region_name},
            hits => $entry->{hits},
            entry_count => scalar @{ $slot->{entries} },
        };
    }

    return {
        status => $slot->{megamorphic} ? 'megamorphic' : 'miss',
        site => $site,
        class_key => $class_key,
        method => $method,
        entry_count => scalar @{ $slot->{entries} },
    };
}

sub update {
    my ($self, %args) = @_;
    my $site = $args{site} // 'default';
    my $class_key = $args{class_key} // 'main';
    my $method = $args{method} // $args{region_name} // '';
    my $slot = $self->{sites}{$site} ||= {
        entries => [],
        megamorphic => JSON::PP::false(),
    };

    for my $entry (@{ $slot->{entries} }) {
        next if $entry->{class_key} ne $class_key || $entry->{method} ne $method;
        $entry->{target_region_id} = $args{target_region_id};
        $entry->{target_region_name} = $args{target_region_name};
        return $self->lookup(site => $site, class_key => $class_key, method => $method);
    }

    push @{ $slot->{entries} }, {
        class_key => $class_key,
        method => $method,
        target_region_id => $args{target_region_id},
        target_region_name => $args{target_region_name},
        hits => 0,
    };
    $slot->{megamorphic} = JSON::PP::true()
        if @{ $slot->{entries} } > $self->{max_polymorphic};

    return {
        status => $slot->{megamorphic} ? 'megamorphic' : 'updated',
        site => $site,
        class_key => $class_key,
        method => $method,
        entry_count => scalar @{ $slot->{entries} },
    };
}

sub report {
    my ($self) = @_;
    return {
        max_polymorphic => $self->{max_polymorphic},
        sites => $self->{sites},
    };
}

1;
