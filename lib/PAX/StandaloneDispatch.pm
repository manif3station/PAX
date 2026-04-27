package PAX::StandaloneDispatch;

our $VERSION = '0.007';

use strict;
use warnings;
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3;
use Symbol qw(gensym);

use PAX::DeoptEngine;
use PAX::GuardManager;
use PAX::NativeRunner;
use PAX::StandaloneImage;

sub new {
    my ($class, %args) = @_;
    return bless {
        image_store => $args{image_store} // PAX::StandaloneImage->new,
        native_runner => $args{native_runner} // PAX::NativeRunner->new,
    }, $class;
}

sub run_i64 {
    my ($self, %args) = @_;
    my $image = $args{image} // $self->{image_store}->load(name => ($args{name} // die 'name required'));
    my $region_name = $args{region_name} // die 'region_name required';
    my $left = defined $args{left} ? $args{left} : 0;
    my $right = defined $args{right} ? $args{right} : 0;
    my @invalidate = @{ $args{invalidate} // [] };

    my $region = _lookup_region($image, $region_name);
    if (!$region) {
        return {
            status => 'fallback',
            execution_model => 'standalone_region_missing',
            requested_region => $region_name,
            reason => "requested region not found: $region_name",
        };
    }

    my $extract_dir = tempdir('pax-standalone-dispatch-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    _extract_image($image, $extract_dir);
    my $paths = _runtime_paths($image, $extract_dir);
    _restore_executable_bits($image, $paths);

    my %epochs = %{ $image->{runtime_epochs} // {} };
    delete @epochs{@invalidate} if @invalidate;
    my $guard = PAX::GuardManager->new(epochs => \%epochs)->validate_or_deopt(
        {
            region_id => $region->{region_id},
            region_name => $region->{region_name},
            guards => $region->{guards} // [],
            deopt => $region->{deopt} // {},
        },
        args => [ $left + 0, $right + 0 ],
        context => 'scalar',
    );

    if ($guard->{status} eq 'native_allowed' && $region->{executable_logical_path}) {
        my $path = File::Spec->catfile($extract_dir, split m{/}, $region->{executable_logical_path});
        my $result = $self->{native_runner}->run_i64_binary(
            path => $path,
            left => $left,
            right => $right,
        );
        if (($result->{status} // '') eq 'ok') {
            return {
                status => 'native',
                execution_model => 'standalone_packaged_native',
                region_id => $region->{region_id},
                region_name => $region->{region_name},
                result => $result,
                guard => $guard,
            };
        }
    }

    my $fallback = _run_perl_region(
        image => $image,
        paths => $paths,
        region => $region,
        left => $left,
        right => $right,
    );

    my $deopt = $guard->{status} eq 'deopt'
        ? $guard->{fallback}{reconstructed_frame}
        : PAX::DeoptEngine->new->reconstruct(
            ssa_unit => {
                region_id => $region->{region_id},
                region_name => $region->{region_name},
                deopt => $region->{deopt} // {},
            },
            reason => $fallback->{reason} // 'native_execution_failed',
            args => [ $left + 0, $right + 0 ],
            context => 'scalar',
            interpreter_result => $fallback->{value},
        );

    return {
        status => ($guard->{status} eq 'deopt') ? 'deopt' : 'fallback',
        execution_model => 'standalone_bundled_perl_fallback',
        region_id => $region->{region_id},
        region_name => $region->{region_name},
        guard => $guard,
        deopt => $deopt,
        result => $fallback,
    };
}

sub _lookup_region {
    my ($image, $region_name) = @_;
    for my $region (@{ $image->{native_dispatch} // [] }) {
        return $region if ($region->{region_name} // '') eq $region_name;
        return $region if ($region->{region_name} // '') eq "main::$region_name";
    }
    return;
}

sub _extract_image {
    my ($image, $extract_dir) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $image->{output_path}, '--pax-standalone-extract', $extract_dir);
    close $in;
    local $/;
    <$out>;
    my $stderr = <$err> // '';
    waitpid($pid, 0);
    die "standalone extraction failed for $image->{output_path}: $stderr\n" if ($? >> 8) != 0;
}

sub _runtime_paths {
    my ($image, $extract_dir) = @_;
    my $code_root = File::Spec->catdir($extract_dir, 'code');
    my $runtime_root = File::Spec->catdir($extract_dir, 'runtime');
    my $assets_root = File::Spec->catdir($extract_dir, 'assets');
    my $entrypoint = File::Spec->catfile($code_root, split m{/}, $image->{entrypoint}{logical_path});
    my $perl_exec = ($image->{runtime}{mode} // '') eq 'bundled_perl'
        ? File::Spec->catfile($runtime_root, split m{/}, ($image->{runtime}{perl_binary_logical_path} // 'bin/perl'))
        : 'perl';

    my @lib_roots = map { File::Spec->catdir($code_root, split m{/}) } @{ $image->{lib_dirs} // [] };
    my @runtime_roots = map { File::Spec->catdir($runtime_root, split m{/}) } @{ $image->{runtime}{bundled_inc_roots} // [] };
    return {
        extract_dir => $extract_dir,
        code_root => $code_root,
        runtime_root => $runtime_root,
        assets_root => $assets_root,
        entrypoint => $entrypoint,
        manifest_path => File::Spec->catfile($image->{standalone_dir}, 'manifest.json'),
        perl_exec => $perl_exec,
        perl5lib => join(':', grep { defined && length } (@lib_roots, @runtime_roots)),
    };
}

sub _restore_executable_bits {
    my ($image, $paths) = @_;
    chmod 0700, $paths->{perl_exec} if ($image->{runtime}{mode} // '') eq 'bundled_perl' && -f $paths->{perl_exec};
    for my $region (@{ $image->{native_dispatch} // [] }) {
        next if !$region->{executable_logical_path};
        my $path = File::Spec->catfile($paths->{extract_dir}, split m{/}, $region->{executable_logical_path});
        chmod 0700, $path if -f $path;
    }
}

sub _run_perl_region {
    my (%args) = @_;
    my $paths = $args{paths};
    my $region = $args{region};
    my $perl = $paths->{perl_exec};
    my $script = q{
my ($entry, $region, $left, $right) = @ARGV;
require PAX::StandaloneRuntime;
my $rv = PAX::StandaloneRuntime->run(entrypoint => $entry, argv => []);
my $qualified = $region =~ /::/ ? $region : "main::$region";
no strict 'refs';
my $value = &{$qualified}(0 + $left, 0 + $right);
print defined $value ? $value : q{};
};
    local $ENV{PERL5LIB} = $paths->{perl5lib} if defined $paths->{perl5lib} && length $paths->{perl5lib};
    local $ENV{PAX_EMBEDDED_ASSET_ROOT} = $paths->{assets_root};
    local $ENV{PAX_STANDALONE_MANIFEST_PATH} = $paths->{manifest_path};
    local $ENV{PAX_STANDALONE_TMPDIR} = $paths->{extract_dir};

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $perl, '-e', $script, $paths->{entrypoint}, $region->{region_name}, $args{left}, $args{right});
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
        reason => ($? >> 8) == 0 ? 'perl_region_fallback' : 'perl_region_execution_failed',
    };
}

1;
