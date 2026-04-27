package PAX::NativeRunner;

our $VERSION = '0.007';

use strict;
use warnings;
use IPC::Open3;
use Symbol qw(gensym);

sub new {
    my ($class, %args) = @_;
    return bless {}, $class;
}

sub run_i64_binary {
    my ($self, %args) = @_;
    my $path = $args{path};
    my $left = defined $args{left} ? $args{left} : 0;
    my $right = defined $args{right} ? $args{right} : 0;

    if (!defined $path || !-x $path) {
        return {
            status => 'error',
            reason => 'native executable missing or not executable',
        };
    }

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $path, $left, $right);
    close $in;
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$err> // '';
    waitpid($pid, 0);
    chomp $stdout;

    return {
        status => ($? >> 8) == 0 ? 'ok' : 'error',
        exit => $? >> 8,
        stdout => $stdout,
        stderr => $stderr,
        value => $stdout =~ /^-?\d+$/ ? 0 + $stdout : undef,
    };
}

1;
