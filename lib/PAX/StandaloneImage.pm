package PAX::StandaloneImage;

our $VERSION = '0.011';

use strict;
use warnings;
use Cwd qw(abs_path);
use Config ();
use Digest::SHA qw(sha256_hex);
use File::Find ();
use File::Path qw(make_path);
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP ();
use PAX::CodeUnitCompiler;
use PAX::StandaloneAnalysis;

my %PURE_PERL_MODULE_CACHE;
my %RUNTIME_FAMILY_FILE_CACHE;

sub new {
    my ($class, %args) = @_;
    return bless {
        root => $args{root} // $ENV{PAX_STANDALONE_ROOT} // '.pax/standalone',
    }, $class;
}

sub build_progress_tasks {
    return [
        { id => 'resolve_inputs', label => 'Resolve build inputs' },
        { id => 'compile_code_units', label => 'Compile Perl code units' },
        { id => 'discover_dependencies', label => 'Discover runtime dependencies' },
        { id => 'package_runtime', label => 'Package runtime payloads' },
        { id => 'package_assets', label => 'Embed asset payloads' },
        { id => 'compile_launcher', label => 'Compile standalone launcher' },
    ];
}

sub build {
    my ($self, %args) = @_;
    my $progress = $args{progress};
    my $entrypoint = $args{entrypoint} // die 'entrypoint required';
    my $name = $args{name} // _default_name($entrypoint);
    _progress_emit($progress, { task_id => 'resolve_inputs', status => 'running' });
    my $abs_entrypoint = abs_path($entrypoint) || die "entrypoint not found: $entrypoint";
    my @lib_dirs = _abs_existing([
        @{ $args{lib_dirs} // [] },
        _entrypoint_declared_lib_dirs($abs_entrypoint),
    ]);
    my @source_roots = _abs_existing($args{source_roots} // []);
    my @scan_roots = grep { defined && $_ ne '' } (_safe_dir_abs($abs_entrypoint), @lib_dirs, @source_roots);
    _progress_emit($progress, {
        task_id => 'resolve_inputs',
        status => 'done',
        label => sprintf('Resolve build inputs (%d lib dirs, %d source roots)', scalar(@lib_dirs), scalar(@source_roots)),
    });
    _progress_emit($progress, { task_id => 'compile_code_units', status => 'running' });
    my @code_units = _code_manifest($abs_entrypoint, \@lib_dirs, \@source_roots);
    _progress_emit($progress, {
        task_id => 'compile_code_units',
        status => 'done',
        label => sprintf('Compile Perl code units (%d packaged units)', scalar(@code_units)),
    });

    my $inferred_namespace = _infer_app_namespace(
        units => \@code_units,
        scan_roots => \@scan_roots,
    );
    my $app_namespace = _normalize_namespace($args{app_namespace});
    $app_namespace = $inferred_namespace if $app_namespace eq '';
    my $legacy_namespace = _normalize_namespace($args{app_legacy_namespace});
    if ($legacy_namespace eq '') {
        $legacy_namespace = $inferred_namespace;
    }

    my $app_meta = _app_metadata(
        app_name => $args{app_name},
        app_namespace => $app_namespace,
        app_legacy_namespace => $legacy_namespace,
        app_entrypoint_env => $args{app_entrypoint_env},
        app_entrypoint_fallback => $args{app_entrypoint_fallback},
        app_command => $args{app_command},
        image_name => $name,
        entrypoint => $entrypoint,
    );
    my $runtime_mode = $args{runtime_mode} // 'bundled_perl';
    my @cpanfiles = _abs_existing($args{cpanfiles} // []);
    _progress_emit($progress, { task_id => 'package_assets', status => 'running' });
    my $assets = _asset_manifest($args{assets} // [], $args{asset_dirs} // []);
    _progress_emit($progress, {
        task_id => 'package_assets',
        status => 'done',
        label => sprintf('Embed asset payloads (%d assets)', scalar(@$assets)),
    });

    my $analysis = PAX::StandaloneAnalysis->new;
    _progress_emit($progress, { task_id => 'discover_dependencies', status => 'running' });
    my $dependencies = $analysis->dependencies(
        entrypoint => $abs_entrypoint,
        code_units => \@code_units,
        cpanfiles => \@cpanfiles,
    );
    _progress_emit($progress, {
        task_id => 'discover_dependencies',
        status => 'done',
        label => sprintf(
            'Discover runtime dependencies (%d packaged, %d bundled XS)',
            $dependencies->{summary}{packaged_app} // 0,
            $dependencies->{summary}{bundled_xs} // 0,
        ),
    });
    my $native = $analysis->native_artifacts(
        entrypoint => $abs_entrypoint,
        code_units => \@code_units,
    );
    my $native_payloads = _native_payloads($native->{items});
    _progress_emit($progress, { task_id => 'package_runtime', status => 'running' });
    my $runtime = _runtime_manifest(
        mode => $runtime_mode,
        dependencies => $dependencies->{items},
        lib_dirs => \@lib_dirs,
        code_units => \@code_units,
        exclude_dirs => [ @lib_dirs, @source_roots ],
        exclude_files => [ map { $_->{source_path} } @code_units ],
        app_namespace => $app_namespace,
        app_legacy_namespace => $app_meta->{compat}{legacy_namespace},
    );
    _progress_emit($progress, {
        task_id => 'package_runtime',
        status => 'done',
        label => sprintf('Package runtime payloads (%d payloads)', scalar(@{ $runtime->{payloads} // [] })),
    });
    my $standalone_dir = File::Spec->catdir($self->{root}, $name);
    make_path($standalone_dir);

    my $output_path = $args{output_path}
        ? _absolute_output($args{output_path})
        : File::Spec->catfile($standalone_dir, $name);
    my $manifest = {
        name => $name,
        app => $app_meta,
        model => $runtime_mode eq 'bundled_perl'
            ? 'single_executable_bundled_perl_payload'
            : 'single_executable_host_perl_payload',
        standalone_dir => $standalone_dir,
        output_path => $output_path,
        entrypoint => {
            source_path => $abs_entrypoint,
            logical_path => _entrypoint_logical_path($abs_entrypoint, \@code_units),
        },
        runtime => {
            mode => $runtime_mode,
            app_server_required => JSON::PP::false,
            source_tree_required => JSON::PP::false,
            perl_binary => $runtime->{perl_binary},
            perl_binary_logical_path => $runtime->{perl_binary_logical_path},
            bundled_inc_roots => $runtime->{bundled_inc_roots},
            runtime_hash => $runtime->{runtime_hash},
        },
        code_units => \@code_units,
        code_unit_count => scalar(@code_units),
        code_unit_bytes => _payload_bytes(\@code_units),
        dependencies => $dependencies->{items},
        dependency_summary => $dependencies->{summary},
        native_artifacts => [ map { _strip_native_runtime_paths($_) } @{ $native->{items} } ],
        native_artifact_summary => $native->{summary},
        native_dispatch => _native_dispatch_manifest($native->{items}),
        runtime_epochs => $native->{runtime_epochs},
        native_payloads => $native_payloads,
        native_payload_count => scalar(@$native_payloads),
        native_payload_bytes => _payload_bytes($native_payloads),
        runtime_payloads => $runtime->{payloads},
        runtime_payload_count => scalar(@{ $runtime->{payloads} }),
        runtime_payload_bytes => _payload_bytes($runtime->{payloads}),
        assets => $assets,
        asset_count => scalar(@$assets),
        asset_bytes => _payload_bytes($assets),
        lib_dirs => [ map { _logical_root('lib', $_) } @lib_dirs ],
        source_roots => [ map { _logical_root('src', $_) } @source_roots ],
        source_hash => _source_hash(\@code_units, $assets, $runtime->{payloads}, $native_payloads),
        build_plan => {
            paxfile_applied => $args{paxfile_applied} ? JSON::PP::true : JSON::PP::false,
            override_fields => $args{override_fields} // [],
            source_packaging => 'mixed_compiled_pcu_v1_hybrid_or_source_fallback_with_compiled_dependencies',
            native_packaging => 'packaged_dispatch_bundle',
            asset_packaging => 'embedded',
        },
    };

    _write_json(File::Spec->catfile($standalone_dir, 'manifest.json'), $manifest);
    _progress_emit($progress, { task_id => 'compile_launcher', status => 'running' });
    my $compile = _compile_launcher($manifest);
    _progress_emit($progress, {
        task_id => 'compile_launcher',
        status => $compile->{status} eq 'built' ? 'done' : 'failed',
        label => $compile->{status} eq 'built'
            ? 'Compile standalone launcher'
            : 'Compile standalone launcher (' . ($compile->{reason} // 'failed') . ')',
    });
    $manifest->{launcher_status} = $compile->{status};
    $manifest->{launcher_reason} = $compile->{reason} if $compile->{reason};
    _write_json(File::Spec->catfile($standalone_dir, 'manifest.json'), $manifest);
    return {
        status => $compile->{status} eq 'built' ? 'built' : 'not_built',
        standalone => _manifest_without_bytes($manifest),
        manifest_path => File::Spec->catfile($standalone_dir, 'manifest.json'),
    };
}

sub _progress_emit {
    my ($progress, $event) = @_;
    return 1 if !$progress || ref($progress) ne 'CODE';
    $progress->($event);
    return 1;
}

sub load {
    my ($self, %args) = @_;
    my $name = $args{name} // die 'name required';
    my $path = File::Spec->catfile($self->{root}, $name, 'manifest.json');
    open my $fh, '<', $path or die "cannot read standalone image $path: $!";
    local $/;
    return JSON::PP::decode_json(<$fh>);
}

sub path_for {
    my ($self, $name) = @_;
    return File::Spec->catfile($self->{root}, $name, 'manifest.json');
}

sub _default_name {
    my ($entrypoint) = @_;
    my ($vol, $dir, $file) = File::Spec->splitpath($entrypoint);
    $file =~ s/\.[^.]+\z//;
    $file =~ s/[^A-Za-z0-9_.-]+/-/g;
    return $file || 'pax-standalone';
}

sub _app_metadata {
    my (%args) = @_;
    my $entrypoint = $args{entrypoint} // '';
    my $image_name = $args{image_name} // 'pax-standalone';
    my $app_name = $args{app_name} // $image_name;
    my $command_fallback = _entrypoint_default_command($entrypoint);
    my $command = $args{app_command} // $command_fallback;
    my $entrypoint_env = $args{app_entrypoint_env};
    my $entrypoint_fallback = $args{app_entrypoint_fallback} // $command_fallback;
    my $legacy_namespace = _normalize_namespace($args{app_legacy_namespace});
    my $compat_namespace = _normalize_namespace($args{app_namespace});
    $legacy_namespace = $compat_namespace if $legacy_namespace eq '';

    return {
        name => $app_name,
        namespace => $compat_namespace,
        compat => {
            namespace => $compat_namespace,
            legacy_namespace => $legacy_namespace,
        },
        command => $command,
        entrypoint_env => $entrypoint_env // '',
        entrypoint_fallback => $entrypoint_fallback,
        entrypoint_command => $command,
    };
}

sub _safe_dir_abs {
    my ($path) = @_;
    return '' if !defined $path || $path eq '';
    my $dir = dirname($path);
    return abs_path($dir) || $dir;
}

sub _infer_app_namespace {
    my (%args) = @_;
    my $units = $args{units} // [];
    my %score;

    for my $unit (@$units) {
        my $module = $unit->{module} // '';
        next if !$module;
        my @parts = split /::/, $module;
        next if @parts < 2;
        for my $i (2 .. @parts) {
            my $prefix = join('::', @parts[0 .. $i - 1]);
            $score{$prefix} += 1000 + $i;
        }
    }

    my $inferred = '';
    my $best = 0;
    for my $ns (keys %score) {
        next if scalar split(/::/, $ns) < 2;
        if ($score{$ns} > $best) {
            $best = $score{$ns};
            $inferred = $ns;
        }
    }

    return $inferred;
}

sub _entrypoint_default_command {
    my ($entrypoint) = @_;
    my ($vol, $dir, $file) = File::Spec->splitpath($entrypoint // '');
    $file =~ s/\.[^.]+\z//;
    $file =~ s/[^A-Za-z0-9_.-]+/-/g;
    return $file || 'pax';
}

sub _absolute_output {
    my ($path) = @_;
    return File::Spec->file_name_is_absolute($path)
        ? $path
        : File::Spec->catfile(File::Spec->rel2abs('.'), $path);
}

sub _abs_existing {
    my ($paths) = @_;
    my @abs;
    for my $path (@$paths) {
        my $abs = abs_path($path);
        push @abs, $abs if defined $abs;
    }
    return @abs;
}

sub _entrypoint_declared_lib_dirs {
    my ($entrypoint) = @_;
    my $source = _slurp_bytes($entrypoint);
    return () if $source eq '';
    my $bin_dir = dirname($entrypoint);
    my @dirs;
    while ($source =~ /^\s*use\s+lib\s+(.+?);/mg) {
        my $expr = $1;
        while ($expr =~ /(['"])(.*?)\1/g) {
            my $path = $2;
            $path =~ s/\$FindBin::Bin|\$Bin/$bin_dir/g;
            $path = File::Spec->rel2abs($path, $bin_dir) if !File::Spec->file_name_is_absolute($path);
            push @dirs, $path if -d $path;
        }
    }
    my %seen;
    return grep { !$seen{$_}++ } @dirs;
}

sub _logical_root {
    my ($prefix, $path) = @_;
    my ($vol, $dirs, $file) = File::Spec->splitpath($path, 1);
    my @parts = grep { length } File::Spec->splitdir($dirs);
    my $leaf = @parts ? $parts[-1] : $file;
    return _safe_logical_path(File::Spec->catfile($prefix, $leaf));
}

sub _code_manifest {
    my ($entrypoint, $lib_dirs, $source_roots) = @_;
    my @manifest;
    my %seen;
    my %seen_modules;
    my $compiler = PAX::CodeUnitCompiler->new;
    my @preferred_roots = grep { defined && $_ ne '' } (dirname($entrypoint), @$lib_dirs, @$source_roots);

    my $entry_unit = $compiler->compile(
        path => $entrypoint,
        kind => 'entrypoint',
        logical_path => _safe_logical_path(File::Spec->catfile('entrypoint', _logical_name($entrypoint))),
    );
    push @manifest, $entry_unit;
    $seen{$entrypoint} = 1;
    my $entry_module = _module_name_from_source_path($entrypoint);
    $seen_modules{$entry_module} = 1 if defined $entry_module;

    for my $dir (@$lib_dirs) {
        my $prefix = _logical_root('lib', $dir);
        for my $path (_perl_files([$dir])) {
            next if $seen{$path}++;
            my $rel = File::Spec->abs2rel($path, $dir);
            my $compiled = $compiler->compile(
                path => $path,
                kind => 'lib',
                logical_path => _safe_logical_path(File::Spec->catfile($prefix, $rel)),
            );
            push @manifest, $compiled;
            my $module = _module_name_from_source_path($path);
            $seen_modules{$module} = 1 if defined $module;
        }
    }

    for my $dir (@$source_roots) {
        my $prefix = _logical_root('src', $dir);
        for my $path (_perl_files([$dir])) {
            next if $seen{$path}++;
            my $rel = File::Spec->abs2rel($path, $dir);
            my $compiled = $compiler->compile(
                path => $path,
                kind => 'source',
                logical_path => _safe_logical_path(File::Spec->catfile($prefix, $rel)),
            );
            push @manifest, $compiled;
            my $module = _module_name_from_source_path($path);
            $seen_modules{$module} = 1 if defined $module;
        }
    }

    my @queue = @manifest;
    while (my $unit = shift @queue) {
        next if ($unit->{unit_kind} // '') eq 'entrypoint' && ($unit->{packaging} // '') eq 'source_payload_fallback';
        my @deps = _pure_perl_dependency_units($unit, \%seen, \%seen_modules, $compiler, \@preferred_roots);
        push @manifest, @deps;
        push @queue, @deps;
    }

    return @manifest;
}

sub _pure_perl_dependency_units {
    my ($unit, $seen, $seen_modules, $compiler, $preferred_roots) = @_;
    my $source = _slurp_bytes($unit->{source_path});
    my @units;
    my %queued_module;
    for my $module (_declared_modules($source)) {
        next if _skip_dependency_module($module);
        next if $queued_module{$module}++;
        next if $seen_modules->{$module};
        my $path = _locate_pure_perl_module($module, $preferred_roots) or next;
        next if _dependency_runtime_only($path);
        next if $seen->{$path}++;
        my $logical = _safe_logical_path(File::Spec->catfile('dependency', split(/::/, $module))) . '.pm';
        my $compiled = $compiler->compile(
            path => $path,
            kind => 'dependency',
            logical_path => $logical,
        );
        next if (($compiled->{packaging} // '') eq 'source_payload_fallback');
        if (($compiled->{packaging} // '') eq 'hybrid_compiled_pcu_v1') {
            my $record = eval { JSON::PP::decode_json($compiled->{bytes}) };
            if (!$@ && ref($record) eq 'HASH' && !@{ $record->{subs} // [] }) {
                next;
            }
        }
        $seen_modules->{$module} = 1;
        push @units, $compiled;
    }
    return @units;
}

sub _dependency_runtime_only {
    my ($path) = @_;
    my $source = _slurp_bytes($path);
    return 0 if !$source;
    $source = _strip_pod($source);
    return 1 if $source =~ /^\s*sub\s+import\b/m;
    return 1 if $source =~ /\bcaller\s*\(/;
    return 1 if $source =~ /\bimport::into\b/i;
    return 1 if $source =~ /\@EXPORT(?:_OK)?\b/;
    return 1 if $source =~ /\bExporter\b/;
    return 0;
}

sub _dependency_codegen_safe {
    my ($path) = @_;
    my $source = _slurp_bytes($path);
    return 0 if !$source;
    $source = _strip_pod($source);
    return 0 if $source =~ /^\s*sub\s+import\b/m;
    return 0 if $source =~ /\bAUTOLOAD\b/;
    return 0 if $source =~ /\beval\b/;
    return 0 if $source =~ /\bgoto\s*&/;
    return 0 if $source =~ /\bcaller\s*\(/;
    return 0 if $source =~ /\*[\w:]+/;
    return 0 if $source =~ /\@EXPORT(?:_OK)?\b/;
    return 0 if $source =~ /\bExporter\b/;
    return 0 if $source =~ /^\s*sub\s+\w+\s*\([^\)]/m;
    return 1;
}

sub _declared_modules {
    my ($source) = @_;
    $source = _strip_pod($source);
    my @modules;
    while ($source =~ /^\s*use\s+([A-Za-z_][A-Za-z0-9_:]*)\b/gm) {
        push @modules, $1;
    }
    while ($source =~ /^\s*require\s+([A-Za-z_][A-Za-z0-9_:]*)\b/gm) {
        push @modules, $1;
    }
    while ($source =~ /^\s*use\s+(?:base|parent)\s+qw\(([^)]*)\)/gm) {
        push @modules, grep { $_ ne '' } split /\s+/, $1;
    }
    while ($source =~ /^\s*use\s+(?:base|parent)\s+['"]([A-Za-z_][A-Za-z0-9_:]*)['"]/gm) {
        push @modules, $1;
    }
    my %seen;
    return grep { !$seen{$_}++ } @modules;
}

sub _strip_pod {
    my ($source) = @_;
    $source //= '';
    $source =~ s/^__(?:END|DATA)__\b.*\z//ms;
    $source =~ s/^=\w+.*?^=cut\s*\n?//msg;
    return $source;
}

sub _skip_dependency_module {
    my ($module) = @_;
    return 1 if !$module;
    return 1 if $module =~ /^(?:strict|warnings|utf8|lib|parent|base|constant|feature|vars|integer|bytes|mro|overload|if|open|re)$/;
    return 1 if $module =~ /^PAX::/;
    return 0;
}

sub _locate_pure_perl_module {
    my ($module, $preferred_roots) = @_;
    my $cache_key = join "\0", $module, @{ $preferred_roots // [] };
    return $PURE_PERL_MODULE_CACHE{$cache_key} if exists $PURE_PERL_MODULE_CACHE{$cache_key};
    my $rel = $module;
    $rel =~ s{::}{/}g;
    $rel .= '.pm';
    my @search_roots = grep { defined && $_ ne '' } (@{ $preferred_roots // [] }, @INC);
    my %seen_root;
    for my $inc (@search_roots) {
        next if ref $inc;
        my $inc_abs = abs_path($inc) || $inc;
        next if $seen_root{$inc_abs}++;
        my $path = File::Spec->catfile($inc, $rel);
        next if !-f $path;
        my $abs = abs_path($path) || $path;
        next if _module_uses_xs($abs);
        return $PURE_PERL_MODULE_CACHE{$cache_key} = $abs;
    }
    return $PURE_PERL_MODULE_CACHE{$cache_key} = undef;
}

sub _module_name_from_source_path {
    my ($path) = @_;
    return if !$path || $path !~ /\.pm$/;
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
    return;
}

sub _entrypoint_logical_path {
    my ($entrypoint, $units) = @_;
    for my $unit (@$units) {
        return $unit->{logical_path} if $unit->{source_path} eq $entrypoint;
    }
    return _safe_logical_path(File::Spec->catfile('entrypoint', _logical_name($entrypoint)));
}

sub _perl_files {
    my ($dirs) = @_;
    my @files;
    for my $dir (@$dirs) {
        next if !-d $dir;
        File::Find::find({
            wanted => sub {
                return if !-f $_;
                return if $_ !~ /\.(?:pm|pl)$/;
                push @files, $File::Find::name;
            },
            no_chdir => 1,
        }, $dir);
    }
    return sort @files;
}

sub _asset_manifest {
    my ($assets, $asset_dirs) = @_;
    my @paths = map { [$_, _logical_name($_)] } @$assets;
    for my $dir (@$asset_dirs) {
        my $abs_dir = abs_path($dir) || next;
        File::Find::find({
            wanted => sub {
                return if !-f $_;
                my $rel = File::Spec->abs2rel($File::Find::name, $abs_dir);
                push @paths, [$File::Find::name, $rel];
            },
            no_chdir => 1,
        }, $abs_dir);
    }

    my @manifest;
    my %seen;
    for my $pair (@paths) {
        my ($path, $logical) = @$pair;
        my $abs = abs_path($path) || next;
        next if $seen{$logical}++;
        my $bytes = _slurp_bytes($abs);
        push @manifest, {
            source_path => $abs,
            logical_path => _safe_logical_path($logical),
            size => length($bytes),
            sha256 => sha256_hex($bytes),
            c_symbol => 'pax_asset_' . sha256_hex($logical),
            bytes => $bytes,
        };
    }
    return \@manifest;
}

sub _payload_bytes {
    my ($payloads) = @_;
    my $total = 0;
    $total += $_->{size} for @$payloads;
    return $total;
}

sub _source_hash {
    my ($code_units, $assets, $runtime_payloads, $native_payloads) = @_;
    my @items;
    push @items, [$_->{logical_path}, $_->{sha256}] for @$code_units;
    push @items, [$_->{logical_path}, $_->{sha256}] for @$assets;
    push @items, [$_->{logical_path}, $_->{sha256}] for @{ $runtime_payloads // [] };
    push @items, [$_->{logical_path}, $_->{sha256}] for @{ $native_payloads // [] };
    my $sha = Digest::SHA->new(256);
    for my $item (sort { $a->[0] cmp $b->[0] } @items) {
        $sha->add($item->[0]);
        $sha->add($item->[1]);
    }
    return $sha->hexdigest;
}

sub _compile_launcher {
    my ($manifest) = @_;
    my $source_path = "$manifest->{output_path}.c";
    my $parent = $manifest->{output_path};
    $parent =~ s{/[^/]+\z}{};
    make_path($parent) if length $parent && !-d $parent;
    my $build_dir = File::Spec->catdir($parent, '.pax-launcher-build');
    make_path($build_dir) if !-d $build_dir;
    my $code_pkg = File::Spec->catfile($build_dir, 'code.pkg');
    my $runtime_pkg = File::Spec->catfile($build_dir, 'runtime.pkg');
    my $asset_pkg = File::Spec->catfile($build_dir, 'assets.pkg');
    my $native_pkg = File::Spec->catfile($build_dir, 'native.pkg');
    my $code_obj = File::Spec->catfile($build_dir, 'code.pkg.o');
    my $runtime_obj = File::Spec->catfile($build_dir, 'runtime.pkg.o');
    my $asset_obj = File::Spec->catfile($build_dir, 'assets.pkg.o');
    my $native_obj = File::Spec->catfile($build_dir, 'native.pkg.o');
    _write_binary($code_pkg, _payload_package_blob($manifest->{code_units}));
    _write_binary($runtime_pkg, _payload_package_blob($manifest->{runtime_payloads}));
    _write_binary($asset_pkg, _payload_package_blob($manifest->{assets}));
    _write_binary($native_pkg, _payload_package_blob($manifest->{native_payloads} // []));
    open my $fh, '>', $source_path or return { status => 'not_built', reason => "cannot write launcher source: $!" };
    print {$fh} _launcher_source($manifest);
    close $fh;
    my $cc = _which('cc') || _which('gcc');
    my $objcopy = _which('objcopy');
    return { status => 'not_built', reason => 'no C compiler available' } if !$cc;
    return { status => 'not_built', reason => 'no objcopy available' } if !$objcopy;
    my $tool_path = _toolchain_path($cc, $objcopy);
    require Cwd;
    my $cwd = Cwd::getcwd();
    my $ok = eval {
        local $ENV{PATH} = $tool_path if defined $tool_path && $tool_path ne '';
        chdir $build_dir or die "cannot chdir to $build_dir: $!";
        system($objcopy, '--input', 'binary', '--output', 'elf64-x86-64', '--binary-architecture', 'i386:x86-64', 'code.pkg', 'code.pkg.o');
        die "objcopy code.pkg failed" if ($? >> 8) != 0;
        system($objcopy, '--input', 'binary', '--output', 'elf64-x86-64', '--binary-architecture', 'i386:x86-64', 'runtime.pkg', 'runtime.pkg.o');
        die "objcopy runtime.pkg failed" if ($? >> 8) != 0;
        system($objcopy, '--input', 'binary', '--output', 'elf64-x86-64', '--binary-architecture', 'i386:x86-64', 'assets.pkg', 'assets.pkg.o');
        die "objcopy assets.pkg failed" if ($? >> 8) != 0;
        system($objcopy, '--input', 'binary', '--output', 'elf64-x86-64', '--binary-architecture', 'i386:x86-64', 'native.pkg', 'native.pkg.o');
        die "objcopy native.pkg failed" if ($? >> 8) != 0;
        system(
            $cc,
            '-O2',
            '-Wl,-z,noexecstack',
            '-o',
            $manifest->{output_path},
            $source_path,
            'code.pkg.o',
            'runtime.pkg.o',
            'assets.pkg.o',
            'native.pkg.o',
        );
        die "launcher compile failed" if ($? >> 8) != 0;
        1;
    };
    my $restore_ok = eval { chdir $cwd or die "cannot restore cwd to $cwd: $!"; 1; };
    return { status => 'not_built', reason => $@ } if !$ok;
    return { status => 'not_built', reason => $@ } if !$restore_ok;
    return (($? >> 8) == 0 && -x $manifest->{output_path})
        ? { status => 'built' }
        : { status => 'not_built', reason => 'standalone launcher compile failed' };
}

sub _toolchain_path {
    my (@tools) = @_;
    my %seen;
    my @dirs;
    for my $tool (@tools) {
        next if !defined $tool || $tool eq '';
        my $dir = dirname($tool);
        next if !defined $dir || $dir eq '';
        push @dirs, $dir if !$seen{$dir}++;
    }
    for my $dir (qw(/usr/bin /bin /usr/sbin /sbin /usr/local/bin)) {
        push @dirs, $dir if !$seen{$dir}++;
    }
    return join ':', @dirs;
}

sub _launcher_source {
    my ($manifest) = @_;
    my $manifest_json = JSON::PP->new->ascii(1)->canonical(1)->encode(_manifest_without_bytes($manifest));
    my $manifest_literal = _c_string($manifest_json);
    my $entrypoint_logical = _c_string($manifest->{entrypoint}{logical_path});
    my $native_payload_count = scalar @{ $manifest->{native_payloads} // [] };
    my $runtime_mode = _c_string($manifest->{runtime}{mode} // 'host_perl');
    my $runtime_perl = _c_string($manifest->{runtime}{perl_binary_logical_path} // '');
    my $native_package_present = $native_payload_count ? '1' : '0';
    my $runtime_inc_roots = _string_array_c('pax_runtime_inc_roots', $manifest->{runtime}{bundled_inc_roots} // []);
    my $code_lib_roots = _string_array_c('pax_code_lib_roots', $manifest->{lib_dirs} // []);
    my $bootstrap_code = _c_string('use PAX::StandaloneRuntime; my $entry = shift @ARGV; my @args = @ARGV; PAX::StandaloneRuntime->run(entrypoint => $entry, argv => \@args);');
    return <<"C";
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

struct pax_pkg_entry {
    const char *path;
    unsigned long len;
    unsigned long offset;
};

extern const unsigned char _binary_code_pkg_start[];
extern const unsigned char _binary_code_pkg_end[];
extern const unsigned char _binary_runtime_pkg_start[];
extern const unsigned char _binary_runtime_pkg_end[];
extern const unsigned char _binary_assets_pkg_start[];
extern const unsigned char _binary_assets_pkg_end[];
extern const unsigned char _binary_native_pkg_start[];
extern const unsigned char _binary_native_pkg_end[];

$runtime_inc_roots
$code_lib_roots

static void ensure_parent_dirs(const char *path) {
    char tmp[4096];
    size_t len = strlen(path);
    if (len >= sizeof(tmp)) return;
    memcpy(tmp, path, len + 1);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0700);
            *p = '/';
        }
    }
}

static int write_package_root(const char *root, const unsigned char *blob, unsigned long blob_len) {
    char *copy = malloc(blob_len + 1);
    char *cursor;
    char *line;
    char *header_end;
    char *data_start = NULL;
    struct pax_pkg_entry *entries = NULL;
    unsigned long count = 0;
    unsigned long entry_index = 0;
    unsigned long offset = 0;
    int rc = 111;

    if (!copy) return 111;
    memcpy(copy, blob, blob_len);
    copy[blob_len] = 0;
    cursor = copy;
    header_end = copy + blob_len;

    line = memchr(cursor, '\\n', (size_t)(header_end - cursor));
    if (!line) goto cleanup;
    *line = 0;
    if (strcmp(cursor, "PAXP") != 0) goto cleanup;
    cursor = line + 1;

    line = memchr(cursor, '\\n', (size_t)(header_end - cursor));
    if (!line) goto cleanup;
    *line = 0;
    count = strtoul(cursor, NULL, 10);
    entries = calloc((size_t)(count ? count : 1), sizeof(*entries));
    if (!entries) goto cleanup;
    cursor = line + 1;

    while (cursor < header_end) {
        char *tab;
        line = memchr(cursor, '\\n', (size_t)(header_end - cursor));
        if (!line) goto cleanup;
        *line = 0;
        if (*cursor == 0) {
            data_start = line + 1;
            break;
        }
        tab = strchr(cursor, '\\t');
        if (!tab || entry_index >= count) goto cleanup;
        *tab = 0;
        entries[entry_index].path = cursor;
        entries[entry_index].len = strtoul(tab + 1, NULL, 10);
        entries[entry_index].offset = offset;
        offset += entries[entry_index].len;
        entry_index++;
        cursor = line + 1;
    }
    if (!data_start) goto cleanup;
    if (entry_index != count) goto cleanup;
    if ((unsigned long)(header_end - data_start) < offset) goto cleanup;

    mkdir(root, 0700);
    for (unsigned long i = 0; i < count; i++) {
        char path[4096];
        FILE *out;
        snprintf(path, sizeof(path), "%s/%s", root, entries[i].path);
        ensure_parent_dirs(path);
        out = fopen(path, "wb");
        if (!out) goto cleanup;
        if (entries[i].len > 0 && fwrite(data_start + entries[i].offset, 1, entries[i].len, out) != entries[i].len) {
            fclose(out);
            goto cleanup;
        }
        fclose(out);
    }
    rc = 0;

cleanup:
    free(entries);
    free(copy);
    return rc;
}

static int append_path(char *buffer, size_t size, const char *path) {
    if (!path || !*path) return 0;
    size_t len = strlen(buffer);
    if (len > 0) {
        if (len + 1 >= size) return 111;
        buffer[len++] = ':';
        buffer[len] = 0;
    }
    if (len + strlen(path) >= size) return 111;
    memcpy(buffer + len, path, strlen(path) + 1);
    return 0;
}

static int extract_roots(const char *root, char *code_root, size_t code_size, char *runtime_root, size_t runtime_size, char *assets_root, size_t assets_size) {
    if (snprintf(code_root, code_size, "%s/code", root) >= (int)code_size) return 111;
    if (snprintf(runtime_root, runtime_size, "%s/runtime", root) >= (int)runtime_size) return 111;
    if (snprintf(assets_root, assets_size, "%s/assets", root) >= (int)assets_size) return 111;
    if (write_package_root(code_root, _binary_code_pkg_start, (unsigned long)(_binary_code_pkg_end - _binary_code_pkg_start)) != 0) return 111;
    if (write_package_root(runtime_root, _binary_runtime_pkg_start, (unsigned long)(_binary_runtime_pkg_end - _binary_runtime_pkg_start)) != 0) return 111;
    if (write_package_root(assets_root, _binary_assets_pkg_start, (unsigned long)(_binary_assets_pkg_end - _binary_assets_pkg_start)) != 0) return 111;
    if ($native_package_present && write_package_root(root, _binary_native_pkg_start, (unsigned long)(_binary_native_pkg_end - _binary_native_pkg_start)) != 0) return 111;
    return 0;
}

static int extract_runtime(char *tmpdir, size_t size, char *entrypoint, size_t entry_size, char *perl_exec, size_t perl_size, char *libpath, size_t lib_size, char *asset_root, size_t asset_size) {
    const char *base = getenv("TMPDIR");
    if (!base || !*base) base = "/tmp";
    if (snprintf(tmpdir, size, "%s/pax-standalone-XXXXXX", base) >= (int)size) return 111;
    if (!mkdtemp(tmpdir)) return 111;
    char code_root[4096];
    char runtime_root[4096];
    char assets_root[4096];
    char runtime_lib_root[4096];
    char manifest_path[4096];
    FILE *manifest_out;
    if (extract_roots(tmpdir, code_root, sizeof(code_root), runtime_root, sizeof(runtime_root), assets_root, sizeof(assets_root)) != 0) return 111;
    if (snprintf(manifest_path, sizeof(manifest_path), "%s/manifest.json", tmpdir) >= (int)sizeof(manifest_path)) return 111;
    manifest_out = fopen(manifest_path, "wb");
    if (!manifest_out) return 111;
    if (fwrite($manifest_literal, 1, strlen($manifest_literal), manifest_out) != strlen($manifest_literal)) {
        fclose(manifest_out);
        return 111;
    }
    fclose(manifest_out);

    if (snprintf(entrypoint, entry_size, "%s/%s", code_root, $entrypoint_logical) >= (int)entry_size) return 111;
    if (snprintf(asset_root, asset_size, "%s", assets_root) >= (int)asset_size) return 111;
    if (snprintf(runtime_lib_root, sizeof(runtime_lib_root), "%s/lib", runtime_root) >= (int)sizeof(runtime_lib_root)) return 111;
    if (strcmp($runtime_mode, "bundled_perl") == 0 && strlen($runtime_perl) > 0) {
        if (snprintf(perl_exec, perl_size, "%s/%s", runtime_root, $runtime_perl) >= (int)perl_size) return 111;
        chmod(perl_exec, 0700);
    } else {
        if (snprintf(perl_exec, perl_size, "%s", "perl") >= (int)perl_size) return 111;
    }
    libpath[0] = 0;
    for (unsigned long i = 0; i < pax_code_lib_roots_count; i++) {
        char top[4096];
        if (snprintf(top, sizeof(top), "%s/%s", code_root, pax_code_lib_roots[i]) >= (int)sizeof(top)) return 111;
        if (append_path(libpath, lib_size, top) != 0) return 111;
    }
    for (unsigned long i = 0; i < pax_runtime_inc_roots_count; i++) {
        char top[4096];
        if (snprintf(top, sizeof(top), "%s/%s", runtime_root, pax_runtime_inc_roots[i]) >= (int)sizeof(top)) return 111;
        if (append_path(libpath, lib_size, top) != 0) return 111;
    }

    setenv("PAX_EMBEDDED_ASSET_ROOT", asset_root, 1);
    setenv("PAX_STANDALONE_TMPDIR", tmpdir, 1);
    setenv("PAX_STANDALONE_MANIFEST_PATH", manifest_path, 1);
    if (access(runtime_lib_root, F_OK) == 0) {
        const char *old_ld = getenv("LD_LIBRARY_PATH");
        char merged_ld[16384];
        if (old_ld && *old_ld) snprintf(merged_ld, sizeof(merged_ld), "%s:%s", runtime_lib_root, old_ld);
        else snprintf(merged_ld, sizeof(merged_ld), "%s", runtime_lib_root);
        setenv("LD_LIBRARY_PATH", merged_ld, 1);
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "--pax-standalone-inspect") == 0) {
        puts($manifest_literal);
        return 0;
    }
    if (argc > 2 && strcmp(argv[1], "--pax-standalone-extract") == 0) {
        char code_root[4096];
        char runtime_root[4096];
        char assets_root[4096];
        if (mkdir(argv[2], 0700) != 0 && errno != EEXIST) return 111;
        if (extract_roots(argv[2], code_root, sizeof(code_root), runtime_root, sizeof(runtime_root), assets_root, sizeof(assets_root)) != 0) return 111;
        puts(argv[2]);
        return 0;
    }

    char tmpdir[4096];
    char entrypoint[4096];
    char perl_exec[4096];
    char libpath[8192];
    char asset_root[4096];
    if (extract_runtime(tmpdir, sizeof(tmpdir), entrypoint, sizeof(entrypoint), perl_exec, sizeof(perl_exec), libpath, sizeof(libpath), asset_root, sizeof(asset_root)) != 0) {
        fprintf(stderr, "failed to extract standalone payload\\n");
        return 111;
    }

    if (strlen(libpath) > 0) {
        const char *old = getenv("PERL5LIB");
        char merged[16384];
        if (old && *old) snprintf(merged, sizeof(merged), "%s:%s", libpath, old);
        else snprintf(merged, sizeof(merged), "%s", libpath);
        setenv("PERL5LIB", merged, 1);
    }

    char **next = calloc((size_t)argc + 5, sizeof(char *));
    if (!next) return 111;
    next[0] = perl_exec;
    next[1] = "-MPAX::StandaloneRuntime";
    next[2] = "-e";
    next[3] = $bootstrap_code;
    next[4] = entrypoint;
    for (int i = 1; i < argc; i++) next[i + 4] = argv[i];
    if (strcmp($runtime_mode, "bundled_perl") == 0) {
        execv(perl_exec, next);
        perror("execv bundled perl");
        return 111;
    }
    execvp("perl", next);
    perror("execvp perl");
    return 111;
}
C
}

sub _manifest_without_bytes {
    my ($manifest) = @_;
    my %copy = %$manifest;
    $copy{code_units} = [ map { _strip_payload($_) } @{ $manifest->{code_units} // [] } ];
    $copy{runtime_payloads} = [ map { _strip_payload($_) } @{ $manifest->{runtime_payloads} // [] } ];
    $copy{assets} = [ map { _strip_payload($_) } @{ $manifest->{assets} // [] } ];
    $copy{native_payloads} = [ map { _strip_payload($_) } @{ $manifest->{native_payloads} // [] } ];
    return \%copy;
}

sub _strip_payload {
    my ($item) = @_;
    my %copy = %$item;
    delete $copy{bytes};
    return \%copy;
}

sub _payload_package_blob {
    my ($items) = @_;
    my $header = "PAXP\n" . scalar(@$items) . "\n";
    my $data = '';
    for my $item (@$items) {
        $header .= $item->{logical_path} . "\t" . $item->{size} . "\n";
        $data .= $item->{bytes};
    }
    $header .= "\n";
    return $header . $data;
}

sub _native_payloads {
    my ($items) = @_;
    my @payloads;
    for my $item (@$items) {
        next if !$item->{executable_path} || !-f $item->{executable_path};
        push @payloads, _file_payload(
            $item->{executable_path},
            'native_executable',
            _safe_logical_path(File::Spec->catfile('native', $item->{region_id}, 'probe')),
        );
        if ($item->{library_path} && -f $item->{library_path}) {
            push @payloads, _file_payload(
                $item->{library_path},
                'native_library',
                _safe_logical_path(File::Spec->catfile('native', $item->{region_id}, 'library.so')),
            );
        }
        if (($item->{tier2_artifact}{path} // '') && -f $item->{tier2_artifact}{path}) {
            push @payloads, _file_payload(
                $item->{tier2_artifact}{path},
                'native_ir',
                _safe_logical_path(File::Spec->catfile('native', $item->{region_id}, 'module.ll')),
            );
        }
    }
    return \@payloads;
}

sub _native_dispatch_manifest {
    my ($items) = @_;
    my @dispatch;
    for my $item (@$items) {
        next if !$item->{region_id};
        push @dispatch, {
            region_id => $item->{region_id},
            region_name => $item->{region_name},
            status => $item->{status},
            entry_kind => $item->{entry_kind},
            reason => $item->{reason},
            guards => $item->{guards} // [],
            deopt => $item->{deopt} // {},
            executable_logical_path => $item->{executable_path}
                ? _safe_logical_path(File::Spec->catfile('native', $item->{region_id}, 'probe'))
                : undef,
            library_logical_path => $item->{library_path}
                ? _safe_logical_path(File::Spec->catfile('native', $item->{region_id}, 'library.so'))
                : undef,
            tier2_logical_path => (($item->{tier2_artifact}{path} // '') ne '')
                ? _safe_logical_path(File::Spec->catfile('native', $item->{region_id}, 'module.ll'))
                : undef,
        };
    }
    return \@dispatch;
}

sub _strip_native_runtime_paths {
    my ($item) = @_;
    my %copy = %$item;
    delete $copy{executable_path};
    delete $copy{library_path};
    if (ref $copy{tier2_artifact} eq 'HASH') {
        my %tier2 = %{ $copy{tier2_artifact} };
        delete $tier2{path};
        $copy{tier2_artifact} = \%tier2;
    }
    return \%copy;
}

sub _string_array_c {
    my ($name, $items) = @_;
    return "static const unsigned long ${name}_count = 0;\nstatic const char *${name}[] = { 0 };\n" if !$items || !@$items;
    my @chunks;
    push @chunks, "static const unsigned long ${name}_count = " . scalar(@$items) . ";\n";
    push @chunks, "static const char *${name}[] = {\n";
    push @chunks, '    ' . _c_string($_) . ",\n" for @$items;
    push @chunks, "};\n";
    return join '', @chunks;
}

sub _runtime_manifest {
    my (%args) = @_;
    my $mode = $args{mode} // 'bundled_perl';
    my @payloads;
    my @bundled_inc_roots;
    my $index = 0;
    my @helper_payloads = _pax_runtime_helper_payloads(
        \$index,
        \@bundled_inc_roots,
        $args{app_namespace} // '',
        $args{app_legacy_namespace} // '',
    );
    my @helper_module_files = _pax_runtime_helper_module_files();
    my @force_runtime_source_files = (
        @helper_module_files,
        map {
            my $path = $_->{source_path} // ();
            $path ? ($path) : ()
        } grep {
            ($_->{class} // '') eq 'compiled_dependency'
                && (($_->{packaging} // '') eq 'hybrid_compiled_pcu_v1')
        } @{ $args{dependencies} // [] },
    );

    my $perl;
    if ($mode eq 'bundled_perl') {
        $perl = abs_path($^X) || $^X;
        my @inc_dirs = _runtime_inc_dirs($args{exclude_dirs} // []);
        push @payloads, _file_payload($perl, 'runtime_binary', 'bin/perl');
        push @payloads, _runtime_shared_lib_payloads($perl, \@inc_dirs);
        my @selected = _runtime_selected_files(
            inc_dirs => \@inc_dirs,
            dependencies => $args{dependencies} // [],
            lib_dirs => $args{lib_dirs} // [],
            exclude_files => $args{exclude_files} // [],
        );
        if (@selected) {
            my %by_dir;
            for my $path (@selected) {
                my $root = _inc_root_for_file($path, \@inc_dirs) or next;
                push @{ $by_dir{$root} }, $path;
            }
            for my $dir (@inc_dirs) {
                my $files = $by_dir{$dir} or next;
                my $prefix = sprintf('inc/%03d', $index++);
                push @bundled_inc_roots, $prefix;
                push @payloads, _file_list_payloads($dir, $prefix, 'runtime_inc', $files, $args{exclude_files} // [], \@force_runtime_source_files);
            }
            for my $dir (@inc_dirs) {
                next if !_is_core_runtime_inc_dir($dir);
                my $prefix = sprintf('inc/%03d', $index++);
                push @bundled_inc_roots, $prefix;
                push @payloads, _tree_payloads($dir, $prefix, 'runtime_inc', []);
            }
            for my $dir (@inc_dirs) {
                next if !_is_site_runtime_inc_dir($dir);
                my $prefix = sprintf('inc/%03d', $index++);
                push @bundled_inc_roots, $prefix;
                push @payloads, _tree_payloads($dir, $prefix, 'runtime_inc', []);
            }
        } else {
            for my $dir (@inc_dirs) {
                my $prefix = sprintf('inc/%03d', $index++);
                push @bundled_inc_roots, $prefix;
                push @payloads, _tree_payloads($dir, $prefix, 'runtime_inc', $args{exclude_files} // []);
            }
        }
    }
    push @payloads, @helper_payloads;

    my $sha = Digest::SHA->new(256);
    for my $payload (sort { $a->{logical_path} cmp $b->{logical_path} } @payloads) {
        $sha->add($payload->{logical_path});
        $sha->add($payload->{sha256});
    }
    return {
        payloads => \@payloads,
        bundled_inc_roots => \@bundled_inc_roots,
        perl_binary => $perl,
        perl_binary_logical_path => ($mode eq 'bundled_perl' ? 'bin/perl' : undef),
        runtime_hash => $sha->hexdigest,
    };
}

sub _pax_runtime_helper_payloads {
    my ($index_ref, $roots, $app_namespace, $legacy_namespace) = @_;
    $app_namespace = _normalize_namespace($app_namespace);
    $legacy_namespace = _normalize_namespace($legacy_namespace);
    my @helpers = _pax_runtime_helper_relative_paths();
    my @payloads;
    my @helper_roots = _pax_runtime_helper_lib_roots();
    return @payloads if !@helper_roots;
    my $prefix = sprintf('inc/%03d', $$index_ref++);
    push @$roots, $prefix;
    for my $rel (@helpers) {
        my $path = _helper_module_path($rel, \@helper_roots);
        next if !-f $path;
        my $logical = _safe_logical_path(File::Spec->catfile($prefix, $rel));
        if ($rel eq 'PAX/StandaloneRuntime.pm' && $app_namespace) {
            my $bytes = _replace_runtime_namespace(
                _slurp_bytes($path),
                $app_namespace,
                $legacy_namespace,
            );
            push @payloads, _file_payload_bytes($path, 'runtime_helper', $logical, $bytes);
            next;
        }
        push @payloads, _file_payload($path, 'runtime_helper', $logical);
    }
    return @payloads;
}

sub _runtime_shared_lib_payloads {
    my ($perl, $runtime_inc_dirs) = @_;
    return () if !$perl || !-x $perl;
    my $ldd = _which('ldd') || ((-x '/usr/bin/ldd') ? '/usr/bin/ldd' : '');
    return () if $ldd eq '';
    open my $fh, '-|', $ldd, $perl or return ();
    my @payloads;
    my %seen;
    while (my $line = <$fh>) {
        my $path;
        if ($line =~ /=>\s+(\S+)\s+\(/) {
            $path = $1;
        } elsif ($line =~ /^\s*(\/\S+)\s+\(/) {
            $path = $1;
        } else {
            next;
        }
        next if !$path || !-f $path;
        my $abs = abs_path($path) || $path;
        next if $seen{$abs}++;
        push @payloads, _file_payload($abs, 'runtime_lib', _safe_logical_path(File::Spec->catfile('lib', File::Basename::basename($abs))));
    }

    for my $runtime_lib (_runtime_core_libs_from_inc_dirs($runtime_inc_dirs // [])) {
        my $abs = abs_path($runtime_lib) || $runtime_lib;
        next if $seen{$abs}++;
        push @payloads, _file_payload($abs, 'runtime_lib', _safe_logical_path(File::Spec->catfile('lib', File::Basename::basename($abs))));
    }
    close $fh;
    return @payloads;
}

sub _which {
    my ($program) = @_;
    return if !defined $program || $program eq '';
    my %seen;
    my @dirs = split /:/, ($ENV{PATH} // '');
    push @dirs, qw(/usr/bin /bin /usr/sbin /sbin /usr/local/bin);
    for my $dir (@dirs) {
        next if !defined $dir || $dir eq '';
        next if $seen{$dir}++;
        my $path = File::Spec->catfile($dir, $program);
        return $path if -x $path;
    }
    return;
}

sub _runtime_core_libs_from_inc_dirs {
    my ($inc_dirs) = @_;
    my @libs;
    my %seen;
    my @dirs = grep { defined $_ && $_ ne '' } map { abs_path($_) || $_ } @{ $inc_dirs // [] };
    for my $dir (@dirs) {
        next if !-d $dir;
        File::Find::find({
            wanted => sub {
                return if !-f $_;
                return unless m{/CORE/libperl} && m/\.(?:so|dylib|dll)(?:\.[^\/\\]+)?\z/;
                my $abs = abs_path($File::Find::name) || $File::Find::name;
                return if $seen{$abs}++;
                push @libs, $abs;
            },
            no_chdir => 1,
        }, $dir);
    }
    return @libs;
}

sub _runtime_inc_dirs {
    my ($exclude_dirs) = @_;
    my %exclude = map { $_ => 1 } grep { defined && length } map { abs_path($_) || $_ } @$exclude_dirs;
    my %seen;
    my @dirs;
    for my $dir (@INC) {
        next if ref $dir;
        my $abs = abs_path($dir);
        next if !defined $abs || !-d $abs;
        next if $exclude{$abs};
        next if $abs =~ m{\A/home/mv/projects/pax(?:/|$)};
        next if $seen{$abs}++;
        push @dirs, $abs;
    }
    return @dirs;
}

sub _is_core_runtime_inc_dir {
    my ($dir) = @_;
    return 0 if !$dir;
    return 0 if $dir =~ m{/site_perl(?:/|$)};
    return 0 if $dir =~ m{/vendor_perl(?:/|$)};
    return ($dir =~ m{/perl5/\d+\.\d+\.\d+(?:/x86_64-linux-gnu)?\z}) ? 1 : 0;
}

sub _is_site_runtime_inc_dir {
    my ($dir) = @_;
    return 0 if !$dir;
    return ($dir =~ m{/site_perl/\d+\.\d+\.\d+(?:/x86_64-linux-gnu)?\z}) ? 1 : 0;
}

sub _runtime_selected_files {
    my (%args) = @_;
    my @modules = map { $_->{module} }
        grep {
            my $class = $_->{class} // '';
            ($_->{module} // '') ne ''
                && (
                    $class eq 'bundled_pure_perl'
                    || $class eq 'bundled_xs'
                    || ($class eq 'compiled_dependency' && (($_->{packaging} // '') eq 'hybrid_compiled_pcu_v1'))
                )
        } @{ $args{dependencies} // [] };
    my @helper_module_files = _pax_runtime_helper_module_files();
    my @hybrid_dependency_files = map {
        my $path = $_->{source_path} // ();
        $path ? ($path) : ()
    } grep {
        ($_->{class} // '') eq 'compiled_dependency'
            && (($_->{packaging} // '') eq 'hybrid_compiled_pcu_v1')
    } @{ $args{dependencies} // [] };
    push @modules, _pax_runtime_helper_modules();
    my %seen_module;
    @modules = grep { !$seen_module{$_}++ } @modules;
    return () if !@modules;

    my @loaded = _probe_loaded_runtime_files(
        modules => \@modules,
        lib_dirs => $args{lib_dirs} // [],
    );
    for my $module (@modules) {
        my $path = _locate_module_runtime_file($module) or next;
        push @loaded, $path;
    }
    my %selected = map { $_ => 1 } _expand_runtime_module_files(
        inc_dirs => $args{inc_dirs} // [],
        seed_files => [ @loaded, @helper_module_files ],
    );

    for my $dep (@{ $args{dependencies} // [] }) {
        next if ($dep->{class} // '') ne 'bundled_xs';
        my $module = $dep->{module} // next;
        my $source = $dep->{source_path} // next;
        $selected{$source} = 1 if -f $source;
        for my $path (_related_xs_files($module, $source, $args{inc_dirs} // [])) {
            $selected{$path} = 1 if -f $path;
        }
    }

    my %force = map { $_ => 1 } (@helper_module_files, @hybrid_dependency_files);
    for my $path (@{ $args{exclude_files} // [] }) {
        my $abs = abs_path($path) || $path;
        delete $selected{$abs} if !$force{$abs};
    }

    return sort keys %selected;
}

sub _expand_runtime_module_files {
    my (%args) = @_;
    my @queue = grep { defined && -f $_ } @{ $args{seed_files} // [] };
    my %selected;
    while (my $path = shift @queue) {
        my $abs = abs_path($path) || $path;
        next if $selected{$abs}++;
        for my $family_file (_runtime_family_files_for($abs)) {
            my $fam_abs = abs_path($family_file) || $family_file;
            next if $selected{$fam_abs};
            push @queue, $fam_abs;
        }
        for my $related (_related_xs_files_for_source($abs, $args{inc_dirs} // [])) {
            my $rel_abs = abs_path($related) || $related;
            $selected{$rel_abs} = 1 if -f $rel_abs;
        }
        next if $abs !~ /\.(?:pm|pl)\z/;
        my $source = _slurp_bytes($abs);
        for my $module (_declared_modules($source)) {
            next if _skip_dependency_module($module);
            my $dep_path = _locate_module_runtime_file($module) or next;
            my $dep_abs = abs_path($dep_path) || $dep_path;
            next if $selected{$dep_abs};
            push @queue, $dep_abs;
        }
    }
    return sort keys %selected;
}

sub _runtime_family_files_for {
    my ($path) = @_;
    my $module = _module_name_from_source_path($path) or return ();
    my ($family) = split /::/, $module;
    return () if !$family;
    return @{ $RUNTIME_FAMILY_FILE_CACHE{$family} } if exists $RUNTIME_FAMILY_FILE_CACHE{$family};
    my @files;
    my %seen;
    for my $inc (@INC) {
        next if ref $inc;
        my $root = File::Spec->catdir($inc, $family);
        next if !-d $root;
        File::Find::find({
            wanted => sub {
                return if !-f $_;
                return if $_ !~ /\.pm\z/;
                my $abs = abs_path($File::Find::name) || $File::Find::name;
                return if $seen{$abs}++;
                push @files, $abs;
            },
            no_chdir => 1,
        }, $root);
    }
    $RUNTIME_FAMILY_FILE_CACHE{$family} = \@files;
    return @files;
}

sub _locate_module_runtime_file {
    my ($module) = @_;
    return if !$module;
    my $rel = $module;
    $rel =~ s{::}{/}g;
    $rel .= '.pm';
    for my $inc (@INC) {
        next if ref $inc;
        my $path = File::Spec->catfile($inc, $rel);
        next if !-f $path;
        return abs_path($path) || $path;
    }
    return;
}

sub _pax_runtime_helper_relative_paths {
    return qw(
        PAX/StandaloneRuntime.pm
        PAX/NativeRunner.pm
        PAX/GuardManager.pm
        PAX/DeoptEngine.pm
    );
}

sub _pax_runtime_helper_lib_roots {
    my %seen;
    my @roots;

    my $loaded = $INC{'PAX/StandaloneImage.pm'} || __FILE__;
    my $abs = abs_path($loaded) || $loaded;
    my @parts = File::Spec->splitdir($abs);
    while (@parts) {
        my $candidate = File::Spec->catdir(@parts);
        if (-f File::Spec->catfile($candidate, 'PAX', 'StandaloneImage.pm')) {
            push @roots, $candidate if !$seen{$candidate}++;
        }
        pop @parts;
    }

    for my $inc (@INC) {
        next if ref $inc;
        next if !defined $inc || $inc eq '';
        my $abs_inc = abs_path($inc) || $inc;
        push @roots, $abs_inc if -f File::Spec->catfile($abs_inc, 'PAX', 'StandaloneRuntime.pm')
            && !$seen{$abs_inc}++;
    }

    my $cwd_lib = abs_path('lib');
    if (defined $cwd_lib && -d $cwd_lib) {
        push @roots, $cwd_lib if !$seen{$cwd_lib}++;
    }

    return @roots;
}

sub _pax_runtime_helper_modules {
    my @helpers = qw(
        PAX/StandaloneRuntime.pm
        PAX/NativeRunner.pm
        PAX/GuardManager.pm
        PAX/DeoptEngine.pm
    );
    my @roots = _pax_runtime_helper_lib_roots();
    return () if !@roots;
    my %seen;
    my @modules;
    for my $rel (@helpers) {
        my $path = _helper_module_path($rel, \@roots);
        next if !-f $path;
        my $source = _slurp_bytes($path);
        while ($source =~ /^\s*use\s+([A-Za-z_][A-Za-z0-9_:]*)\b/gm) {
            my $module = $1;
            next if $module =~ /^PAX::/;
            push @modules, $module if !$seen{$module}++;
        }
        while ($source =~ /^\s*require\s+([A-Za-z_][A-Za-z0-9_:]*)\b/gm) {
            my $module = $1;
            next if $module =~ /^PAX::/;
            push @modules, $module if !$seen{$module}++;
        }
    }
    for my $module (qw(XSLoader)) {
        push @modules, $module if !$seen{$module}++;
    }
    return @modules;
}

sub _pax_runtime_helper_module_files {
    my @roots = _pax_runtime_helper_lib_roots();
    my @modules = _pax_runtime_helper_modules();
    my @files;
    my %seen;
    for my $rel (_pax_runtime_helper_relative_paths()) {
        my $path = _helper_module_path($rel, \@roots);
        next if !$path;
        push @files, $path if !$seen{$path}++;
    }
    for my $module (@modules) {
        my $path = _locate_module_runtime_file($module) or next;
        push @files, $path if !$seen{$path}++;
    }
    for my $path (_probe_loaded_runtime_files(modules => \@modules, lib_dirs => [])) {
        push @files, $path if !$seen{$path}++;
    }
    return @files;
}

sub _helper_module_path {
    my ($rel, $roots) = @_;
    return if !$rel;
    for my $root (@{ $roots // [] }) {
        next if !defined $root || $root eq '';
        my $path = File::Spec->catfile($root, split m{/}, $rel);
        return $path if -f $path;
    }
    return;
}

sub _probe_loaded_runtime_files {
    my (%args) = @_;
    my @modules = @{ $args{modules} // [] };
    return () if !@modules;

    my ($fh, $path) = tempfile(
        'pax-runtime-probe-XXXXXX',
        SUFFIX => '.pl',
        TMPDIR => 1,
        UNLINK => 1,
    );
    print {$fh} <<'PL';
use strict;
use warnings;
use JSON::PP qw(encode_json decode_json);

my $payload = decode_json($ENV{PAX_RUNTIME_PROBE_PAYLOAD} // '{}');
unshift @INC, @{ $payload->{lib_dirs} // [] };
my %before = map { $_ => 1 } keys %INC;

for my $module (@{ $payload->{modules} // [] }) {
    (my $require_path = $module) =~ s{::}{/}g;
    $require_path .= '.pm';
    eval { require $require_path; 1 } or next;
}

my @files;
for my $key (sort keys %INC) {
    next if $before{$key};
    my $value = $INC{$key};
    next if !defined $value || ref $value;
    push @files, $value if $value ne '';
}

print encode_json(\@files);
PL
    close $fh;

    my $payload = JSON::PP->new->ascii(1)->canonical(1)->encode({
        modules => \@modules,
        lib_dirs => [ map { abs_path($_) || $_ } @{ $args{lib_dirs} // [] } ],
    });
    local $ENV{PAX_RUNTIME_PROBE_PAYLOAD} = $payload;
    my $output = qx{$^X $path};
    my $exit = $? >> 8;
    return () if $exit != 0 || !defined $output || $output eq '';
    my $decoded = eval { JSON::PP::decode_json($output) };
    return () if $@ || ref($decoded) ne 'ARRAY';
    my %seen;
    return grep { defined $_ && -f $_ && !$seen{$_}++ } @$decoded;
}

sub _related_xs_files {
    my ($module, $source, $inc_dirs) = @_;
    my @parts = split /::/, $module;
    my $leaf = $parts[-1];
    my @roots = @{ $inc_dirs // [] };
    if (!@roots) {
        my $root = _inc_root_for_file($source, $inc_dirs);
        @roots = defined $root ? ($root) : ();
    }
    my @candidates;
    for my $root (@roots) {
        push @candidates,
            File::Spec->catfile($root, 'auto', @parts, "$leaf.so"),
            File::Spec->catfile($root, 'auto', @parts, "$leaf.bundle"),
            File::Spec->catfile($root, 'auto', @parts, "$leaf.dll"),
            File::Spec->catfile($root, 'auto', @parts, "$leaf.bs");
    }
    my %seen;
    return grep { -f $_ && !$seen{$_}++ } @candidates;
}

sub _related_xs_files_for_source {
    my ($source, $inc_dirs) = @_;
    return () if !$source;
    my $root = _inc_root_for_file($source, $inc_dirs) or return;
    my $abs = abs_path($source) || $source;
    my $rel = File::Spec->abs2rel($abs, $root);
    return () if !$rel || $rel !~ /\.pm\z/;
    $rel =~ s/\.pm\z//;
    my @parts = File::Spec->splitdir($rel);
    return () if !@parts;
    my $leaf = $parts[-1];
    my @candidates;
    for my $dir (@{ $inc_dirs // [] }) {
        push @candidates,
            File::Spec->catfile($dir, 'auto', @parts, "$leaf.so"),
            File::Spec->catfile($dir, 'auto', @parts, "$leaf.bundle"),
            File::Spec->catfile($dir, 'auto', @parts, "$leaf.dll"),
            File::Spec->catfile($dir, 'auto', @parts, "$leaf.bs");
    }
    my %seen;
    return grep { -f $_ && !$seen{$_}++ } @candidates;
}

sub _inc_root_for_file {
    my ($path, $inc_dirs) = @_;
    my $abs = abs_path($path) || $path;
    my @roots = sort { length($b) <=> length($a) } @{ $inc_dirs // [] };
    for my $dir (@roots) {
        return $dir if index($abs, $dir . '/') == 0 || $abs eq $dir;
    }
    return;
}

sub _file_list_payloads {
    my ($dir, $prefix, $kind, $files, $exclude_files, $force_include_files) = @_;
    my @payloads;
    my %exclude = map { (abs_path($_) || $_) => 1 } @{ $exclude_files // [] };
    my %force = map { (abs_path($_) || $_) => 1 } @{ $force_include_files // [] };
    my %seen;
    for my $path (@{ $files // [] }) {
        my $abs = abs_path($path) || $path;
        next if $exclude{$abs} && !$force{$abs};
        next if $seen{$abs}++;
        next if index($abs, $dir . '/') != 0 && $abs ne $dir;
        my $rel = File::Spec->abs2rel($abs, $dir);
        push @payloads, _file_payload($abs, $kind, _safe_logical_path(File::Spec->catfile($prefix, $rel)));
    }
    return @payloads;
}

sub _tree_payloads {
    my ($dir, $prefix, $kind, $exclude_files) = @_;
    my @payloads;
    my %exclude = map { (abs_path($_) || $_) => 1 } @{ $exclude_files // [] };
    File::Find::find({
        wanted => sub {
            return if !-f $_;
            my $abs = abs_path($File::Find::name) || $File::Find::name;
            return if $exclude{$abs};
            my $rel = File::Spec->abs2rel($File::Find::name, $dir);
            push @payloads, _file_payload($File::Find::name, $kind, _safe_logical_path(File::Spec->catfile($prefix, $rel)));
        },
        no_chdir => 1,
    }, $dir);
    return @payloads;
}

sub _file_payload {
    my ($path, $kind, $logical) = @_;
    my $abs = abs_path($path) || $path;
    my $bytes = _slurp_bytes($abs);
    return _file_payload_bytes($abs, $kind, $logical, $bytes);
}

sub _file_payload_bytes {
    my ($path, $kind, $logical, $bytes) = @_;
    return {
        source_path => $path,
        logical_path => $logical,
        unit_kind => $kind,
        size => length($bytes),
        sha256 => sha256_hex($bytes),
        c_symbol => 'pax_payload_' . sha256_hex($logical),
        bytes => $bytes,
    };
}

sub _normalize_namespace {
    my ($namespace) = @_;
    return '' if !defined $namespace;
    $namespace =~ s/^\s+|\s+$//g;
    $namespace =~ s/^\:+|\:+$//g;
    return $namespace;
}

sub _replace_runtime_namespace {
    my ($bytes, $app_namespace, $legacy_namespace) = @_;
    return $bytes if !$bytes || !defined $app_namespace || $app_namespace eq '';
    $legacy_namespace = _normalize_namespace($legacy_namespace);
    my $legacy = $legacy_namespace // '';

    my $legacy_marker = '__PAX_RUNTIME_LEGACY_NAMESPACE__';
    my $has_legacy_marker = index($bytes, $legacy_marker) >= 0 ? 1 : 0;
    if ($has_legacy_marker) {
        $legacy = $legacy_marker;
    } elsif ($legacy eq '' || $app_namespace eq $legacy) {
        $legacy = _infer_legacy_runtime_namespace($bytes);
    }
    return $bytes if $legacy eq '';

    return $bytes if !$has_legacy_marker && $app_namespace eq $legacy;

    if ($has_legacy_marker) {
        my $namespace = _normalize_namespace($app_namespace);
        my $namespace_path = $namespace;
        $namespace_path =~ s{::}{/}g;
        $bytes =~ s/\Q$legacy_marker\E/$namespace/g;
        $bytes =~ s/\Q${legacy_marker}\/\E/$namespace_path\//g;
        return $bytes;
    }

    my $namespace_path = $app_namespace;
    $namespace_path =~ s{::}{/}g;
    my $legacy_path = $legacy;
    $legacy_path =~ s{::}{/}g;
    $bytes =~ s/\Q$legacy\E/$app_namespace/g;
    $bytes =~ s/\Q$legacy_path\E/$namespace_path/g;
    return $bytes;
}

sub _infer_legacy_runtime_namespace {
    my ($bytes) = @_;
    return '' if !$bytes || $bytes eq '';
    my %counts;
    while ($bytes =~ /(?<![A-Za-z0-9_])([A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)+)\b/g) {
        my $module = $1;
        my @parts = split /::/, $module;
        next if @parts < 2;
        for my $depth (2 .. @parts) {
            my $prefix = join('::', @parts[0 .. $depth - 1]);
            $counts{$prefix}++;
        }
    }
    my ($best, $best_score, $best_depth) = ('', 0, 0);
    for my $candidate (keys %counts) {
        my $depth = scalar split /::/, $candidate;
        next if $depth < 2;
        my $score = ($counts{$candidate} * 1000) + $depth;
        if ($score > $best_score || ($score == $best_score && $depth > $best_depth)) {
            $best = $candidate;
            $best_score = $score;
            $best_depth = $depth;
        }
    }
    return $best;
}

sub _module_uses_xs {
    my ($path) = @_;
    my $source = _slurp_bytes($path);
    return 1 if $source =~ /\b(?:XSLoader|DynaLoader)\b/;
    my $base = $path;
    $base =~ s/\.pm$//;
    for my $ext (qw(so bundle dll)) {
        return 1 if -f "$base.$ext";
    }
    return 0;
}

sub _logical_name {
    my ($path) = @_;
    my ($vol, $dir, $file) = File::Spec->splitpath($path);
    return $file;
}

sub _safe_logical_path {
    my ($path) = @_;
    my @parts = grep { length && $_ ne '.' && $_ ne '..' } File::Spec->splitdir($path);
    return join '/', @parts;
}

sub _c_string {
    my ($value) = @_;
    $value =~ s/\\/\\\\/g;
    $value =~ s/"/\\"/g;
    $value =~ s/\n/\\n/g;
    return '"' . $value . '"';
}

sub _write_json {
    my ($path, $data) = @_;
    my $dir = dirname($path);
    make_path($dir) if length $dir && !-d $dir;
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} JSON::PP->new->ascii(1)->canonical(1)->pretty(1)->encode(_manifest_without_bytes($data));
    close $fh;
}

sub _write_binary {
    my ($path, $bytes) = @_;
    my $dir = dirname($path);
    make_path($dir) if length $dir && !-d $dir;
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print {$fh} $bytes;
    close $fh;
}

sub _slurp_bytes {
    my ($path) = @_;
    open my $fh, '<:raw', $path or return '';
    local $/;
    return <$fh> // '';
}

1;

__END__

=head1 NAME

PAX::StandaloneImage - build standalone PAX executable images

=head1 DESCRIPTION

This module packages an entrypoint, compiled code units, runtime helpers,
dependency payloads, native artifacts, and assets into one executable. Runtime
helper discovery is independent of the current working directory, so C<pax build
-o output bin/pax> can be launched from a directory with no local C<lib/>
directory.

=head1 METHODS

=head2 new

Constructs a standalone image builder.

=head2 build

Builds a standalone executable from entrypoint, library paths, source roots,
cpanfile inputs, assets, output path, and runtime mode.

=head2 load

Loads a previously written standalone image manifest by name.

=cut
