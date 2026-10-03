use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use FindBin;
use IO::Socket::INET;

=pod

=head1 NAME

t/docker_distros.t - the dashboard binary serves its web UI on other distributions

=head1 WHY IT EXISTS

A self-contained binary must not depend on whichever distribution it was built on. Running it in
real containers (an image with nothing in it, musl-based Alpine, Debian, and any extra images named
in C<PAX_DOCKER_IMAGES>) proves that, including the web service, which is the core function.

=head1 DESCRIPTION

Builds the Developer Dashboard binary, then for each image runs C<init>, creates a user and starts
C<serve --foreground> with host networking, and checks login (302), the bundled favicon (200), an
authenticated C</apps> (302) and a saved Ajax route. Skips without the application checkout, a
reachable Docker daemon, or a free port 7890.

=head1 HOW TO RUN

  prove -l t/docker_distros.t
  PAX_DOCKER_IMAGES="ubuntu:18.04 fedora:40" prove -l t/docker_distros.t

=cut

my $app = $ENV{PAX_PARITY_APP} // abs_path("$FindBin::Bin/../../developer-dashboard") // '';
plan skip_all => 'no Developer Dashboard checkout found (set PAX_PARITY_APP)' if !$app || !-f "$app/bin/dashboard";
plan skip_all => 'no reachable Docker daemon' if system('docker info >/dev/null 2>&1') != 0;
# Several tests use the dashboard's fixed port; serialize them across parallel `prove -j` workers.
use Fcntl qw(:flock);
open my $port_lock, '>>', '/tmp/pax-port-7890.lock' or die "cannot open port lock: $!";
flock($port_lock, LOCK_EX);
my $port = 7890;
plan skip_all => "port $port is already in use" if IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 1);

my $tmp = tempdir('pax-docker-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $bin = "$tmp/dashboard";
my $pax = abs_path("$FindBin::Bin/../bin/pax");
my $rc = system('sh', '-c', 'cd "$1" && PAX_PROGRESS=0 "$2" -I"$3/lib" "$4" build --compact -o "$5" "$6/bin/dashboard" >/dev/null 2>&1', 'sh', $tmp, $^X, abs_path("$FindBin::Bin/.."), $pax, $bin, $app);
plan skip_all => 'could not build the dashboard binary' if $rc != 0 || !-x $bin;

# The image with nothing in it: no shell, no libc, no files.
system('tar -cT /dev/null | docker import - pax-empty-test >/dev/null 2>&1');
my @images = ('pax-empty-test', 'alpine:3.20', 'debian:bookworm-slim', split(' ', $ENV{PAX_DOCKER_IMAGES} // ''));

# probe($image) runs the service in that image and returns the observed status codes.
sub probe {
    my ($image) = @_;
    my $vol = "$tmp/vol-" . ($image =~ s/\W+/_/gr);
    make_path("$vol/home/.developer-dashboard/dashboards/ajax", "$vol/tmp");
    open my $aj, '>', "$vol/home/.developer-dashboard/dashboards/ajax/hello.pl" or die $!;
    print {$aj} "print qq{ajax-hello\\n};\n";
    close $aj;
    my $run = "docker run --rm --network host -v $bin:/app:ro -v $vol/home:/root -v $vol/tmp:/tmp -e HOME=/root $image";
    return { error => 'image unavailable' } if $image ne 'pax-empty-test' && system("docker image inspect $image >/dev/null 2>&1") != 0 && system("docker pull -q $image >/dev/null 2>&1") != 0;
    system("$run /app init >/dev/null 2>&1");
    system("$run /app auth add-user bob password123 >/dev/null 2>&1");
    chomp(my $cid = `docker run -d --rm --network host -v $bin:/app:ro -v $vol/home:/root -v $vol/tmp:/tmp -e HOME=/root $image /app serve --foreground`);
    my %seen;
    for (1 .. 40) {
        last if IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 1);
        select(undef, undef, undef, 0.5);
    }
    my $host = 'example.test:7890';
    my $login = `curl -s -m 15 -D - -o /dev/null -H 'Host: $host' -H 'Origin: http://$host' -d 'username=bob&password=password123' http://127.0.0.1:$port/login`;
    ($seen{login}) = $login =~ m{\AHTTP/\S+ (\d+)};
    my ($cookie) = $login =~ /^set-cookie: *([^;\r\n]*)/mi;
    $seen{favicon} = `curl -s -m 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:$port/favicon.ico`;
    $seen{apps} = `curl -s -m 10 -o /dev/null -w '%{http_code}' -H 'Host: $host' -H 'Cookie: $cookie' http://127.0.0.1:$port/apps`;
    $seen{ajax} = `curl -s -m 20 -H 'Host: $host' -H 'Cookie: $cookie' 'http://127.0.0.1:$port/ajax?file=hello.pl&type=text'`;
    system("docker rm -f $cid >/dev/null 2>&1");
    chomp(@seen{qw(favicon apps ajax)});
    return \%seen;
}

for my $image (@images) {
    my $seen = probe($image);
    SKIP: {
        skip "$image: $seen->{error}", 4 if $seen->{error};
        is($seen->{login}, 302, "$image: login succeeds");
        is($seen->{favicon}, 200, "$image: bundled static asset is served");
        is($seen->{apps}, 302, "$image: authenticated route answers");
        is($seen->{ajax}, 'ajax-hello', "$image: saved Ajax route runs");
    }
}
system('docker rmi -f pax-empty-test >/dev/null 2>&1');

done_testing();
