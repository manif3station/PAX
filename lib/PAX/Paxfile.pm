package PAX::Paxfile;

our $VERSION = '0.012';

use strict;
use warnings;

sub load_optional {
    my ($class, $path) = @_;
    $path //= 'paxfile.yml';
    return {} if !-f $path;
    return $class->load($path);
}

sub load {
    my ($class, $path) = @_;
    open my $fh, '<', $path or die "cannot read $path: $!";
    local $/ = "\n";
    my %data;
    my $section;
    while (defined(my $line = <$fh>)) {
        chomp $line;
        $line =~ s/\r\z//;
        $line =~ s/\s+#.*\z//;
        next if $line =~ /^\s*(?:#.*)?\z/;

        if ($line =~ /^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*?)\s*\z/) {
            my ($key, $value) = ($1, $2);
            if ($value eq '') {
                $section = $key;
                $data{$section} //= [];
                next;
            }
            $data{$key} = _scalar($value);
            $section = undef;
            next;
        }

        if (defined $section && $line =~ /^\s*-\s*(.*?)\s*\z/) {
            push @{ $data{$section} }, _scalar($1);
            next;
        }

        die "unsupported paxfile.yml syntax: $line\n";
    }
    close $fh;
    return \%data;
}

sub _scalar {
    my ($value) = @_;
    $value =~ s/\A\s+|\s+\z//g;
    if ($value =~ /\A"(.*)"\z/s || $value =~ /\A'(.*)'\z/s) {
        $value = $1;
    }
    return $value;
}

1;
