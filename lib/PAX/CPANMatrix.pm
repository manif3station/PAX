package PAX::CPANMatrix;

our $VERSION = '0.010';

use strict;
use warnings;
use JSON::PP qw(decode_json);
use IPC::Open3;
use Symbol qw(gensym);
use PAX::Capture;
use PAX::Manifest;

sub new {
    my ($class, %args) = @_;
    return bless {
        manifest_path => $args{manifest_path},
        perl => $args{perl} // $^X,
    }, $class;
}

sub run {
    my ($self) = @_;
    my $manifest = $self->_load_manifest;
    my @results;
    for my $dist (@{ $manifest->{distributions} // [] }) {
        push @results, $self->_run_distribution($dist);
    }
    my $failed = grep { !$_->{passed} } @results;
    return {
        suite => 'cpan_distribution_matrix',
        manifest_path => $self->{manifest_path},
        perl => $self->{perl},
        total => scalar @results,
        failed => $failed,
        passed => $failed ? JSON::PP::false() : JSON::PP::true(),
        results => \@results,
    };
}

sub _run_distribution {
    my ($self, $dist) = @_;
    my @modules;
    for my $module (@{ $dist->{modules} // [] }) {
        push @modules, $self->_run_module($module);
    }
    my @fixtures;
    for my $fixture (@{ $dist->{fixtures} // [] }) {
        push @fixtures, $self->_run_fixture($fixture);
    }
    my @level_checks;
    for my $expected (@{ $dist->{expected_levels} // [] }) {
        push @level_checks, {
            level => $expected,
            passed => _level_present($expected, \@fixtures) ? JSON::PP::true() : JSON::PP::false(),
        };
    }
    my $declared_xs = $dist->{declared_xs} // [];
    my $failed = (grep { !$_->{passed} } @modules) + (grep { !$_->{passed} } @fixtures);
    $failed += grep { !$_->{passed} } @level_checks;
    return {
        distribution => $dist->{distribution},
        source => $dist->{source} // 'installed',
        compatibility_class => $dist->{compatibility_class},
        declared_xs => $declared_xs,
        expected_levels => $dist->{expected_levels} // [],
        level_checks => \@level_checks,
        modules => \@modules,
        fixtures => \@fixtures,
        passed => $failed ? JSON::PP::false() : JSON::PP::true(),
    };
}

sub _run_module {
    my ($self, $module) = @_;
    my $code = 'no strict "refs"; my $m = shift; print(defined ${$m . "::VERSION"} ? ${$m . "::VERSION"} : "unknown", "\n")';
    my ($stdout, $stderr, $exit) = _run($self->{perl}, '-M' . $module, '-e', $code, $module);
    return {
        module => $module,
        exit => $exit,
        version => $exit == 0 ? _trim($stdout) : undef,
        stderr => $stderr,
        passed => $exit == 0 ? JSON::PP::true() : JSON::PP::false(),
    };
}

sub _run_fixture {
    my ($self, $fixture) = @_;
    my $capture = PAX::Capture->new(mode => 'live')->capture($fixture);
    my $manifest = PAX::Manifest->new(capture => $capture)->to_hash;
    return {
        path => $fixture,
        capture_status => $capture->{status},
        compatibility_level => $manifest->{compatibility}{level},
        reason => $manifest->{compatibility}{reason},
        passed => ($capture->{status} // '') eq 'ok' ? JSON::PP::true() : JSON::PP::false(),
    };
}

sub _load_manifest {
    my ($self) = @_;
    open my $fh, '<', $self->{manifest_path} or die "cannot read CPAN matrix manifest $self->{manifest_path}: $!";
    local $/;
    return decode_json(<$fh>);
}

sub _run {
    my (@cmd) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, @cmd);
    close $in;
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$err> // '';
    waitpid($pid, 0);
    return ($stdout, $stderr, $? >> 8);
}

sub _trim {
    my ($value) = @_;
    $value //= '';
    $value =~ s/\A\s+//;
    $value =~ s/\s+\z//;
    return $value;
}

sub _level_present {
    my ($expected, $fixtures) = @_;
    return 1 if !@$fixtures;
    for my $fixture (@$fixtures) {
        return 1 if ($fixture->{compatibility_level} // '') eq $expected;
    }
    return 0;
}

1;
