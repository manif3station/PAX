package PAX::StandaloneAnalysis;

our $VERSION = '0.024';

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Spec;
use JSON::PP ();
use PAX::Capture;
use PAX::Manifest;
use PAX::RegionSelector;
use PAX::HIR;
use PAX::GuardedSSA;
use PAX::Tier1;

sub new {
    my ($class, %args) = @_;
    return bless {}, $class;
}

sub dependencies {
    my ($self, %args) = @_;
    my $entrypoint = $args{entrypoint} // die 'entrypoint required';
    my $code_units = $args{code_units} // [];
    my $cpanfiles = $args{cpanfiles} // [];

    my %modules;
    my @seed_modules;
    for my $unit (@$code_units) {
        my $source = _analysis_source(_slurp($unit->{source_path}));
        for my $module (_source_module_refs($source)) {
            $modules{$module}{used_in_code} = 1;
            push @seed_modules, $module;
        }
    }

    for my $cpanfile (@$cpanfiles) {
        my $source = _slurp($cpanfile);
        while ($source =~ /^\s*(requires|recommends)\s+['"]([A-Za-z_][A-Za-z0-9_:]*)['"]/gm) {
            my ($kind, $module) = ($1, $2);
            push @{ $modules{$module}{declared_in_cpanfile} }, {
                type => $kind,
                path => $cpanfile,
            };
        }
    }

    my %packaged = map {
        my $name = _module_name_from_path($_->{source_path});
        defined $name ? ($name => $_) : ()
    } grep { ($_->{unit_kind} // '') eq 'lib' || ($_->{unit_kind} // '') eq 'dependency' } @$code_units;
    _expand_dependency_closure(\%modules, \@seed_modules, \%packaged);
    my @items;
    my %summary = (
        packaged_app => 0,
        compiled_dependency => 0,
        bundled_pure_perl => 0,
        bundled_xs => 0,
        missing => 0,
        unsupported => 0,
    );

    for my $module (sort keys %modules) {
        my %item = (
            module => $module,
            declared_in_cpanfile => $modules{$module}{declared_in_cpanfile} // [],
            used_in_code => $modules{$module}{used_in_code} ? JSON::PP::true() : JSON::PP::false(),
        );
        if (my $packaged = $packaged{$module}) {
            if (($packaged->{unit_kind} // '') eq 'dependency') {
                $item{class} = 'compiled_dependency';
                $item{provider} = 'pax_compiler';
                $summary{compiled_dependency}++;
            } else {
                $item{class} = 'packaged_app';
                $item{provider} = 'application';
                $summary{packaged_app}++;
            }
            $item{source_path} = $packaged->{source_path};
            $item{packaging} = $packaged->{packaging};
        } else {
            my $path = _locate_module($module);
            if (!$path) {
                $item{class} = 'missing';
                $item{provider} = 'unresolved';
                $summary{missing}++;
            } else {
                my $xs = _module_uses_xs($path);
                $item{class} = $xs ? 'bundled_xs' : 'bundled_pure_perl';
                $item{provider} = 'bundled_runtime';
                $item{source_path} = $path;
                $item{xs} = $xs ? JSON::PP::true() : JSON::PP::false();
                $summary{$item{class}}++;
            }
        }
        push @items, \%item;
    }

    return {
        items => \@items,
        summary => \%summary,
    };
}

sub _analysis_source {
    my ($source) = @_;
    $source //= '';
    $source =~ s/^__(?:END|DATA)__\b.*\z//ms;
    $source =~ s/^=\w+.*?^=cut\s*\n?//msg;
    return $source;
}

sub _source_module_refs {
    my ($source) = @_;
    my @modules;
    while ($source =~ /^\s*use\s+([A-Z][A-Za-z0-9_:]*)\b/gm) {
        my $module = $1;
        next if !_is_dependency_candidate($module);
        push @modules, $module;
    }
    while ($source =~ /^\s*require\s+([A-Z][A-Za-z0-9_:]*)\b/gm) {
        my $module = $1;
        next if !_is_dependency_candidate($module);
        push @modules, $module;
    }
    my %seen;
    return grep { !$seen{$_}++ } @modules;
}

sub _is_dependency_candidate {
    my ($module) = @_;
    return 0 if !defined $module || length($module) < 2;
    return 0 if $module =~ /^(?:strict|warnings|utf8|lib|parent|base|constant|feature)$/;
    return 1;
}

sub _expand_dependency_closure {
    my ($modules, $seed_modules, $packaged) = @_;
    my @queue = grep { defined && $_ ne '' } @$seed_modules;
    my %seen_module;
    my %scanned_path;

    while (@queue) {
        my $module = shift @queue;
        next if $seen_module{$module}++;
        my $path = $packaged->{$module} ? $packaged->{$module}{source_path} : _locate_module($module);
        next if !$path || $scanned_path{$path}++;
        my $source = _analysis_source(_slurp($path));
        for my $child (_source_module_refs($source)) {
            $modules->{$child}{used_in_code} = 1 if !exists $modules->{$child}{used_in_code};
            next if $seen_module{$child};
            push @queue, $child;
        }
    }
}

sub native_artifacts {
    my ($self, %args) = @_;
    my $entrypoint = $args{entrypoint} // die 'entrypoint required';
    my $code_units = $args{code_units} // [];
    my @probe_paths = _native_probe_paths($entrypoint, $code_units);
    return { items => [], summary => { native_ready => 0, fallback_only => 0, total => 0 }, runtime_epochs => undef }
        if !_native_probe_worthwhile(\@probe_paths);
    my $capture = eval { PAX::Capture->new(mode => 'live')->capture($entrypoint) };
    return {
        items => [],
        summary => { native_ready => 0, fallback_only => 0, total => 0 },
        diagnostics => [{
            level => 'warning',
            code => 'native_capture_failed',
            message => "$@",
        }],
        runtime_epochs => undef,
    } if !$capture || $@;
    return { items => [], summary => { native_ready => 0, fallback_only => 0, total => 0 } }
        if ($capture->{status} ne 'ok');

    my ($manifest, $regions, $hir, $ssa) = eval {
        my $manifest = PAX::Manifest->new(capture => $capture)->to_hash;
        my $regions = PAX::RegionSelector->new(manifest => $manifest)->select;
        my $hir = PAX::HIR->new(manifest => $manifest, regions => $regions->{selected})->lower_all;
        my $ssa = PAX::GuardedSSA->new(hir_units => $hir)->build_all;
        ($manifest, $regions, $hir, $ssa);
    };
    return {
        items => [],
        summary => { native_ready => 0, fallback_only => 0, total => 0 },
        diagnostics => [{
            level => 'warning',
            code => 'native_analysis_failed',
            message => "$@",
        }],
        runtime_epochs => undef,
    } if $@;

    my @items;
    my %summary = (
        total => 0,
        native_ready => 0,
        fallback_only => 0,
    );
    for my $unit (@$ssa) {
        my $artifact = PAX::Tier1->new(out_dir => '.pax/standalone-native')->compile($unit);
        my %item = (
            region_id => $unit->{region_id},
            region_name => $unit->{region_name},
            status => $artifact->{status},
            entry_kind => $artifact->{entry_kind},
            reason => $artifact->{reason},
            guards => $unit->{guards},
            deopt => $unit->{deopt},
            tier2_artifact => $artifact->{tier2_artifact},
        );
        if (($artifact->{entry_kind} // '') =~ /\Anative_i64_(?:leaf|loop)\z/ && $artifact->{executable_path}) {
            $item{executable_path} = $artifact->{executable_path};
            $item{library_path} = $artifact->{library_path};
            $summary{native_ready}++;
        } else {
            $summary{fallback_only}++;
        }
        $summary{total}++;
        push @items, \%item;
    }

    return {
        items => \@items,
        summary => \%summary,
        runtime_epochs => $manifest->{runtime_epochs},
    };
}

sub _native_probe_paths {
    my ($entrypoint, $code_units) = @_;
    my %seen;
    my @paths = grep { defined && !$seen{$_}++ } (
        $entrypoint,
        map { $_->{source_path} } @$code_units,
    );
    return @paths;
}

sub _native_probe_worthwhile {
    my ($paths) = @_;
    for my $path (@$paths) {
        next if !$path || !-f $path;
        my $source = _slurp($path);
        next if !defined $source || $source eq '';
        return 1 if _source_has_native_candidate($source);
    }
    return 0;
}

sub _source_has_native_candidate {
    my ($source) = @_;
    return 1 if $source =~ /sub\s+\w+\s*\{[^{}]*my\s*\(\s*\$\w+\s*,\s*\$\w+\s*\)\s*=\s*\@_;[^{}]*return\s+\$\w+\s*(?:\+|\-|\*)\s*\$\w+\s*;/ms;
    return 1 if $source =~ /sub\s+\w+\s*\{[^{}]*for\s*\(.*?;.*?;.*?\)\s*\{[^{}]*\$\w+\s*(?:\+=|\-=|\*=)\s*\$\w+/ms;
    return 1 if $source =~ /sub\s+\w+\s*\{[^{}]*while\s*\(.*?\)\s*\{[^{}]*\$\w+\s*(?:\+=|\-=|\*=)\s*\$\w+/ms;
    return 0;
}

sub _module_name_from_path {
    my ($path) = @_;
    return undef if !$path || $path !~ /\.pm$/;
    my $abs = abs_path($path) || $path;
    for my $inc (@INC) {
        next if ref $inc;
        my $inc_abs = abs_path($inc) || $inc;
        next if index($abs, $inc_abs . '/') != 0;
        my $rel = substr($abs, length($inc_abs) + 1);
        $rel =~ s/\.pm$//;
        $rel =~ s{/}{::}g;
        return $rel if $rel ne '';
    }
    my @parts = File::Spec->splitdir($abs);
    for my $i (0 .. $#parts) {
        if ($parts[$i] eq 'lib' && $i < $#parts) {
            my @tail = @parts[$i + 1 .. $#parts];
            my $name = join('::', @tail);
            $name =~ s/\.pm$//;
            return $name if $name ne '';
        }
    }
    my $name = $parts[-1];
    $name =~ s/\.pm$//;
    return $name;
}

sub _locate_module {
    my ($module) = @_;
    my $rel = $module;
    $rel =~ s{::}{/}g;
    $rel .= '.pm';
    for my $inc (@INC) {
        next if ref $inc;
        my $path = File::Spec->catfile($inc, $rel);
        return abs_path($path) || $path if -f $path;
    }
    return;
}

sub _module_uses_xs {
    my ($path) = @_;
    my $source = _slurp($path);
    return 1 if $source =~ /\b(?:XSLoader|DynaLoader)\b/;
    my $base = $path;
    $base =~ s/\.pm$//;
    for my $ext (qw(so bundle dll)) {
        return 1 if -f "$base.$ext";
    }
    return 0;
}

sub _slurp {
    my ($path) = @_;
    open my $fh, '<', $path or return '';
    local $/;
    return <$fh> // '';
}

1;

=pod

=head1 NAME

PAX::StandaloneAnalysis - document the StandaloneAnalysis component within the PAX compiler, packaging, or runtime stack.

=head1 DESCRIPTION

This file is part of the maintained PAX Perl surface and exists to document the StandaloneAnalysis component within the PAX compiler, packaging, or runtime stack.

=cut

