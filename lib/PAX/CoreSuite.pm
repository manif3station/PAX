package PAX::CoreSuite;

our $VERSION = '0.009';

use strict;
use warnings;
use JSON::PP qw(decode_json);
use IPC::Open3;
use Symbol qw(gensym);

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
    for my $case (@{ $manifest->{cases} // [] }) {
        push @results, $self->_run_case($case);
    }
    my $failed = grep { !$_->{passed} } @results;
    return {
        suite => 'perl_core_regression',
        manifest_path => $self->{manifest_path},
        perl => $self->{perl},
        total => scalar @results,
        failed => $failed,
        passed => $failed ? JSON::PP::false() : JSON::PP::true(),
        results => \@results,
    };
}

sub _run_case {
    my ($self, $case) = @_;
    my @cmd = ($self->{perl}, @{ $case->{argv} // [] });
    my ($stdout, $stderr, $exit) = _run(@cmd);
    return {
        id => $case->{id},
        description => $case->{description},
        command => \@cmd,
        exit => $exit,
        stdout => $stdout,
        stderr => $stderr,
        passed => $exit == 0 ? JSON::PP::true() : JSON::PP::false(),
    };
}

sub _load_manifest {
    my ($self) = @_;
    open my $fh, '<', $self->{manifest_path} or die "cannot read core suite manifest $self->{manifest_path}: $!";
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

1;
