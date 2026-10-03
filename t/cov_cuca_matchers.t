use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::CodeUnitCompiler;

=pod

=head1 NAME

t/cov_cuca_matchers.t - source-shape matcher coverage for the code-unit compiler

=head1 WHY IT EXISTS

The code-unit compiler recognises declared subs by loose regexes against sub
bodies. Each recogniser needs a body it accepts and near-miss bodies it rejects,
so both outcomes of every matcher are exercised without any external checkout.

=head1 DESCRIPTION

The DATA section holds one fixture sub per recogniser (header line gives package,
sub name, expected op, the body line numbers whose removal must break the
match, and the count of identifier-replacement near-misses that must be rejected). Each fixture is compiled whole and must yield the expected op; then every
single-line deletion is compiled and must be rejected exactly for the listed lines.

=cut

my @fixtures;
{
    my $current;
    while (my $line = <DATA>) {
        if ($line =~ /^#\@\@ (\S+) (\S+) (\S+) (\S*) w(\d+) p([01])$/) {
            $current = { pkg => $1, name => $2, op => $3, rej => [ split /,/, $4 ], words => $5, pkg_rejects => $6, text => '' };
            push @fixtures, $current;
            next;
        }
        $line =~ s/^  //;
        if ($line =~ /^#%% (\S+)$/) {
            push @{ $current->{adds} }, $1;
            next;
        }
        if ($line =~ /^#-- (.+)$/) {
            push @{ $current->{cuts} }, $1;
            next;
        }
        $current->{text} .= $line;
    }
}

# compile_fixture($fixture, $text)
# Compiles one fixture sub text through the declared-sub recogniser.
# Input: fixture hash and sub source text. Output: compiled record or undef.
sub compile_fixture {
    my ($fx, $text) = @_;
    my $source = "package $fx->{pkg};\nuse strict;\n$text\n1;\n";
    return PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped($source, "$fx->{pkg}::$fx->{name}");
}

for my $fx (@fixtures) {
    my $label = "$fx->{pkg}::$fx->{name}";
    my $text = $fx->{text};
    $text =~ s/\n+\z//;
    my $record = compile_fixture($fx, $text);
    is($record && $record->{op}, $fx->{op}, "$label compiles to $fx->{op}");
    my @lines = split /\n/, $text, -1;
    my @rejected;
    for my $index (1 .. $#lines - 1) {
        my @mutant = @lines;
        splice @mutant, $index, 1;
        my $result = compile_fixture($fx, join("\n", @mutant));
        push @rejected, $index unless $result && ($result->{op} // '') eq $fx->{op};
    }
    is_deeply(\@rejected, $fx->{rej}, "$label rejects exactly the near-miss bodies that lose a required line");
    for my $word (@{ $fx->{adds} || [] }) {
        my @mutant = @lines;
        splice @mutant, -1, 0, "# $word";
        my $result = compile_fixture($fx, join("\n", @mutant));
        ok(!($result && ($result->{op} // '') eq $fx->{op}), "$label rejects a body that also mentions $word");
    }
    for my $cut (@{ $fx->{cuts} || [] }) {
        (my $mutant = $text) =~ s/\Q$cut\E/ZZ/g;
        my $result = compile_fixture($fx, $mutant);
        ok(!($result && ($result->{op} // '') eq $fx->{op}), "$label rejects a body without $cut");
    }
    my %seen_word;
    my $word_rejects = 0;
    for my $word (grep { !$seen_word{$_}++ } ($text =~ /[A-Za-z_]\w*/g)) {
        (my $mutant = $text) =~ s/\Q$word\E/ZZ/g;
        my $result = compile_fixture($fx, $mutant);
        $word_rejects++ unless $result && ($result->{op} // '') eq $fx->{op};
    }
    is($word_rejects, $fx->{words}, "$label rejects the expected number of word-level near-misses");
}

# Explicit near-miss shapes that cannot be derived by deleting text from a fixture.
{
    my $pkg = 'Demo::Edge';
    my $full = "${pkg}::";
    # edge($name, $text)
    # Compiles one hand-written sub text as the named sub of the edge package.
    # Input: sub name and sub text. Output: compiled record or undef.
    sub edge {
        my ($name, $text) = @_;
        return PAX::CodeUnitCompiler::_compile_declared_sub_from_source_unprototyped("package $pkg;\n$text\n1;\n", $full . $name);
    }

    my $required_only = edge('new', <<'S');
sub new {
    my ($class, %args) = @_;
    my $files = $args{files} || die 'Missing file registry';
    return bless { 'files' }, $class;
}
S
    ok(!$required_only, 'required-argument constructor without slot pairs is not recognised');

    my $no_aliases = edge('helper_aliases', <<'S');
sub helper_aliases {
    return ( 'pjq', 'skill' );
}
S
    ok(!$no_aliases, 'helper alias recogniser rejects a body without alias pairs');

    my $transform = PAX::CodeUnitCompiler::_compile_simple_transform_sub_from_source("package $pkg;\nsub x { return 1; }\n", 'x', 'unqualified');
    ok(!defined $transform, 'simple transform recogniser needs a qualified sub name');

    my $missing_body = PAX::CodeUnitCompiler::_compile_simple_transform_sub_from_source("package $pkg;\n1;\n", 'absent', "${pkg}::absent");
    ok(!defined $missing_body, 'simple transform recogniser needs a sub body in the source');
}

done_testing();

__DATA__
#@@ Developer::Dashboard::ActionRunner new bless_required_args_hash 1,2,3,4,7 w9 p0
  sub new {
      my ( $class, %args ) = @_;
      my $files = $args{files} || die 'Missing file registry';
      my $paths = $args{paths} || die 'Missing path registry';
      return bless {
          files => $files,
          paths => $paths,
      }, $class;
  }
#@@ Developer::Dashboard::Auth new bless_required_args_hash 1,2,3,4,7 w9 p0
  sub new {
      my ( $class, %args ) = @_;
      my $paths = $args{paths} || die 'Missing path registry';
      my $files = $args{files} || die 'Missing file registry';
      return bless {
          paths => $paths,
          files => $files,
      }, $class;
  }
#@@ Developer::Dashboard::CLI::Complete complete app_complete 2,3,4,8,11,16,17,20,21,24,30,33,39,42,43,45,46,47,48,50,51 w27 p0
  sub complete {
      my (%args) = @_;
      my $words = $args{words} || die "Missing completion words\n";
      my $index = defined $args{index} ? $args{index} : die "Missing completion index\n";
      die "Completion words must be an array reference\n" if ref($words) ne 'ARRAY';
  
      my @words = @{$words};
      my $current = defined $words[$index] ? $words[$index] : '';
      my $suggest = Developer::Dashboard::CLI::Suggest->new();
  
      my @candidates;
      if ( $index <= 1 ) {
          my @path_aliases = $current =~ /\A(.+)\./
            ? _skill_path_alias_candidates($1)
            : ();
          @candidates = (
              $suggest->top_level_candidates,
              $suggest->skill_commands,
              @path_aliases,
          );
      }
      elsif ( ( $words[1] || '' ) eq 'workspace' && $index == 2 ) {
          my $provider = $args{ticket_sessions} || \&_ticket_sessions;
          @candidates = $provider->();
      }
      elsif (
          ( $words[1] || '' ) =~ /\A(?:restart|stop)\z/
          && ( $words[2] || '' ) eq 'collector'
          && $index == 3
        )
      {
          my $provider = $args{collector_names} || \&_collector_names;
          @candidates = $provider->();
      }
      elsif (
          ( $words[1] || '' ) =~ /\A(?:log|logs)\z/
          && ( $words[2] || '' ) eq 'collector'
          && $index == 3
        )
      {
          my $provider = $args{collector_names} || \&_collector_names;
          @candidates = $provider->();
      }
      elsif ( ( $words[1] || '' ) eq 'docker' && ( $words[2] || '' ) eq 'development' && $index == 3 ) {
          @candidates = qw(enable disable);
      }
      else {
          @candidates = _subcommand_candidates( $words[1] || '' );
      }
  
      my %seen;
      return grep { !$seen{$_}++ } grep { $current eq '' || index( $_, $current ) == 0 } @candidates;
  }
#@@ Developer::Dashboard::CLI::Paths _normalize_add_arguments paths_normalize_add_arguments 4,6,7,11 w12 p1
  sub _normalize_add_arguments {
      my (@argv) = @_;
      die "Usage: dashboard path add <name> <path>\n" if !@argv;
  
      if ( @argv == 1 && $argv[0] eq '.' ) {
          my $cwd = cwd();
          return ( basename($cwd), $cwd );
      }
  
      my $name = shift @argv || die "Usage: dashboard path add <name> <path>\n";
      my $path = shift @argv || die "Usage: dashboard path add <name> <path>\n";
      $path = cwd() if $path eq '.';
      return ( $name, $path );
  }
#@@ Developer::Dashboard::CLI::Paths _normalize_delete_argument paths_normalize_delete_argument 2,3,5,15,22 w12 p1
  sub _normalize_delete_argument {
      my (%args) = @_;
      my $paths  = $args{paths}  || die "Missing paths registry\n";
      my $config = $args{config} || die "Missing config\n";
      my $name   = $args{name};
      die "Usage: dashboard path del <name>\n" if !defined $name || $name eq '';
      return $name if $name ne '.';
  
      my $cwd = cwd();
      my %aliases = %{ $config->path_aliases || {} };
      my $preferred = basename($cwd);
      if ( exists $aliases{$preferred} ) {
          my $resolved = eval { $paths->_expand_home( $aliases{$preferred} ) };
          $resolved = $aliases{$preferred} if !defined $resolved || $resolved eq '';
          return $preferred if $resolved eq $cwd;
      }
      for my $candidate ( sort keys %aliases ) {
          my $target = $aliases{$candidate};
          next if !defined $target || $target eq '';
          my $resolved = eval { $paths->_expand_home($target) };
          $resolved = $target if !defined $resolved || $resolved eq '';
          return $candidate if $resolved eq $cwd;
      }
  
      return basename($cwd);
  }
#@@ Developer::Dashboard::CLI::Paths _cdr_payload cdr_payload 2,4,11,12,14,22,23,29 w17 p0
  sub _cdr_payload {
      my (%args) = @_;
      my $paths = $args{paths} || die "Missing paths registry\n";
      my $argv  = $args{args}  || [];
      die "cdr args must be an array reference\n" if ref($argv) ne 'ARRAY';
  
      my @terms = @{$argv};
      return { target => '', matches => [] } if !@terms;
  
      my $first = $terms[0];
      my $configured_aliases = $paths->named_paths || {};
      my $alias_target = eval { $paths->resolve_dir($first) };
      if ( !defined $alias_target && !exists $configured_aliases->{$first} && ref( $args{folder_alias_resolver} ) eq 'CODE' ) {
          $alias_target = $args{folder_alias_resolver}->($first);
      }
      if ( defined $alias_target && $alias_target ne '' ) {
          shift @terms;
          return { target => $alias_target, matches => [] } if !@terms;
          my @matches = $paths->locate_dirs_under( $alias_target, @terms );
          return {
              target  => @matches == 1 ? $matches[0] : $alias_target,
              matches => @matches == 1 ? [] : \@matches,
          };
      }
  
      my @matches = $paths->locate_dirs_under( $paths->current_working_directory, @terms );
      return {
          target  => @matches == 1 ? $matches[0] : '',
          matches => @matches == 1 ? [] : \@matches,
      };
  }
#@@ Developer::Dashboard::CLI::Paths _cdr_completion cdr_completion 2,3,4,5,14,15,20,28 w19 p0
  sub _cdr_completion {
      my (%args) = @_;
      my $paths = $args{paths} || die "Missing paths registry\n";
      my $words = $args{words} || die "Missing completion words\n";
      my $index = defined $args{index} ? $args{index} : die "Missing completion index\n";
      die "cdr completion words must be an array reference\n" if ref($words) ne 'ARRAY';
  
      my @words = @{$words};
      return () if !@words;
  
      my $current = defined $words[$index] ? $words[$index] : '';
      my @args = @words > 1 ? @words[ 1 .. $#words ] : ();
      my $arg_index = $index - 1;
  
      if ( $arg_index <= 0 ) {
          return _cdr_initial_candidates(
              paths   => $paths,
              prefix  => $current,
              include => [ $paths->current_working_directory ],
          );
      }
  
      my $first = $args[0] // '';
      my $alias_target = eval { $paths->resolve_dir($first) };
      my $base_root = defined $alias_target && $alias_target ne '' ? $alias_target : $paths->current_working_directory;
      my $filter_start = defined $alias_target && $alias_target ne '' ? 1 : 0;
      my @filters = @args >= $arg_index ? @args[ $filter_start .. ( $arg_index - 1 ) ] : ();
  
      return _cdr_directory_candidates(
          paths   => $paths,
          root    => $base_root,
          terms   => \@filters,
          prefix  => $current,
      );
  }
#@@ Developer::Dashboard::CLI::Paths _cdr_initial_candidates cdr_initial_candidates 2,5,7,8 w22 p0
  sub _cdr_initial_candidates {
      my (%args) = @_;
      my $paths  = $args{paths}   || die "Missing paths registry\n";
      my $prefix = defined $args{prefix} ? $args{prefix} : '';
      my $roots  = $args{include} || [];
      die "cdr completion include roots must be an array reference\n" if ref($roots) ne 'ARRAY';
  
      my @candidates = grep { index( $_, $prefix ) == 0 } keys %{ $paths->named_paths || {} };
      push @candidates, _cdr_directory_candidates(
          paths  => $paths,
          root   => $_,
          terms  => [],
          prefix => $prefix,
      ) for grep { defined && $_ ne '' && -d $_ } @{$roots};
  
      my %seen;
      return sort grep { $_ ne '' && !$seen{$_}++ } @candidates;
  }
#@@ Developer::Dashboard::CLI::Paths _cdr_directory_candidates cdr_directory_candidates 2,6,8,13,18 w21 p0
  sub _cdr_directory_candidates {
      my (%args) = @_;
      my $paths  = $args{paths} || die "Missing paths registry\n";
      my $root   = $args{root}  || return ();
      my $terms  = $args{terms} || [];
      my $prefix = defined $args{prefix} ? $args{prefix} : '';
      die "cdr completion terms must be an array reference\n" if ref($terms) ne 'ARRAY';
  
      my @matches = $paths->locate_dirs_under( $root, @{$terms} );
      my %seen;
      my @candidates;
      for my $path (@matches) {
          next if !defined $path || $path eq '' || $path eq $root;
          my $name = basename($path);
          next if $name eq '';
          next if $prefix ne '' && index( $name, $prefix ) != 0;
          next if $seen{$name}++;
          push @candidates, $name;
      }
  
      return sort @candidates;
  }
#@@ Developer::Dashboard::CLI::Query run_query_command query_run_command 4,7,13 w8 p1
  sub run_query_command {
      my (%args) = @_;
      my $command = $args{command} || die 'Missing command';
      my @argv    = @{ $args{args} || [] };
      my ( $path, $file ) = _split_query_args(@argv);
  
      my $raw = _read_query_input($file);
      my $data = _parse_query_input(
          command => $command,
          text    => $raw,
      );
      my $value = _select_query_value( $data, $path );
      _print_query_value($value);
      _command_exit(0);
  }
#@@ Developer::Dashboard::CLI::Query _split_query_args query_split_args 5,6,9,11,13 w7 p1
  sub _split_query_args {
      my (@argv) = @_;
      my $file = '';
      my @rest;
  
      for my $arg (@argv) {
          if ( !$file && -f $arg ) {
              $file = $arg;
              next;
          }
          push @rest, $arg;
      }
  
      my $path = @rest ? join( ' ', @rest ) : '';
      return ( $path, $file );
  }
#@@ Developer::Dashboard::CLI::Query _read_query_input query_read_input 2,3,6,9 w8 p1
  sub _read_query_input {
      my ($file) = @_;
      if ($file) {
          open my $fh, '<', $file or die "Unable to read $file: $!";
          local $/;
          return <$fh>;
      }
  
      local $/;
      return scalar <STDIN>;
  }
#@@ Developer::Dashboard::CLI::Query _extract_query_path query_extract_path 13,14,18,21,23,26,27,28 w16 p1
  sub _extract_query_path {
      my ( $data, $path ) = @_;
      return $data if !defined $path || $path eq '' || $path eq '$d' || $path eq '.';
      $path =~ s/^\$d\.?//;
  
      my @parts = grep { $_ ne '' } split /\./, $path;
      my $value = $data;
  
      while (@parts) {
          if ( ref($value) eq 'HASH' ) {
              my $remaining = join '.', @parts;
              if ( exists $value->{$remaining} ) {
                  return $value->{$remaining};
              }
          }
  
          my $part = shift @parts;
          if ( ref($value) eq 'HASH' ) {
              die "Missing path segment '$part'\n" if !exists $value->{$part};
              $value = $value->{$part};
              next;
          }
          if ( ref($value) eq 'ARRAY' ) {
              die "Array index '$part' is invalid\n" if $part !~ /^\d+$/ || $part > $#$value;
              $value = $value->[$part];
              next;
          }
          die "Path '$path' does not resolve through a nested structure\n";
      }
  
      return $value;
  }
#@@ Developer::Dashboard::CLI::Query _path_uses_perl_expression query_path_uses_expression 2,4 w9 p1
  sub _path_uses_perl_expression {
      my ($path) = @_;
      return 0 if !defined $path || $path eq '' || $path eq '$d' || $path eq '.';
      return 0 if $path =~ /^\$d(?:\.[A-Za-z0-9_]+)*\z/;
      return index( $path, '$d' ) >= 0 ? 1 : 0;
  }
#@@ Developer::Dashboard::CLI::Query _select_query_value query_select_value 3,4 w6 p1
  sub _select_query_value {
      my ( $data, $path ) = @_;
      return $data if !defined $path || $path eq '';
      return _evaluate_query_expression( $data, $path ) if _path_uses_perl_expression($path);
      return _extract_query_path( $data, $path );
  }
#@@ Developer::Dashboard::CLI::Query _evaluate_query_expression query_evaluate_expression 3,6,10,14,18 w11 p1
  sub _evaluate_query_expression {
      my ( $data, $expr ) = @_;
      my $code = eval <<"PERL_EVAL";
  sub {
      my (\$d) = \@_;
      return do { $expr };
  }
  PERL_EVAL
      die "Query expression '$expr' failed: $@" if $@;
  
      if ( $expr =~ /^\s*scalar\b/ ) {
          my $scalar = eval { scalar $code->($data) };
          die "Query expression '$expr' failed: $@" if $@;
          return $scalar;
      }
  
      my @list = eval { $code->($data) };
      die "Query expression '$expr' failed: $@" if $@;
      return \@list if _expression_prefers_list_output($expr);
      return \@list if @list > 1;
      return $list[0] if @list == 1;
      return [];
  }
#@@ Developer::Dashboard::CLI::Query _expression_prefers_list_output query_expression_prefers_list 4 w11 p1
  sub _expression_prefers_list_output {
      my ($expr) = @_;
      return 0 if !defined $expr || $expr =~ /^\s*scalar\b/;
      return 0 if $expr =~ /\bjoin\b/;
      return $expr =~ /\b(?:sort|map|grep|keys|values)\b/ ? 1 : 0;
  }
#@@ Developer::Dashboard::CLI::Query _print_query_value query_print_value 2,3,5,6 w8 p1
  sub _print_query_value {
      my ($value) = @_;
      if ( ref($value) ) {
          print json_encode($value), "\n";
          return 1;
      }
      print defined $value ? $value : '';
      print "\n";
      return 1;
  }
#@@ Developer::Dashboard::CLI::Query _parse_java_properties query_parse_java_properties 12,22,23 w10 p1
  sub _parse_java_properties {
      my ($text) = @_;
      my %props;
      my @lines = split /\n/, $text // '';
      my $pending = '';
  
      for my $line (@lines) {
          $line =~ s/\r$//;
          next if $line =~ /^\s*[#!]/;
          if ( $line =~ s/\\$// ) {
              $pending .= $line;
              next;
          }
          $line = $pending . $line;
          $pending = '';
          next if $line =~ /^\s*$/;
  
          my ( $key, $value ) = split /\s*[:=]\s*|\s+/, $line, 2;
          $key   = '' if !defined $key;    # uncoverable branch true
          $value = '' if !defined $value;
          $key   =~ s/^\s+|\s+$//g;
          $value =~ s/^\s+|\s+$//g;
          $props{$key} = _unescape_properties($value);
      }
  
      return \%props;
  }
#@@ Developer::Dashboard::CLI::Query _unescape_properties query_unescape_properties 2,6 w7 p1
  sub _unescape_properties {
      my ($text) = @_;
      $text =~ s/\\t/\t/g;
      $text =~ s/\\n/\n/g;
      $text =~ s/\\r/\r/g;
      $text =~ s/\\f/\f/g;
      $text =~ s/\\\\/\\/g;
      return $text;
  }
#@@ Developer::Dashboard::CLI::Query _parse_ini query_parse_ini 3,16,23,24 w10 p1
  sub _parse_ini {
      my ($text) = @_;
      my %ini;
      my $current_section = '_global';
      $ini{$current_section} = {};
      my @lines = split /\n/, $text // '';
  
      for my $line (@lines) {
          $line =~ s/[\r\n]+$//;
          $line =~ s/^\s+|\s+$//g;
          next if $line =~ /^[;#]/ || $line eq '';
          
          if ($line =~ /^\[(.+)\]$/) {
              $current_section = $1;
              $ini{$current_section} = {};
              next;
          }
          
          if ($line =~ /^([^=:]+)\s*[:=]\s*(.*)$/) {
              my ($key, $value) = ($1, $2);
              $key =~ s/^\s+|\s+$//g;
              $value =~ s/^\s+|\s+$//g;
              $ini{$current_section}{$key} = $value;
          }
      }
  
      return \%ini;
  }
#@@ Developer::Dashboard::CLI::Query _parse_csv query_parse_csv 8,10 w8 p1
  sub _parse_csv {
      my ($text) = @_;
      my @rows;
      my @lines = split /\n/, $text // '';
  
      for my $line (@lines) {
          $line =~ s/[\r\n]+$//;
          next if $line eq '';
          my @fields = split /,/, $line;
          push @rows, \@fields;
      }
  
      return \@rows;
  }
#@@ Developer::Dashboard::CLI::Query _parse_xml query_parse_xml 2,4 w9 p1
  sub _parse_xml {
      my ($text) = @_;
      my $parser = XML::Parser->new( Style => 'Tree' );
      my $tree = $parser->parse($text);
      return _xml_tree_to_data($tree);
  }
#@@ Developer::Dashboard::CLI::Query _xml_tree_to_data query_xml_tree_to_data 2,5,6 w12 p1
  sub _xml_tree_to_data {
      my ($tree) = @_;
      die 'XML tree must be an array reference' if ref($tree) ne 'ARRAY' || @{$tree} < 2;
      my ( $root_name, $root_children ) = @{$tree};
      return {
          $root_name => _xml_element_payload($root_children),
      };
  }
#@@ Developer::Dashboard::CLI::Query _xml_element_payload query_xml_element_payload 2,9,12,15,18,19,22,25,27,36,37 w16 p1
  sub _xml_element_payload {
      my ($children) = @_;
      die 'XML element payload must be an array reference' if ref($children) ne 'ARRAY';
      my $attrs = $children->[0];
      my @items = @{$children}[ 1 .. $#$children ];
      my @text;
      my %elements;
      my %repeated;
  
      while (@items) {
          my $name = shift @items;
          my $value = shift @items;
          if ( $name eq '0' ) {
              push @text, $value if $value !~ /^\s*$/;
              next;
          }
  
          my $decoded = _xml_element_payload($value);
          if ( exists $elements{$name} ) {
              if ( !$repeated{$name} ) {
                  $elements{$name} = [ $elements{$name} ];
                  $repeated{$name} = 1;
              }
              push @{ $elements{$name} }, $decoded;
              next;
          }
          $elements{$name} = $decoded;
      }
  
      my $text = join '', @text;
      my $has_attrs = ref($attrs) eq 'HASH' && keys %{$attrs};
      my $has_children = keys %elements ? 1 : 0;
  
      return $text if !$has_attrs && !$has_children;
  
      my %node = %elements;
      $node{_attributes} = $attrs if $has_attrs;
      $node{_text} = $text if $text ne '';
      return \%node;
  }
#@@ Developer::Dashboard::CLI::RuntimeControl _log_usage return_literal 1 w6 p0
  sub _log_usage {
      return "Usage: dashboard log[s] [web|collector [name]] [-n <lines>] [-f]\n";
  }
#@@ Developer::Dashboard::CLI::Skills _build_paths build_paths_registry 1,2 w15 p0
  sub _build_paths {
      my $home = $ENV{HOME} || '';
      return Developer::Dashboard::PathRegistry->new(
          home            => $home,
          workspace_roots => [ grep { defined && -d } map { "$home/$_" } qw(projects src work) ],    # uncoverable branch false the mapped candidate is an interpolated string and is never undef
          project_roots   => [ grep { defined && -d } map { "$home/$_" } qw(projects src work) ],    # uncoverable branch false the mapped candidate is an interpolated string and is never undef
      );
  }
#@@ Developer::Dashboard::CLI::Source _usage return_literal 1 w4 p0
  sub _usage {
      return "Usage: dashboard source --files\n";
  }
#@@ Developer::Dashboard::CLI::Ticket _tmux_status_interval_seconds return_literal 1 w3 p0
  sub _tmux_status_interval_seconds {
      return 15;
  }
#@@ Developer::Dashboard::CLI::Upgrade _usage return_literal 1 w4 p0
  sub _usage {
      return "Usage: dashboard upgrade [--dry-run]\n";
  }
#@@ Developer::Dashboard::DataHelper j call_named_with_first_arg 1 w4 p0
  sub j {
      return json_encode( $_[0] );
  }
#@@ Developer::Dashboard::DataHelper je call_named_with_first_arg_default 1 w4 p0
  sub je {
      return json_decode( $_[0] // '' );
  }
#@@ Developer::Dashboard::DockerCompose new bless_required_args_hash 1,2,3,4,7 w9 p0
  sub new {
      my ( $class, %args ) = @_;
      my $config = $args{config} || die 'Missing config';
      my $paths  = $args{paths}  || die 'Missing path registry';
      return bless {
          config => $config,
          paths  => $paths,
      }, $class;
  }
#@@ Developer::Dashboard::DockerCompose _expand_env_path docker_compose_expand_env_path 10,12 w13 p1
  sub _expand_env_path {
      my ( $self, $path ) = @_;
      return $path if !defined $path || $path eq '';
  
      # DD-887: a single combined pass over the ORIGINAL string, matching both
      # ${VAR} and bare $VAR forms in one alternation - never two sequential
      # passes, which would re-scan the first pass's OUTPUT as input to the
      # second, letting one env var's own value (if it happens to contain a
      # "$NAME"-shaped substring) get a second, unintended expansion using a
      # completely unrelated env var.
      $path =~ s/\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)/
          my $name = defined $1 ? $1 : $2;
          defined $ENV{$name} ? $ENV{$name} : '';
      /gex;
  
      return $path;
  }
#@@ Developer::Dashboard::DockerCompose _docker_config_root docker_compose_config_root 2 w5 p1
  sub _docker_config_root {
      my ($self) = @_;
      return File::Spec->catdir( $self->{paths}->config_root, 'docker' );
  }
  #-- 'docker'
#@@ Developer::Dashboard::DockerCompose _home_docker_config_root docker_compose_home_config_root 2 w6 p1
  sub _home_docker_config_root {
      my ($self) = @_;
      return File::Spec->catdir( $self->{paths}->home_runtime_root, 'config', 'docker' );
  }
  #-- 'docker'
  #-- 'config'
#@@ Developer::Dashboard::DockerCompose _discover_service_files docker_compose_discover_service_files 4,9,29,31 w16 p1
  sub _discover_service_files {
      my ( $self, %args ) = @_;
      my $service      = $args{service} || return;
      my $project_root = $args{project_root} || cwd();    # uncoverable condition false cwd never returns a false value
      return if $self->_service_folder_is_disabled(
          project_root => $project_root,
          service      => $service,
      );
  
      my @roots = $self->_service_lookup_roots(
          project_root => $project_root,
          service      => $service,
      );
  
      my @files;
      my %seen;
      my $development_enabled = $self->_service_folder_is_development(
          project_root => $project_root,
          service      => $service,
      );
      for my $root (@roots) {
          next if !defined $root;    # uncoverable branch true lookup roots are interpolated paths, never undef
          my $service_root = File::Spec->catdir( $root, $service );
          next if !-d $service_root;    # uncoverable branch true lookup roots already filtered to existing service folders
  
          my $compose = File::Spec->catfile( $service_root, 'compose.yml' );
          push @files, $compose if -f $compose && !$seen{$compose}++;
  
          next if !$development_enabled;
          my $development = File::Spec->catfile( $service_root, 'development.compose.yml' );
          push @files, $development if -f $development && !$seen{$development}++;
      }
  
      return @files;
  }
#@@ Developer::Dashboard::DockerCompose _discover_enabled_services docker_compose_discover_enabled_services 2,4,8 w7 p1
  sub _discover_enabled_services {
      my ( $self, %args ) = @_;
      my @services = $self->_discover_service_names(%args);
      return grep {
          !$self->_service_folder_is_disabled(
              project_root => $args{project_root},
              service      => $_,
          )
      } @services;
  }
#@@ Developer::Dashboard::DockerCompose _discover_service_names docker_compose_discover_service_names 6,9,13,15,17 w14 p1
  sub _discover_service_names {
      my ( $self, %args ) = @_;
      my $project_root = $args{project_root} || cwd();    # uncoverable condition false cwd never returns a false value
      my $service_map  = $args{service_map} || {};
      my %names = map { $_ => 1 } grep { $_ ne '' } keys %{$service_map};
  
      for my $root ( $self->_service_lookup_roots( project_root => $project_root, service => '__all__' ) ) {
          next if !-d $root;
          opendir my $dh, $root or next;
          while ( my $entry = readdir $dh ) {
              next if $entry eq '.' || $entry eq '..';
              next if !-d File::Spec->catdir( $root, $entry );
              $names{$entry} = 1;
          }
          closedir $dh;
      }
  
      return sort keys %names;
  }
#@@ Developer::Dashboard::DockerCompose _service_folder_is_disabled docker_compose_service_folder_is_disabled 4,12,14 w12 p1
  sub _service_folder_is_disabled {
      my ( $self, %args ) = @_;
      my $service      = $args{service} || return 0;
      my $project_root = $args{project_root} || cwd();    # uncoverable condition false cwd never returns a false value
      my @roots = $self->_service_lookup_roots(
          project_root => $project_root,
          service      => $service,
      );
      return 0 if !@roots;
      for my $root ( reverse @roots ) {
          my $service_root = File::Spec->catdir( $root, $service );
          next if !-d $service_root;
          return 1 if -f File::Spec->catfile( $service_root, 'disabled.yml' );
          return 0;
      }
  
      return 0;
  }
#@@ Developer::Dashboard::DockerCompose _service_lookup_roots docker_compose_service_lookup_roots 6,10,15,18,21,22 w15 p1
  sub _service_lookup_roots {
      my ( $self, %args ) = @_;
      my $service      = $args{service} || return;
      my $project_root = $args{project_root} || cwd();    # uncoverable condition false cwd never returns a false value
      my @roots;
      my %seen;
      for my $runtime_root ( $self->{paths}->runtime_layers ) {
          my @candidates = ();
          my $config_docker_root = File::Spec->catdir( $runtime_root, 'config', 'docker' );
          push @candidates, $config_docker_root;
          push @candidates, $self->_installed_skill_docker_roots_for_runtime($runtime_root);
  
          for my $root (@candidates) {
              next if !defined $root;    # uncoverable branch true candidate roots are interpolated paths, never undef
              next if $seen{$root}++;    # uncoverable branch true candidate roots across runtime layers are already distinct
              if ( $service eq '__all__' ) {
                  push @roots, $root;
                  next;
              }
              my $service_root = File::Spec->catdir( $root, $service );
              push @roots, $root if -d $service_root;
          }
      }
  
      return @roots;
  }
#@@ Developer::Dashboard::DockerCompose _infer_services_from_args docker_compose_infer_services_from_args 5,15,17,18 w12 p1
  sub _infer_services_from_args {
      my ( $self, %args ) = @_;
      my $argv         = $args{args} || [];
      my $project_root = $args{project_root} || cwd();    # uncoverable condition false cwd never returns a false value
      my $service_map  = $args{service_map} || {};
      my %known = map { $_ => 1 } $self->_discover_service_names(
          project_root => $project_root,
          service_map  => $service_map,
      );
  
      my @services;
      my %seen;
      for my $arg ( @{$argv} ) {
          next if !defined $arg || $arg eq '';
          next if $arg =~ /^-/;
          next if !$known{$arg};
          next if $seen{$arg}++;
          push @services, $arg;
      }
  
      return @services;
  }
#@@ Developer::Dashboard::DockerCompose disable_service docker_compose_disable_service 3,7,12,19 w15 p1
  sub disable_service {
      my ( $self, %args ) = @_;
      my $service = $args{service} || die "Usage: dashboard docker disable <service>\n";
      my $marker = $self->_service_disabled_marker_path(
          project_root => $args{project_root},
          service      => $service,
      );
      die "Refusing service name that escapes the docker config root: $service\n"
        if !defined $marker;
      my ( undef, $dir ) = File::Spec->splitpath($marker);
      make_path($dir) if !-d $dir;
      open my $fh, '>', $marker or die "Unable to write $marker: $!";
      print {$fh} "---\ndisabled: 1\n";
      close $fh or die "Unable to close $marker: $!";    # uncoverable branch true the deferred write failure surfaces only on close, unreproducible on the test host
      return {
          action   => 'disable',
          disabled => 1,
          marker   => $marker,
          service  => $service,
      };
  }
#@@ Developer::Dashboard::DockerCompose enable_service docker_compose_enable_service 3,7,9,15 w17 p1
  sub enable_service {
      my ( $self, %args ) = @_;
      my $service = $args{service} || die "Usage: dashboard docker enable <service>\n";
      my $marker = $self->_service_disabled_marker_path(
          project_root => $args{project_root},
          service      => $service,
      );
      die "Refusing service name that escapes the docker config root: $service\n"
        if !defined $marker;
      unlink $marker or die "Unable to remove $marker: $!" if -e $marker;
      return {
          action   => 'enable',
          disabled => 0,
          marker   => $marker,
          service  => $service,
      };
  }
#@@ Developer::Dashboard::DockerCompose list_services docker_compose_list_services 7,14,23,29,30 w13 p1
  sub list_services {
      my ( $self, %args ) = @_;
      my $project_root = $args{project_root} || cwd();    # uncoverable condition false cwd never returns a false value
      my $filter = defined $args{filter} && $args{filter} ne '' ? $args{filter} : 'all';
      die "Usage: dashboard docker list [--enabled|--disabled]\n"
        if $filter !~ /\A(?:all|enabled|disabled)\z/;
  
      my @services = $self->_discover_service_names(
          project_root => $project_root,
          service_map  => $self->{config}->docker_config->{services} || {},
      );
  
      my @listed;
      for my $service (@services) {
          my $disabled = $self->_service_folder_is_disabled(
              project_root => $project_root,
              service      => $service,
          ) ? 1 : 0;
          next if $filter eq 'enabled'  && $disabled;
          next if $filter eq 'disabled' && !$disabled;
          push @listed, {
              disabled => $disabled,
              enabled  => $disabled ? 0 : 1,
              marker   => $self->_service_disabled_marker_path(
                  project_root => $project_root,
                  service      => $service,
              ),
              service => $service,
              status  => $disabled ? 'disabled' : 'enabled',
          };
      }
  
      return \@listed;
  }
#@@ Developer::Dashboard::DockerCompose _discover_base_files docker_compose_discover_base_files 2 w8 p1
  sub _discover_base_files {
      my ( $self, $root ) = @_;
      my @candidates = qw(compose.yml compose.yaml docker-compose.yml docker-compose.yaml);
      return grep { -f $_ } map { File::Spec->catfile( $root, $_ ) } @candidates;
  }
#@@ Developer::Dashboard::DockerCompose _service_disabled_marker_path docker_compose_service_disabled_marker_path 3,6 w8 p1
  sub _service_disabled_marker_path {
      my ( $self, %args ) = @_;
      my $service = $args{service} || die 'Missing service';
      my $root = $self->_service_toggle_root(%args);
      my $dir = _contained_service_path( $root, $service );
      return if !defined $dir;
      return File::Spec->catfile( $dir, 'disabled.yml' );
  }
#@@ Developer::Dashboard::DockerCompose _service_toggle_root docker_compose_service_toggle_root 3,4 w11 p1
  sub _service_toggle_root {
      my ( $self, %args ) = @_;
      my @layers = $self->{paths}->runtime_layers;
      my $runtime_root = @layers ? $layers[-1] : $self->{paths}->home_runtime_root;    # uncoverable branch false runtime_layers always includes at least the home runtime root
      return File::Spec->catdir( $runtime_root, 'config', 'docker' );
  }
#@@ Developer::Dashboard::Doctor _audit_roots doctor_audit_roots 2,4,6,7 w12 p0
  sub _audit_roots {
      my ( $self, %args ) = @_;
      my %seen;
      my @reports;
      for my $root ( $self->_known_roots ) {
          next if !$root->{path} || $seen{ $root->{path} }++;
          push @reports, $self->_audit_root( %{$root}, fix => $args{fix} );
      }
      return @reports;
  }
#@@ Developer::Dashboard::Doctor _known_roots doctor_known_roots 4,5,7,8,9,11,12,13,14,17 w14 p0
  sub _known_roots {
      my ($self) = @_;
      my $home = $self->{paths}->home;
      return (
          {
              label => 'home_runtime',
              path  => $self->{paths}->home_runtime_path,
          },
          map {
              +{
                  label => $_->{label},
                  path  => File::Spec->catdir( $home, $_->{name} ),
              }
          } (
              { label => 'legacy_bookmarks', name => 'bookmarks' },
              { label => 'legacy_config',    name => 'config' },
              { label => 'legacy_cli',       name => 'cli' },
              { label => 'legacy_checkers',  name => 'checkers' },
          ),
      );
  }
#@@ Developer::Dashboard::Doctor _audit_root doctor_audit_root 2,3,6,12,15,16,18,22,24,27,29,30,38,40 w20 p0
  sub _audit_root {
      my ( $self, %args ) = @_;
      my $path = $args{path} || die 'Missing audit root path';
      my $label = $args{label} || die 'Missing audit root label';
      my $fix = $args{fix} ? 1 : 0;
  
      return {
          label       => $label,
          path        => $path,
          exists      => 0,
          issue_count => 0,
          issues      => [],
      } if !-e $path;
  
      my @issues;
      File::Find::find(
          {
              no_chdir => 1,
              wanted   => sub {
                  my $entry = $File::Find::name;
                  my $issue = $self->_permission_issue_for_path($entry);
                  return if !$issue;
                  if ($fix) {
                      chmod oct( $issue->{expected_mode} ), $entry
                        or die sprintf 'Unable to chmod %s to %s: %s', $entry, $issue->{expected_mode}, $!;    # uncoverable branch true
                      $issue->{fixed} = 1;
                      $issue->{current_mode} = $issue->{expected_mode};
                  }
                  push @issues, $issue;
              },
          },
          $path,
      );
  
      return {
          label       => $label,
          path        => $path,
          exists      => 1,
          issue_count => scalar @issues,
          issues      => \@issues,
      };
  }
#@@ Developer::Dashboard::Doctor _permission_issue_for_path doctor_permission_issue_for_path 3,6,12,13,15 w12 p0
  sub _permission_issue_for_path {
      my ( $self, $path ) = @_;
      return if !defined $path || $path eq '';
      my $mode = _mode_octal($path);
      return if !defined $mode;
  
      my $expected = -d $path ? '0700' : ( -x $path ? '0700' : '0600' );
      return if $mode eq $expected;
  
      return {
          path          => $path,
          kind          => -d $path ? 'directory' : 'file',
          current_mode  => $mode,
          expected_mode => $expected,
          fixed         => 0,
      };
  }
#@@ Developer::Dashboard::Doctor _doctor_hook_results doctor_hook_results 2,3,4 w19 p0
  sub _doctor_hook_results {
      my ($self) = @_;
      return {} if !defined $ENV{RESULT} || $ENV{RESULT} eq '';
      my $results = json_decode( $ENV{RESULT} );
      die 'Doctor hook RESULT must decode to a hash'
        if ref($results) ne 'HASH';
      return $results;
  }
#@@ Developer::Dashboard::Doctor _mode_octal mode_octal_stat 2,3,4 w11 p0
  sub _mode_octal {
      my ($path) = @_;
      my @stat = stat($path);
      return undef if !@stat;
      return sprintf '%04o', $stat[2] & 07777;
  }
#@@ Developer::Dashboard::EnvAudit clear clear_package_hash_and_env 1,2,3 w5 p0
  sub clear {
      %AUDIT = ();
      delete $ENV{DEVELOPER_DASHBOARD_ENV_AUDIT};
      return 1;
  }
#@@ Developer::Dashboard::EnvAudit record record_package_hash_entry_and_sync 1,2,3,4,5,6,7,8,9,10 w18 p0
  sub record {
      my ( $class, $key, $value, $envfile ) = @_;
      die "Missing env audit key\n" if !defined $key || $key eq '';
      die "Missing env audit source file\n" if !defined $envfile || $envfile eq '';
      $class->_load_from_env();
      $AUDIT{$key} = {
          value   => $value,
          envfile => $envfile,
      };
      $class->_sync_to_env();
      return 1;
  }
#@@ Developer::Dashboard::EnvAudit key hash_lookup_via_method_copy 1,2,3,4,5 w13 p0
  sub key {
      my ( $class, $key ) = @_;
      return undef if !defined $key || $key eq '';
      my $audit = $class->_audit_copy();
      return undef if !exists $audit->{$key};
      return $audit->{$key};
  }
#@@ Developer::Dashboard::EnvAudit keys return_method_call 1,2 w7 p0
  sub keys {
      my ($class) = @_;
      return $class->_audit_copy();
  }
#@@ Developer::Dashboard::EnvAudit _audit_copy copy_package_hash_entries 1,2,3,4,5,6,7,8,9 w13 p0
  sub _audit_copy {
      my ($class) = @_;
      $class->_load_from_env();
      my %copy = map {
          $_ => {
              value   => $AUDIT{$_}{value},
              envfile => $AUDIT{$_}{envfile},
          }
      } CORE::keys %AUDIT;
      return \%copy;
  }
#@@ Developer::Dashboard::File configure app_file_configure 1,3,4,5,6,9 w17 p0
  sub configure {
      my ( $class, %args ) = @_;
      $FILES = $args{files} if $args{files};
      if ( !$FILES && $args{paths} ) {
          $FILES = Developer::Dashboard::FileRegistry->new( paths => $args{paths} );
      }
      %ALIASES = %{ $args{aliases} || {} };
      %CONFIG_ALIASES = ();
      $CONFIG_ALIASES_KEY = '';
      return 1;
  }
#@@ Developer::Dashboard::File all app_file_all 1,2 w6 p0
  sub all {
      my $files = _files_obj();
      _load_configured_aliases();
      return {} if !$files || !$files->can('all_files');
      return $files->all_files;
  }
#@@ Developer::Dashboard::File exists app_file_exists 2,3 w7 p0
  sub exists {
      my ( $class, $file ) = @_;
      my $path = $class->_resolve_file($file);
      return $path && -f $path ? 1 : 0;
  }
#@@ Developer::Dashboard::File cat return_method_call 2 w6 p0
  sub cat {
      my ( $class, $file ) = @_;
      return $class->read($file);
  }
#@@ Developer::Dashboard::File resolve return_method_call 2 w7 p0
  sub resolve {
      my ( $class, $file ) = @_;
      return $class->_resolve_file($file);
  }
#@@ Developer::Dashboard::File write app_file_write 1,2,3,4,5,6,7,8,9,10 w25 p0
  sub write {
      my ( $class, $file, $content, $append ) = @_;
      my $path = $class->_resolve_file($file);
      die 'Missing file path' if !defined $path || $path eq '';
      my $mode = $append ? '>>' : '>';
      open my $fh, $mode, $path or die "Unable to write $path: $!";
      print {$fh} defined $content ? $content : '';
      close $fh or die "Unable to close $path: $!";
      my $files = _files_obj();
      $files->paths->secure_file_permissions($path) if $files && $files->can('paths');
      return $path;
  }
#@@ Developer::Dashboard::File rm app_file_rm 2,3 w10 p0
  sub rm {
      my ( $class, $file ) = @_;
      my $path = $class->_resolve_file($file);
      unlink $path if defined $path && -e $path;
      return $path;
  }
#@@ Developer::Dashboard::File _files_obj app_file_files_obj 1,4,9,10 w10 p0
  sub _files_obj {
      return $FILES if blessed($FILES);
      my $home = $ENV{HOME} || '';
      return if $home eq '';
      my $paths = Developer::Dashboard::PathRegistry->new(
          home            => $home,
          workspace_roots => [ grep { -d } map { "$home/$_" } qw(projects src work) ],
          project_roots   => [ grep { -d } map { "$home/$_" } qw(projects src work) ],
      );
      $FILES = Developer::Dashboard::FileRegistry->new( paths => $paths );
      _load_configured_aliases();
      return $FILES;
  }
#@@ Developer::Dashboard::File _load_configured_aliases app_file_load_configured_aliases 5,7 w10 p0
  sub _load_configured_aliases {
      my $files = blessed($FILES) ? $FILES : return 1;
      my $key = _configured_alias_cache_key($files);
      return 1 if $key ne '' && $CONFIG_ALIASES_KEY eq $key;
  
      my $config = Developer::Dashboard::Config->new( files => $files, paths => $files->paths );
      %CONFIG_ALIASES = %{ $config->file_aliases || {} };
      $files->register_named_files( \%CONFIG_ALIASES );
      $CONFIG_ALIASES_KEY = $key;
      return 1;
  }
#@@ Developer::Dashboard::File _resolve_file app_file_resolve_file 4,5,10,11 w9 p0
  sub _resolve_file {
      my ( $class, $where ) = @_;
      return if !defined $where || $where eq '';
      return $where if File::Spec->file_name_is_absolute($where) || $where =~ m{/};
      _files_obj();
      _load_configured_aliases();
      my $files = blessed($FILES) ? $FILES : undef;
      return $files->$where() if $files && $RESOLVABLE_ACCESSOR{$where};
      return $ALIASES{$where} if defined $ALIASES{$where};
      return $CONFIG_ALIASES{$where} if defined $CONFIG_ALIASES{$where};
      my $env = 'DEVELOPER_DASHBOARD_FILE_' . uc($where);
      return $ENV{$env} if defined $ENV{$env} && $ENV{$env} ne '';
      return;
  }
#@@ Developer::Dashboard::File AUTOLOAD app_file_autoload 2,4,5 w6 p0
  sub AUTOLOAD {
      my ($class) = @_;
      my ($name) = $AUTOLOAD =~ /::([^:]+)$/;
      return if $name eq 'DESTROY';
      my $path = $class->_resolve_file($name);
      die "Unknown file '$name'" if !defined $path;
      return $path;
  }
#@@ Developer::Dashboard::FileRegistry paths return_self_slot  w3 p1
  sub paths { $_[0]->{paths} }
#@@ Developer::Dashboard::Folder configure folder_configure 2,3,5 w10 p1
  sub configure {
      my ( $class, %args ) = @_;
      $PATHS = $args{paths} if $args{paths};
      %ALIASES = %{ $args{aliases} || {} };
      %CONFIG_ALIASES = ();
      $CONFIG_ALIASES_KEY = '';
      return 1;
  }
#@@ Developer::Dashboard::Folder home folder_home 1 w5 p1
  sub home {
      return $ENV{HOME} || '';
  }
#@@ Developer::Dashboard::Folder tmp folder_tmp 1 w5 p1
  sub tmp {
      return File::Spec->tmpdir;
  }
#@@ Developer::Dashboard::Folder dd folder_runtime_root 1,2 w5 p1
  sub dd {
      my $paths = _paths_obj();
      return $paths && $paths->can('runtime_root') ? $paths->runtime_root : '';
  }
#@@ Developer::Dashboard::Folder bookmarks folder_dashboards_root 1,2 w5 p1
  sub bookmarks {
      my $paths = _paths_obj();
      return $paths && $paths->can('dashboards_root') ? $paths->dashboards_root : '';
  }
#@@ Developer::Dashboard::Folder configs folder_config_root 1,2 w5 p1
  sub configs {
      my $paths = _paths_obj();
      return $paths && $paths->can('config_root') ? $paths->config_root : '';
  }
#@@ Developer::Dashboard::Folder all folder_all_paths 2 w5 p1
  sub all {
      my $paths = _paths_obj();
      _load_configured_aliases();
      return {} if !$paths || !$paths->can('all_paths');
      return $paths->all_paths;
  }
#@@ Developer::Dashboard::Folder postman folder_postman 1,2 w9 p1
  sub postman {
      my $dir = File::Spec->catdir( configs(), 'postman' );
      make_path($dir) if $dir ne '' && !-d $dir;    # uncoverable condition left
      return $dir;
  }
#@@ Developer::Dashboard::Folder _paths_obj folder_paths_obj 4,6,9 w9 p1
  sub _paths_obj {
      return $PATHS if blessed($PATHS);
      my $home = $ENV{HOME} || '';
      return if $home eq '';
      $PATHS = Developer::Dashboard::PathRegistry->new(
          home            => $home,
          workspace_roots => [ grep { defined && -d } map { "$home/$_" } qw(projects src work) ],    # uncoverable branch false
          project_roots   => [ grep { defined && -d } map { "$home/$_" } qw(projects src work) ],    # uncoverable branch false
      );
      _load_configured_aliases();
      return $PATHS;
  }
#@@ Developer::Dashboard::Housekeeper _temp_file_kind housekeeper_temp_file_kind 3 w7 p1
  sub _temp_file_kind {
      my ( $self, $entry ) = @_;
      return ( 'ajax-temp-file', 'ajax_temp_files' ) if $entry =~ /\Adeveloper-dashboard-ajax-/;
      return ( 'result-temp-file', 'result_temp_files' ) if $entry =~ /\Adashboard-result-/;
      return;
  }
#@@ Developer::Dashboard::Housekeeper _collector_rotation housekeeper_collector_rotation 3,5,6,8,9 w10 p1
  sub _collector_rotation {
      my ( $self, $job ) = @_;
      my %rotation;
      if ( ref( $job->{rotation} ) eq 'HASH' ) {
          %rotation = ( %rotation, %{ $job->{rotation} } );
      }
      if ( ref( $job->{rotations} ) eq 'HASH' ) {
          %rotation = ( %rotation, %{ $job->{rotations} } );
      }
      return \%rotation;
  }
#@@ Developer::Dashboard::Housekeeper _read_state_metadata housekeeper_read_state_metadata 2,8,9 w12 p1
  sub _read_state_metadata {
      my ( $self, $dir ) = @_;
      my $file = File::Spec->catfile( $dir, 'runtime.json' );
      return if !-f $file;
      open my $fh, '<', $file or die "Unable to read $file: $!";
      local $/;
      my $raw = <$fh>;
      close $fh or die "Unable to close $file: $!";    # uncoverable branch true
      my $data = eval { json_decode($raw) };
      return if !$data || ref($data) ne 'HASH';
      return $data;
  }
#@@ Developer::Dashboard::Housekeeper _path_is_old_enough housekeeper_path_old_enough 2,4 w7 p1
  sub _path_is_old_enough {
      my ( $self, $path, $min_age_seconds ) = @_;
      my @stat = stat($path);
      return 0 if !@stat;
      return ( time - $stat[9] ) >= $min_age_seconds ? 1 : 0;
  }
#@@ Developer::Dashboard::Housekeeper _remove_tree housekeeper_remove_tree 4,5,6,7,8,12 w14 p1
  sub _remove_tree {
      my ( $self, $path, $kind, %args ) = @_;
      if ( !$args{dry_run} ) {
          my $errors = [];
          remove_tree( $path, { error => \$errors } );
          if ( @{$errors} && !$self->_only_missing_tree_errors($errors) ) {
              die "Unable to remove stale $kind $path\n";
          }
      }
      return {
          kind => $kind,
          path => $path,
      };
  }
#@@ Developer::Dashboard::Housekeeper _only_missing_tree_errors housekeeper_only_missing_tree_errors 4,5,6 w11 p1
  sub _only_missing_tree_errors {
      my ( $self, $errors ) = @_;
      return 1 if ref($errors) ne 'ARRAY' || !@{$errors};
      for my $entry ( @{$errors} ) {
          my ($message) = values %{ $entry || {} };
          return 0 if !defined $message || $message !~ /No such file or directory/;
      }
      return 1;
  }
#@@ Developer::Dashboard::Housekeeper _collector_store housekeeper_collector_store 2 w6 p1
  sub _collector_store {
      my ($self) = @_;
      return $self->{collector_store} ||= Developer::Dashboard::Collector->new( paths => $self->{paths} );    # uncoverable condition false
  }
#@@ Developer::Dashboard::InternalCLI helper_names internal_cli_helper_names 1,2,5,6 w12 p1
  sub helper_names {
      return qw(
        jq yq tomq propq iniq csvq xmlq
        of open-file workspace file files path paths ps1
        encode decode indicator collector config auth api ask init cpan page action docker serve stop restart log shell doctor housekeeper skills which upgrade
        complete
      );
  }
#@@ Developer::Dashboard::InternalCLI helper_aliases internal_cli_helper_aliases 2,6,8 w5 p1
  sub helper_aliases {
      return {
          pjq   => 'jq',
          pyq   => 'yq',
          ptomq => 'tomq',
          pjp   => 'propq',
          skill => 'skills',
          logs  => 'log',
      };
  }
#@@ Developer::Dashboard::InternalCLI canonical_helper_name internal_cli_canonical_helper_name 2,3,5 w11 p1
  sub canonical_helper_name {
      my ($name) = @_;
      return '' if !defined $name || $name eq '';
      my %allowed = map { $_ => 1 } helper_names();
      return $name if $allowed{$name};
      my $aliases = helper_aliases();
      return $aliases->{$name} || '';
  }
#@@ Developer::Dashboard::InternalCLI helper_path internal_cli_helper_path 3,4,5 w9 p1
  sub helper_path {
      my (%args) = @_;
      my $paths = $args{paths} || die 'Missing paths registry';
      my $name  = canonical_helper_name( $args{name} );
      die "Unsupported helper command '$args{name}'" if $name eq '';
      return File::Spec->catfile( _helper_install_root($paths), $name );
  }
#@@ Developer::Dashboard::InternalCLI helper_content internal_cli_helper_content 2,4 w12 p1
  sub helper_content {
      my ($name) = @_;
      $name = $name eq '_dashboard-core' ? $name : canonical_helper_name($name);
      die "Unsupported helper command '$name'" if !defined $name || $name eq '';    # uncoverable condition left
      my $path = _helper_asset_path($name);
      open my $fh, '<:raw', $path or die "Unable to read $path: $!";    # uncoverable branch true
      my $content = do { local $/; <$fh> };
      close $fh or die "Unable to close $path: $!";    # uncoverable branch true
      return $content;
  }
#@@ Developer::Dashboard::InternalCLI ensure_helpers internal_cli_ensure_helpers 9,11,13,19,21 w6 p1
  sub ensure_helpers {
      my (%args) = @_;
      my $paths = $args{paths} || die 'Missing paths registry';
      my %skip = map { $_ => 1 } grep { defined $_ && $_ ne '' } @{ $args{skip_names} || [] };
  
      my @written;
      $paths->ensure_dir( _helper_parent_root($paths) );
      $paths->ensure_dir( _helper_install_root($paths) );
      my $core_target = File::Spec->catfile( _helper_install_root($paths), '_dashboard-core' );
      if ( _stage_managed_helper( paths => $paths, name => '_dashboard-core', target => $core_target ) ) {
          $paths->secure_file_permissions( $core_target, executable => 1 );
      }
  
      for my $name ( helper_names() ) {
          next if $skip{$name};
          my $target = helper_path( paths => $paths, name => $name );
          next if !_stage_managed_helper( paths => $paths, name => $name, target => $target );
          $paths->secure_file_permissions( $target, executable => 1 );
          push @written, $target;
      }
  
      _remove_retired_managed_helper(
          paths => $paths,
          name  => 'skill',
      );
      _remove_legacy_managed_flat_helpers( paths => $paths );
  
      return \@written;
  }
#@@ Developer::Dashboard::InternalCLI _stage_managed_helper internal_cli_stage_managed_helper 4,11,15,17,19 w10 p1
  sub _stage_managed_helper {
      my (%args) = @_;
      my $target = $args{target} || die 'Missing helper target';
      my $name   = $args{name}   || die 'Missing helper name';
      my $content = _managed_helper_content($name);
  
      if ( -e $target ) {
          return 0 if !-f $target;
          if ( ( -s $target ) == 0 && _is_managed_helper_target( $args{paths}, $target ) ) {
              _write_helper_atomically( $target, $content );
              return 1;
          }
          open my $existing_fh, '<:raw', $target or die "Unable to read $target: $!";    # uncoverable branch true
          my $existing = do { local $/; <$existing_fh> };
          close $existing_fh or die "Unable to close $target: $!";    # uncoverable branch true
          return 0 if !_is_dashboard_managed_helper( $existing, $name );
          require Developer::Dashboard::SeedSync;
          return 0 if Developer::Dashboard::SeedSync::same_content_md5( $existing, $content );
          return 0 if _should_defer_windows_helper_refresh( $name, $target );
      }
  
      _write_helper_atomically( $target, $content );
      return 1;
  }
#@@ Developer::Dashboard::InternalCLI _remove_retired_managed_helper internal_cli_remove_retired_managed_helper 4,10,11 w11 p1
  sub _remove_retired_managed_helper {
      my (%args) = @_;
      my $paths = $args{paths} || die 'Missing paths registry';
      my $name  = $args{name}  || die 'Missing retired helper name';
      my $target = File::Spec->catfile( _helper_install_root($paths), $name );
      return 0 if !-e $target;
      return 0 if !-f $target;
      open my $fh, '<:raw', $target or die "Unable to read $target: $!";    # uncoverable branch true
      my $content = do { local $/; <$fh> };
      close $fh or die "Unable to close $target: $!";    # uncoverable branch true
      return 0 if !_is_dashboard_managed_helper( $content, $name );
      unlink $target or die "Unable to remove retired helper $target: $!";    # uncoverable branch true
      return 1;
  }
#@@ Developer::Dashboard::InternalCLI _managed_helper_content internal_cli_managed_helper_content 2,3,15,16,23,24,25,26,29,32,33,34,36,41,50,51,57,61 w11 p1
  sub _managed_helper_content {
      my ($name) = @_;
      my $content = helper_content($name);
      if ( _helper_uses_dashboard_core($name) ) {
          my $legacy_block = <<'BLOCK';
  my $command = basename($0);
  my $core = File::Spec->catfile( $Bin, '_dashboard-core' );
  exec { $^X } $^X, $core, $command, @ARGV;
  die "Unable to exec $core for $command: $!";
  BLOCK
          my $managed_block = <<"BLOCK";
  my \$command = '$name';
  my \$core = File::Spec->catfile( \$Bin, '_dashboard-core' );
  my \$running_helper = eval { require Cwd; Cwd::abs_path(\$0) } || \$0;
  \$ENV{DEVELOPER_DASHBOARD_RUNNING_HELPER} ||= \$running_helper;
  if (is_windows()) {
      eval {
          require Developer::Dashboard::InternalCLI;
          my \$shipped_core = Developer::Dashboard::InternalCLI::_helper_asset_path('_dashboard-core');
          \$core = \$shipped_core if defined \$shipped_core && \$shipped_core ne q{} && -f \$shipped_core;
          1;
      } or do {
          # Keep the staged sibling core path when the shipped helper asset is unavailable.
      };
  }
  if ( !defined \$ENV{DEVELOPER_DASHBOARD_REPO_LIB} || \$ENV{DEVELOPER_DASHBOARD_REPO_LIB} eq q{} ) {
      for my \$inc (\@INC) {
          next if !defined \$inc || \$inc eq q{};
          my \$candidate = File::Spec->catfile( \$inc, 'Developer', 'Dashboard.pm' );
          if ( -f \$candidate ) {
              \$ENV{DEVELOPER_DASHBOARD_REPO_LIB} = \$inc;
              last;
          }
      }
  }
  my \@command = ( \$^X, \$core, \$command, \@ARGV );
  if (is_windows()) {
      system \@command;
      my \$status = \$?;
      my \$exit_code = \$status > 255 ? \$status >> 8 : \$status;
      exit \$exit_code;
  }
  exec { \$^X } \@command;
  die "Unable to exec \$core for \$command: \$!";
  BLOCK
          $content =~ s/use File::Basename qw\(basename\);\n//;
          $content =~ s/use Developer::Dashboard::Platform qw\(is_windows\);\n//g;
          $content =~ s/use File::Spec;\nuse FindBin qw\(\$Bin\);\n/use File::Spec;\nuse FindBin qw(\$Bin);\nuse Developer::Dashboard::Platform qw(is_windows);\n/;
          $content =~ s/\Q$legacy_block\E/$managed_block/;
          $content =~ s/my \$command = '[^']+';\nmy \$core = File::Spec->catfile\( \$Bin, '_dashboard-core' \);\nmy \@command = \( \$\^X, \$core, \$command, \@ARGV \);\nif \(is_windows\(\)\) \{\n    system \@command;\n    my \$status = \$\?;\n    my \$exit_code = \$status > 255 \? \$status >> 8 : \$status;\n    exit \$exit_code;\n\}\nexec \{ \$\^X \} \@command;\ndie "Unable to exec \$core for \$command: \$!";/$managed_block/s;
      }
      my $marker  = _managed_helper_marker($name) . "\n";
      my $version_marker = _managed_helper_version_marker() . "\n";
      if ( $content =~ /\Q$marker\E/ ) {
          return $content if $content =~ /\Q$version_marker\E/;
          $content =~ s/\Q$marker\E/$marker$version_marker/;
          return $content;
      }
      if ( $content =~ /\A(#![^\n]*\n)/ ) {
          substr( $content, length($1), 0, $marker . $version_marker );
          return $content;
      }
      return $marker . $version_marker . $content;
  }
#@@ Developer::Dashboard::InternalCLI _managed_helper_marker internal_cli_managed_helper_marker 2 w5 p1
  sub _managed_helper_marker {
      my ($name) = @_;
      return "# developer-dashboard-managed-helper: $name";
  }
#@@ Developer::Dashboard::InternalCLI _managed_helper_version_marker return_literal 1 w6 p0
  sub _managed_helper_version_marker {
      return "# developer-dashboard-managed-helper-version: $VERSION";
  }
#@@ Developer::Dashboard::InternalCLI _is_dashboard_managed_helper internal_cli_is_dashboard_managed_helper 3,4,6,8,10 w14 p1
  sub _is_dashboard_managed_helper {
      my ( $content, $name ) = @_;
      return 0 if !defined $content;
      return 1 if $content =~ /^\Q@{[ _managed_helper_marker($name) ]}\E$/m;
      if ( $name eq '_dashboard-core' ) {
          return 1
            if $content =~ /Missing built-in dashboard command/
            && $content =~ /Developer::Dashboard::CLI::SeededPages/;
      }
      return 1
        if $content =~ /LAZY-THIN-CMD/
        && $content =~ /Developer Dashboard/;
      return 0;
  }
#@@ Developer::Dashboard::InternalCLI _helper_parent_root internal_cli_helper_parent_root 2 w5 p1
  sub _helper_parent_root {
      my ($paths) = @_;
      return File::Spec->catdir( $paths->home_runtime_root, 'cli' );
  }
#@@ Developer::Dashboard::InternalCLI _helper_install_root internal_cli_helper_install_root 2 w4 p1
  sub _helper_install_root {
      my ($paths) = @_;
      return File::Spec->catdir( _helper_parent_root($paths), 'dd' );
  }
#@@ Developer::Dashboard::InternalCLI _helper_asset_path internal_cli_helper_asset_path 4,8,10,14,15,21 w6 p1
  sub _helper_asset_path {
      my ($name) = @_;
      my $repo_path = File::Spec->catfile( _repo_private_cli_root(), $name );
      return $repo_path if -f $repo_path;
      for my $root ( _repo_private_cli_root_candidates() ) {
          next if !defined $root || $root eq '';
          my $candidate = File::Spec->catfile( $root, $name );
          return $candidate if -f $candidate;
      }
      if ( _module_source_looks_like_blib_build() ) {
          for my $root ( _shared_private_cli_root_candidates() ) {
              next if !defined $root || $root eq '';
              my $candidate = File::Spec->catfile( $root, $name );
              return $candidate if -f $candidate;
          }
      }
      my @roots = _shared_private_cli_root_candidates();
      for my $root (@roots) {
          next if !defined $root || $root eq '';
          my $candidate = File::Spec->catfile( $root, $name );
          return $candidate if -f $candidate;
      }
      return File::Spec->catfile( _shared_private_cli_root(), $name );
  }
#@@ Developer::Dashboard::JSON json_encode json_xs_encode_pretty 1 w11 p0
  sub json_encode {
      return JSON::XS->new->utf8->canonical->pretty->encode( $_[0] );
  }
#@@ Developer::Dashboard::JSON json_decode json_xs_decode 1 w9 p0
  sub json_decode {
      return JSON::XS->new->utf8->decode( $_[0] );
  }
#@@ Developer::Dashboard::PageResolver new bless_required_args_hash 1,2,3,4,5,6,11 w9 p0
  sub new {
      my ( $class, %args ) = @_;
      my $config  = $args{config}  || die 'Missing config';
      my $pages   = $args{pages}   || die 'Missing page store';
      my $paths   = $args{paths}   || die 'Missing path registry';
      my $actions = $args{actions} || die 'Missing action runner';
      return bless {
          actions => $actions,
          config  => $config,
          pages   => $pages,
          paths   => $paths,
      }, $class;
  }
#@@ Developer::Dashboard::PageResolver list_pages page_resolver_list_pages 2,3,5,6,7 w17 p0
  sub list_pages {
      my ($self) = @_;
      my %ids = map { $_ => 1 } $self->{pages}->list_saved_pages;
      for my $provider ( @{ $self->providers } ) {
          next if ref($provider) ne 'HASH';
          $ids{ $provider->{id} } = 1 if $provider->{id};
      }
      return sort keys %ids;
  }
#@@ Developer::Dashboard::PageResolver load_named_page page_resolver_load_named_page 2,4,5,8,19,22,24 w14 p0
  sub load_named_page {
      my ( $self, $id, $report ) = @_;
      die 'Missing page id' if !defined $id || $id eq '';
      my $saved = eval { $self->{pages}->load_saved_page($id) };
      if ($saved) {
          $saved->{meta}{source_kind} = 'saved';
          _note( $report, 'saved', 'matched' );
          return $saved;
      }
      # DD-603: load_saved_page dies for three distinct reasons - genuine
      # "not found", a file-read failure, or a parse/validation failure - and
      # only the first one means "fall through to provider lookup". Collapsing
      # all three into a silent fallthrough turns a real read/parse error into
      # a misleading generic "not found" once provider lookup also fails to
      # match. Only the exact not-found die falls through; anything else is
      # the real diagnostic and must surface as-is. $@ is always a truthy,
      # eval-set error string here: this line is reached only when $saved is
      # falsy, and load_saved_page's own contract is to always either die or
      # return a truthy page hashref, never return falsy without dying.
      if ( $@ !~ /\APage '\Q$id\E' not found/ ) {
          _note( $report, 'saved', 'error', $@ );
          die $@;
      }
      _note( $report, 'saved', 'not-found' );
      return $self->load_provider_page( $id, $report );
  }
#@@ Developer::Dashboard::PageResolver providers page_resolver_providers 3,4,8,9,10,14,17 w10 p0
  sub providers {
      my ($self) = @_;
      my @providers = (
          {
              id          => 'system-status',
              kind        => 'builtin',
              title       => 'System Status',
              description => 'Generated page describing the local runtime.',
          },
          {
              id          => 'project-context',
              kind        => 'builtin',
              title       => 'Project Context',
              description => 'Generated page describing the active project.',
          },
      );
  
      push @providers, @{ $self->{config}->providers };
      return \@providers;
  }
#@@ Developer::Dashboard::PageResolver load_provider_page page_resolver_load_provider_page 4,9,10,14,19,29,34,35,47,48,49,50,51,60,62 w23 p0
  sub load_provider_page {
      my ( $self, $id, $report ) = @_;
      my @providers = @{ $self->providers };
      my ($provider) = grep { ref($_) eq 'HASH' && $_->{id} && $_->{id} eq $id } @providers;
      if ( !$provider ) {
          # Report the CANDIDATES, not just the verdict. The ids that DO exist are
          # what a reader needs in order to act on a mistyped or renamed page id.
          _note( $report, 'providers', 'no-match',
              join ', ', sort grep { defined && length } map { ref($_) eq 'HASH' ? $_->{id} : () } @providers );
          die "Page '$id' not found";
      }
      _note( $report, 'providers', 'matched' );
  
      my $page;
      if ( ( $provider->{kind} || '' ) eq 'builtin' && $id eq 'system-status' ) {
          $page = Developer::Dashboard::PageDocument->new(
              id          => $id,
              title       => 'System Status',
              description => 'Generated overview of runtime paths and roots.',
              layout      => {
                  body => join(
                      "\n",
                      'Developer Dashboard runtime paths:',
                      'home: ' . $self->{paths}->home,
                      'runtime: ' . $self->{paths}->runtime_root,
                      'dashboards: ' . $self->{paths}->dashboards_root,
                      'config: ' . $self->{paths}->config_root,
                      'cli: ' . $self->{paths}->cli_root,
                  ),
              },
              actions => [
                  { id => 'paths', label => 'Show paths', kind => 'builtin', builtin => 'paths.list', safe => 1 },
              ],
          );
      }
      elsif ( ( $provider->{kind} || '' ) eq 'builtin' && $id eq 'project-context' ) {
          my $root = $self->{paths}->current_project_root || '(none)';
          $page = Developer::Dashboard::PageDocument->new(
              id          => $id,
              title       => 'Project Context',
              description => 'Generated page describing the current project root.',
              layout      => { body => "Current project root:\n$root" },
              state       => { current_project_root => $root },
              actions     => [
                  { id => 'state', label => 'Show state', kind => 'builtin', builtin => 'page.state', safe => 1 },
              ],
          );
      }
      elsif ( ref( $provider->{page} ) eq 'HASH' ) {
          $page = Developer::Dashboard::PageDocument->from_hash( $provider->{page} );
      }
      else {
          $page = Developer::Dashboard::PageDocument->new(
              id          => $provider->{id},
              title       => $provider->{title} || $provider->{id},
              description => $provider->{description} || 'Generated provider page.',
              layout      => { body => $provider->{body} || '' },
              actions     => $provider->{actions} || [],
              state       => $provider->{state} || {},
          );    # uncoverable condition false count:1
      }
  
      $page->{meta}{source_kind} = 'provider';
      return $page;
  }
#@@ Developer::Dashboard::PageRuntime new bless_args_hash 1,2,6 w8 p0
  sub new {
      my ( $class, %args ) = @_;
      return bless {
          files   => $args{files},
          paths   => $args{paths},
          aliases => $args{aliases} || {},
      }, $class;
  }
#@@ Developer::Dashboard::PageRuntime::StreamHandle PRINT stream_writer_print 1,2,3 w11 p0
  sub PRINT {
      my ( $self, @parts ) = @_;
      $self->{writer}->( join '', map { defined $_ ? $_ : '' } @parts );
      return 1;
  }
#@@ Developer::Dashboard::PageRuntime::StreamHandle PRINTF stream_writer_printf 1,2,3 w11 p0
  sub PRINTF {
      my ( $self, $format, @parts ) = @_;
      $self->{writer}->( sprintf( defined $format ? $format : '', @parts ) );
      return 1;
  }
#@@ Developer::Dashboard::Platform is_windows global_eq_literal_bool 1 w6 p0
  sub is_windows {
      return $OS_NAME eq 'MSWin32' ? 1 : 0;
  }
#@@ Developer::Dashboard::Platform native_shell_name native_shell_name 4,5,6,8,12 w13 p0
  sub native_shell_name {
      my ($requested) = @_;
      return normalize_shell_name($requested) if defined $requested && $requested ne '';
  
      if (is_windows()) {
          return command_in_path('pwsh') ? 'pwsh' : 'powershell';
      }
  
      my $shell = $ENV{SHELL} || '';
      $shell =~ s{.*[\\/]}{} if $shell ne '';
      return normalize_shell_name($shell) if $shell ne '';
  
      return 'bash' if command_in_path('bash');
      return 'zsh'  if command_in_path('zsh');
      return 'sh';
  }
#@@ Developer::Dashboard::Platform normalize_shell_name normalize_shell_name 6,7,9 w11 p0
  sub normalize_shell_name {
      my ($shell) = @_;
      $shell = native_shell_name() if !defined $shell || $shell eq '';
      $shell =~ s{.*[\\/]}{} if defined $shell;    # uncoverable branch false
      $shell = lc( $shell || '' );
  
      return 'powershell' if $shell eq 'ps' || $shell eq 'powershell.exe';
      return 'pwsh'       if $shell eq 'pwsh.exe';
      return $shell if $shell eq 'bash' || $shell eq 'zsh' || $shell eq 'sh' || $shell eq 'powershell' || $shell eq 'pwsh';
      die "Unsupported shell '$shell'\n";
  }
#@@ Developer::Dashboard::Platform shell_command_argv shell_command_argv 2,7 w11 p0
  sub shell_command_argv {
      my ( $command, %args ) = @_;
      die "Missing shell command\n" if !defined $command;
  
      my $shell = normalize_shell_name( $args{shell} || native_shell_name() );    # uncoverable condition false
      my $login = $args{login} ? 1 : 0;
      return ( $shell, $login ? '-lc' : '-c', $command ) if $shell eq 'bash' || $shell eq 'zsh' || $shell eq 'sh';
      return ( $shell, '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $command )
        if $shell eq 'powershell' || $shell eq 'pwsh';
      die "Unsupported shell '$shell'\n";
  }
#@@ Developer::Dashboard::Platform command_in_path command_in_path 15,16,18,19,21,25,26 w15 p0
  sub command_in_path {
      my ($name) = @_;
      return if !defined $name || $name eq '';
  
      # DD-765: a BARE name (no directory separator) is a request to search
      # PATH - the caller's cwd is not on PATH, and never was. Testing the
      # bare name as a relative filesystem path here resolved it against the
      # process's cwd, so a same-named file sitting in whatever directory
      # dashboard happened to be run from was preferred over the real PATH
      # executable and returned as a RELATIVE string - a dot-in-PATH hazard
      # reached without dot ever being on PATH, and unconditionally wrong the
      # moment any caller's cwd changes between the check and the use. Every
      # current caller passes a bare name, so this loop never had a legitimate
      # reason to exist; a caller with an actual path does not need this
      # resolver at all.
      if ( $name =~ m{[\\/]} ) {
          for my $candidate ( _path_candidates($name) ) {
              return $candidate if -f $candidate;
          }
      }
  
      for my $dir ( File::Spec->path ) {
          next if !defined $dir || $dir eq '';
          for my $candidate ( _path_candidates( File::Spec->catfile( $dir, $name ) ) ) {
              return $candidate if -f $candidate;
          }
      }
  
      return;
  }
#@@ Developer::Dashboard::Platform is_runnable_file is_runnable_file 2,3 w6 p0
  sub is_runnable_file {
      my ($path) = @_;
      my $resolved = resolve_runnable_file($path);
      return $resolved ? 1 : 0;
  }
#@@ Developer::Dashboard::Platform resolve_runnable_file resolve_runnable_file 4,7,8 w9 p0
  sub resolve_runnable_file {
      my ($path) = @_;
      return if !defined $path || $path eq '';
  
      for my $candidate ( _runnable_path_candidates($path) ) {
          next if !-f $candidate;
          return $candidate if !is_windows() && -x $candidate;
          return $candidate if is_windows() && _is_windows_runnable_candidate($candidate);
      }
  
      return;
  }
#@@ Developer::Dashboard::Platform command_argv_for_path command_argv_for_path 2,11,14,17,21,23,25 w23 p0
  sub command_argv_for_path {
      my ($path) = @_;
      my $resolved = ( -f $path ? $path : resolve_runnable_file($path) ) || die "Unable to find runnable file for $path";
      my $lower = lc $resolved;
  
      # DD-856: an actual shebang line, when present, names the interpreter the
      # file's author intended - it must be honoured BEFORE any extension-based
      # guess. Without this check first, a shell script saved with a .pl suffix
      # (or any other mismatched extension) was silently force-run through the
      # wrong interpreter by extension alone, producing undefined behaviour
      # instead of running the script or reporting a clear error.
      if ( !is_windows() && _has_shebang($resolved) ) {
          return ( $^X, '-I', _module_lib_root(), $resolved ) if _shebang_uses_perl($resolved);
          return ($resolved);
      }
  
      return ( $^X, '-I', _module_lib_root(), $resolved ) if $lower =~ /\.pl\z/;
      if ( $lower =~ /\.py\z/ ) {
          my $venv_python = _find_layer_venv_python($resolved);
          return ( $venv_python, $resolved ) if defined $venv_python;
          return ( _python_binary(), $resolved );
      }
      return ( _node_binary(), $resolved ) if $lower =~ /\.js\z/;
      return ( $^X, '-I', _module_lib_root(), '-MDeveloper::Dashboard::Platform', '-e', 'Developer::Dashboard::Platform::_exec_go_source(@ARGV)', $resolved )
        if $lower =~ /\.go\z/;
      return ( $^X, '-I', _module_lib_root(), '-MDeveloper::Dashboard::Platform', '-e', 'Developer::Dashboard::Platform::_exec_java_source(@ARGV)', $resolved )
        if $lower =~ /\.java\z/;
      return ( _powershell_binary(), '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $resolved )
        if $lower =~ /\.ps1\z/;
      return ( _cmd_binary(), '/d', '/c', $resolved ) if $lower =~ /\.(?:cmd|bat)\z/;
      return ( _posix_shell_binary('bash'), $resolved ) if $lower =~ /\.bash\z/;
      return ( _posix_shell_binary('sh'),   $resolved ) if $lower =~ /\.sh\z/;
      return ($resolved) if !is_windows();
      return ($^X, $resolved);
  }
#@@ Developer::Dashboard::Platform _shebang_uses_perl shebang_uses_perl 2,6 w11 p0
  sub _shebang_uses_perl {
      my ($path) = @_;
      open my $fh, '<', $path or die "Unable to read $path: $!";
      my $first = <$fh>;
      close $fh;
      return 0 if !defined $first;
      return $first =~ /^#!.*\bperl(?:\s|\z)/ ? 1 : 0;
  }
#@@ Developer::Dashboard::Platform shell_quote_for shell_quote_for 5,6,8,10 w7 p0
  sub shell_quote_for {
      my ( $shell, $value ) = @_;
      $shell = normalize_shell_name($shell);
      $value = '' if !defined $value;
  
      if ( $shell eq 'powershell' || $shell eq 'pwsh' ) {
          $value =~ s/'/''/g;
          return "'$value'";
      }
  
      $value =~ s/'/'\\''/g;
      return "'$value'";
  }
#@@ Developer::Dashboard::Platform _path_candidates path_candidates 6,9,11 w9 p0
  sub _path_candidates {
      my ($path) = @_;
      my @candidates = ($path);
      return @candidates if !is_windows();
      return @candidates if $path =~ /\.[^\\\/.]+\z/;
  
      my @extensions = split /;/, ( $ENV{PATHEXT} || '.COM;.EXE;.BAT;.CMD;.PS1' );
      for my $ext (@extensions) {
          next if $ext eq '';
          push @candidates, $path . lc($ext);
          push @candidates, $path . uc($ext);
      }
      return @candidates;
  }
#@@ Developer::Dashboard::Platform _is_windows_runnable_candidate is_windows_runnable_candidate 6,7 w10 p0
  sub _is_windows_runnable_candidate {
      my ($path) = @_;
      return 1 if $path =~ /\.(?:pl|ps1)\z/i;
      return 1 if $path =~ /\.py\z/i && ( command_in_path('python') || command_in_path('python3') );
      return 1 if $path =~ /\.js\z/i && command_in_path('node');
      return 1 if $path =~ /\.(?:com|exe|bat|cmd)\z/i;
      return 1 if $path =~ /\.(?:sh|bash)\z/i && ( command_in_path('bash') || command_in_path('sh') );
      return 1 if _has_shebang($path);
      return 0;
  }
#@@ Developer::Dashboard::Platform _has_shebang has_shebang 2,5 w10 p0
  sub _has_shebang {
      my ($path) = @_;
      open my $fh, '<', $path or die "Unable to read $path: $!";
      my $first = <$fh>;
      close $fh;
      return defined $first && $first =~ /^#!/ ? 1 : 0;
  }
#@@ Developer::Dashboard::Platform _powershell_binary command_chain_or_literal 1 w6 p0
  sub _powershell_binary {
      return command_in_path('pwsh') || command_in_path('powershell') || 'powershell';
  }
#@@ Developer::Dashboard::Platform _module_lib_root module_lib_root 1,2 w8 p0
  sub _module_lib_root {
      my $path = $INC{'Developer/Dashboard/Platform.pm'} || __FILE__;
      return dirname( dirname( dirname($path) ) );
  }
#@@ Developer::Dashboard::Platform _exec_go_source exec_go_source 2,6,10,13 w11 p0
  sub _exec_go_source {
      my ( $path, @args ) = @_;
      die "Missing Go source path\n" if !defined $path || $path eq '';
      my $dir = dirname($path);
      my $go_mod = _find_layer_go_mod($dir);
      my ( $mod_cache, $build_cache );
      if ( defined $go_mod ) {
          my $cache_root = File::Spec->catdir( dirname($go_mod), 'local', 'go-cache' );
          $mod_cache   = File::Spec->catdir( $cache_root, 'mod' );
          $build_cache = File::Spec->catdir( $cache_root, 'build' );
      }
      local $ENV{GOMODCACHE} = $mod_cache   if defined $mod_cache;
      local $ENV{GOCACHE}    = $build_cache if defined $build_cache;
      $EXEC_LAUNCHER->( 'go', 'run', '-C', $dir, $path, @args ) or die "Unable to exec go run for $path: $!";
  }
#@@ Developer::Dashboard::Platform _exec_java_source exec_java_source 8,26 w16 p0
  sub _exec_java_source {
      my ( $path, @args ) = @_;
  
      # DD-597: the javac/mvn launches below mutate the caller's global $? as a
      # side effect; without this guard that stays set in the caller's process
      # after this sub returns (the die path only - a successful exec below
      # replaces the process image and never returns).
      local $?;
      die "Missing Java source path\n" if !defined $path || $path eq '';
  
      my $class = _java_main_class($path);
      my ($simple_class) = $class =~ /([^\.]+)\z/;
      die "Unable to resolve Java main class for $path\n" if !defined $simple_class;
  
      my $pom = _find_layer_pom($path);
      return _exec_java_source_via_mvn( $pom, $class, @args ) if defined $pom;
  
      my $build_root = tempdir( CLEANUP => 1 );
      my $source_root = tempdir( CLEANUP => 1 );
      my $staged_source = File::Spec->catfile( $source_root, $simple_class . '.java' );
      copy( $path, $staged_source ) or die "Unable to stage Java source $path as $staged_source: $!";    # uncoverable branch true
  
      $SYSTEM_LAUNCHER->( 'javac', '-d', $build_root, $staged_source );
      my $exit_code = $? >> 8;
      die "javac failed for $path with exit code $exit_code\n" if $exit_code != 0;
  
      $EXEC_LAUNCHER->( 'java', '-cp', $build_root, $class, @args ) or die "Unable to exec java for $path: $!";
  }
#@@ Developer::Dashboard::Platform _java_main_class java_main_class 8,11,12,15,16,22 w18 p0
  sub _java_main_class {
      my ($path) = @_;
      die "Missing Java source path\n" if !defined $path || $path eq '';
  
      open my $fh, '<', $path or die "Unable to read $path: $!";
      my $package = '';
      my $class = '';
      while ( my $line = <$fh> ) {
          if ( $line =~ /^\s*package\s+([A-Za-z_][A-Za-z0-9_\.]*)\s*;/ ) {
              $package = $1;
              next;
          }
          if ( $line =~ /^\s*(?:public\s+)?(?:final\s+|abstract\s+)?(?:class|interface|enum|record)\s+([A-Za-z_][A-Za-z0-9_]*)\b/ ) {
              $class = $1;
              last;
          }
      }
      close $fh;
  
      if ( $class eq '' ) {
          $class = basename($path);
          $class =~ s/\.java\z//i;
      }
  
      return $package eq '' ? $class : $package . '.' . $class;
  }
#@@ Developer::Dashboard::Prompt render prompt_render 3,4,17,29,33,34 w18 p0
  sub render {
      my ( $self, %args ) = @_;
  
      my $jobs = defined $args{jobs} ? $args{jobs} : 0;
      my $cwd  = $args{cwd} || cwd();    # uncoverable condition false
      my $mode = $args{mode} || 'compact';
      my $color = exists $args{color} ? $args{color} : 0;
      my $max_age = defined $args{max_age} ? $args{max_age} : 300;
      my $no_indicators = $args{no_indicators} ? 1 : 0;
      $no_indicators = 1 if !$no_indicators && $self->_tmux_status_active;
      my $project = $self->{paths}->project_root_for($cwd);
      my $home = $self->{paths}->home;
      $cwd =~ s/^\Q$home\E/~/;
      $cwd = "Home: $home" if $cwd eq '~';
  
      my @indicator_parts = $no_indicators
        ? ()
        : $self->_indicator_parts(
            color   => $color,
            max_age => $max_age,
            mode    => $mode,
        );
  
      my $ticket = defined $ENV{WORKSPACE_REF} && $ENV{WORKSPACE_REF} ne ''
        ? $ENV{WORKSPACE_REF}
        : ( defined $ENV{TICKET_REF} ? $ENV{TICKET_REF} : '' );
      my @info_parts = @indicator_parts;
      push @info_parts, "🎫:$ticket" if $ticket ne '';
      my $info = @info_parts ? join( ' ', @info_parts ) : '';
      my $branch = $self->_git_branch($project);
      my $jobs_suffix = $jobs ? " ($jobs jobs)" : '';
      my $branch_suffix = $branch ? " 🌿$branch" : '';
  
      return sprintf "(%s)%s [%s]%s%s\n> ",
        $self->_timestamp,
        ( $info ne '' ? " $info" : '' ),
        $cwd,
        $jobs_suffix,
        $branch_suffix;
  }
#@@ Developer::Dashboard::Prompt _timestamp strftime_now 1 w10 p0
  sub _timestamp {
      return strftime( '%Y-%m-%d %H:%M:%S', localtime );
  }
#@@ Developer::Dashboard::Prompt _indicator_parts prompt_indicator_parts 7,9,12,20,21,22 w18 p0
  sub _indicator_parts {
      my ( $self, %args ) = @_;
      my $mode = $args{mode} || 'compact';
      my $color = exists $args{color} ? $args{color} : 0;
      my $max_age = defined $args{max_age} ? $args{max_age} : 300;
  
      my @indicator_parts;
      for my $indicator ( $self->{indicators}->list_indicators ) {
          next if exists $indicator->{prompt_visible} && !$indicator->{prompt_visible};
          my $status_icon = $self->{indicators}->prompt_status_icon($indicator);
          my $icon = defined $indicator->{icon} ? $indicator->{icon} : '';
          my $label = defined $indicator->{label} ? $indicator->{label} : $indicator->{name};
          my $stale = $self->{indicators}->is_stale( $indicator, max_age => $max_age ) ? 1 : 0;
          my $part = $mode eq 'extended'
            ? join( '', grep { defined && $_ ne '' } $status_icon, $icon, $label )
            : join( '', grep { defined && $_ ne '' } $status_icon, ( $icon || substr( $label, 0, 1 ) ) );    # uncoverable branch false
          if ($color) {
              my $status = $indicator->{status} || '';
              my $ansi = $stale ? "\e[33m" : $status =~ /^(ok|clean)$/ ? "\e[32m" : $status =~ /^(missing|error|dirty|down)$/ ? "\e[31m" : "\e[36m";
              $part = $ansi . $part . "\e[0m";
          }
          push @indicator_parts, $part;
      }
  
      return @indicator_parts;
  }
#@@ Developer::Dashboard::RuntimeManager _state_settle_polls return_literal 1 w3 p0
  sub _state_settle_polls {
      return 10;
  }
#@@ Developer::Dashboard::SeedSync content_md5 content_md5 1,2,3 w10 p0
  sub content_md5 {
      my ($content) = @_;
      $content = '' if !defined $content;
      return md5_hex( _content_bytes($content) );
  }
#@@ Developer::Dashboard::SeedSync same_content_md5 same_content_md5 1,2 w7 p0
  sub same_content_md5 {
      my ( $left, $right ) = @_;
      return content_md5($left) eq content_md5($right);
  }
#@@ Developer::Dashboard::SeedSync _content_bytes utf8_content_bytes 1,2,3 w10 p0
  sub _content_bytes {
      my ($content) = @_;
      return encode_utf8($content) if utf8::is_utf8($content);
      return $content;
  }
#@@ Developer::Dashboard::SessionStore new bless_required_args_hash 1,2,3 w9 p0
  sub new {
      my ( $class, %args ) = @_;
      my $paths = $args{paths} || die 'Missing path registry';
      return bless { paths => $paths }, $class;
  }
#@@ Developer::Dashboard::UpdateManager new bless_required_args_hash 1,2,3,4,5,7,12 w9 p0
  sub new {
      my ( $class, %args ) = @_;
      my $config = $args{config} || die 'Missing config';
      my $files  = $args{files}  || die 'Missing file registry';
      my $paths  = $args{paths}  || die 'Missing path registry';
      my $runner = $args{runner} || die 'Missing collector runner';
  
      return bless {
          config => $config,
          files  => $files,
          paths  => $paths,
          runner => $runner,
      }, $class;
  }
#@@ Developer::Dashboard::UpdateManager updates_dir cwd_catdir_literal 2 w8 p0
  sub updates_dir {
      my ($self) = @_;
      return File::Spec->catdir( cwd(), 'updates' );
  }
#@@ Developer::Dashboard::UpdateManager run update_manager_run 14,15,17,18,24,32,35,41,45,46,49 w36 p0
  sub run {
      my ($self) = @_;
  
      # DD-597: system() below mutates the caller's global $? as a side
      # effect; without this guard that stays set in the caller's process
      # after this sub returns, regardless of the exit code already captured
      # per-file in this sub's own results.
      local $?;
  
      my @results;
      my $dir = $self->updates_dir;
  
      return \@results if !-d $dir;
  
      my @running = $self->_running_collectors;
      $self->_stop_collectors(@running);
  
      opendir my $dh, $dir or die "Unable to open updates directory $dir: $!";
      for my $file ( sort readdir $dh ) {
          next if $file eq '.' || $file eq '..';
          next if !-f File::Spec->catfile( $dir, $file );
  
          my $path = File::Spec->catfile( $dir, $file );
          next if !$self->_is_supported_update_script($path);
          my @cmd = command_argv_for_path($path);
  
          print "-" x 40, "\n";
          print ">> Run Update: $file...\n";
          print "-" x 40, "\n";
          print ">> @cmd\n";
          print "-" x 40, "\n";
  
          my ( $stdout, $stderr, $exit_code ) = capture {
              system @cmd;
              return $? >> 8;
          };
          my $output = $stdout . $stderr;
  
          print $output if defined $output && $output ne ''; # uncoverable condition left
          print "\n>> Finished.\n\n";
  
          push @results, {
              file      => $file,
              exit_code => $exit_code,
              output    => $output,
          };
      }
      closedir $dh;
  
      $self->_restart_collectors(@running);
  
      return \@results;
  }
#@@ Developer::Dashboard::UpdateManager _is_supported_update_script supported_update_script 2,3,4,5 w17 p0
  sub _is_supported_update_script {
      my ( $self, $path ) = @_;
      return 0 if !defined $path || $path eq '';
      return 1 if $path =~ /\.pl\z/i;
      return 1 if $path =~ /\.(?:sh|bash|ps1|cmd|bat)\z/i;
      return is_runnable_file($path) ? 1 : 0;
  }
#@@ Developer::Dashboard::UpdateManager _running_collectors runner_loop_names 2 w9 p0
  sub _running_collectors {
      my ($self) = @_;
      return map { $_->{name} } $self->{runner}->running_loops;
  }
#@@ Developer::Dashboard::UpdateManager _stop_collectors stop_named_loops 2,3,4 w11 p0
  sub _stop_collectors {
      my ( $self, @names ) = @_;
      for my $name (@names) {
          eval { $self->{runner}->stop_loop($name) };
      }
  }
#@@ Developer::Dashboard::UpdateManager _restart_collectors restart_wanted_collectors 4,5,10,11 w17 p0
  sub _restart_collectors {
      my ( $self, @names ) = @_;
      return if !@names;
  
      my %wanted = map { $_ => 1 } @names;
      my @jobs = @{ $self->{config}->collectors };
  
      for my $job (@jobs) {
          next if ref($job) ne 'HASH';
          next if !$wanted{ $job->{name} };
          eval { $self->{runner}->start_loop($job) };
      }
  }
#@@ Developer::Dashboard::Web::DancerApp build_psgi_app dancerapp_build_psgi_app 2,4,7,9 w11 p1
  sub build_psgi_app {
      my ( $class, %args ) = @_;
      my $app = $args{app} || die 'Missing backend web app';
      my $default_headers = $args{default_headers} || {};
      $BACKEND_APP = {
          app             => $app,
          default_headers => { %{$default_headers} },
      };
      _load_skill_dashboard_modules( $args{paths} );
      return __PACKAGE__->to_app;
  }
#@@ Developer::Dashboard::Web::Server::Daemon new bless_args_hash 1,2,7 w8 p0
  sub new {
      my ( $class, %args ) = @_;
      return bless {
          host          => $args{host},
          port          => $args{port},
          internal_host => $args{internal_host},
          internal_port => $args{internal_port},
      }, $class;
  }
#@@ Developer::Dashboard::Web::Server::Daemon sockhost return_self_slot 1 w5 p0
  sub sockhost {
      return $_[0]{host};
  }
#@@ Developer::Dashboard::Web::Server::Daemon sockport return_self_slot 1 w5 p0
  sub sockport {
      return $_[0]{port};
  }
#@@ Developer::Dashboard::Web::Server::Daemon internal_sockhost return_self_slot 1 w4 p0
  sub internal_sockhost {
      return $_[0]{internal_host};
  }
#@@ Developer::Dashboard::Web::Server::Daemon internal_sockport return_self_slot 1 w4 p0
  sub internal_sockport {
      return $_[0]{internal_port};
  }
#@@ Demo::Text reverse_words split_reverse_join 1,2,3 w9 p0
  sub reverse_words {
      my ($value) = @_;
      my @parts = split /\s+/, ($value // '');
      return join ' ', reverse @parts;
  }
#@@ Demo::Audit _load_from_env load_package_hash_from_env_json 1,2,3,4,5,6,7,8,9,10,11,12,13 w22 p0
  sub _load_from_env {
      my ($class) = @_;
      return 1 if %AUDIT;
      my $raw = $ENV{AUDIT_JSON} || '';
      return 1 if $raw eq '';
      my $decoded = json_decode($raw);
      die "Invalid audit payload\n" if ref($decoded) ne 'HASH';
      %AUDIT = map {
          $_ => {
              value => $decoded->{$_}{value},
              envfile => $decoded->{$_}{envfile},
          }
      } CORE::keys %{$decoded};
      return 1;
  }
#@@ Demo::Audit _sync_to_env sync_env_json_from_method 1,2,3 w9 p0
  sub _sync_to_env {
      my ($class) = @_;
      $ENV{AUDIT_JSON} = json_encode( $class->_audit_copy );
      return 1;
  }
#@@ Demo::Content file_matches file_matches_content_md5 1,2,3,4,5,6 w18 p0
  sub file_matches {
      my ($path, $content) = @_;
      return 0 if !defined $path || $path eq '' || !-f $path;
      open my $fh, '<:raw', $path or die "Unable to read $path: $!";
      my $existing = do { local $/; <$fh> };
      close $fh or die "Unable to close $path: $!";
      return same_content_md5($existing, $content);
  }
#@@ Demo::Files read app_file_read 1,2,3,4,5,6 w16 p0
  sub read {
      my ($class, $file) = @_;
      my $path = $class->_resolve_file($file);
      return if !defined $path || !-f $path;
      open my $fh, '<', $path or die "Unable to read $path: $!";
      local $/;
      return <$fh>;
  }
#@@ Demo::Shell _posix_shell posix_shell_binary 1,2 w8 p0
  sub _posix_shell {
      my ($preferred) = @_;
      return command_in_path($preferred) || command_in_path('sh') || $preferred;
  }
#@@ Demo::Shell _cmd_binary cmd_binary 1,2,3 w14 p0
  sub _cmd_binary {
      my $candidate = $ENV{ComSpec} || command_in_path('cmd') || 'cmd.exe';
      return 'cmd.exe' if lc( basename($candidate) ) eq 'cmd.exe';
      return $candidate;
  }
#@@ Demo::Shell _runnable_path_candidates runnable_path_candidates 2,3 w16 p0
  sub _runnable_path_candidates {
      my ($path) = @_;
      my %seen;
      my @candidates = grep { !$seen{$_}++ } map { $path . $_ } qw(.pl .go .java .ps1 .cmd .bat .sh .bash);
      return @candidates;
  }
#@@ Demo::Root _module_lib_root module_lib_root 1,2 w8 p0
  sub _module_lib_root {
      my $path = $INC{"Demo/Root.pm"} || __FILE__;
      return dirname( dirname( dirname($path) ) );
  }
#@@ Demo::Root _bare_lib_root module_lib_root 1,2 w8 p0
  sub _bare_lib_root {
      my $path = $INC{Demo/Root.pm} || __FILE__;
      return dirname( dirname( dirname($path) ) );
  }
#@@ Demo::Web build_app build_pax_web_psgi_app 1,2,3,4 w13 p0
  sub build_app {
      my $tt = Template->new( INCLUDE_PATH => 'views' );
      get '/' => sub { my $out; $tt->process( 'index.tt', {}, \$out ); return $out };
      get '/healthz' => sub { return 'ok' };
      return dancer_app->to_app;
  }
#@@ Demo::Handle new tiehandle_constructor 1,2 w9 p0
  sub new {
      my ($class, %args) = @_;
      return bless { writer => $args{writer} || sub { } }, $class;
  }
#@@ Demo::Complete _subcommand_candidates app_subcommand_candidates 1,2,3,4,5,6,7,8,9,10,11,12,13 w21 p0
  sub _subcommand_candidates {
      my ($command) = @_;
      return qw(list install) if $command eq 'skills' || $command eq 'skill';
      return qw(up down) if $command eq 'docker';
      return qw(resolve locate) if $command eq 'path';
      return qw(set get) if $command eq 'indicator';
      return qw(run job) if $command eq 'collector';
      return qw(sync) if $command eq 'config';
      return qw(login) if $command eq 'auth';
      return qw(new) if $command eq 'page';
      return qw(run) if $command eq 'action';
      return qw(start stop) if $command eq 'serve';
      return qw(ps1 bash) if $command eq 'shell';
      return ();
  }
#@@ Demo::Paths run_paths_command run_paths_command 2,3,4,5,6,7,8 w33 p0
  sub run_paths_command {
      my (%args) = @_;
      my $command = $args{command} // die "Missing command name\n";
      my $argv = $args{args} // die "Missing command arguments\n";
      die "Command arguments must be an array reference\n" if ref($argv) ne 'ARRAY';
      my $paths = _build_paths();
      my $files = Demo::FileRegistry->new( paths => $paths );
      my $config = Demo::Config->new( files => $files, paths => $paths );
      die "Usage: dashboard path <resolve|locate|cdr|complete-cdr|add|del|rm|project-root|list> ...\n";
  }
#@@ Demo::Files run_files_command run_files_command 2,3,4,5,6,7,8 w29 p0
  sub run_files_command {
      my (%args) = @_;
      my $command = $args{command} // die "Missing command name\n";
      my $argv = $args{args} // die "Missing command arguments\n";
      die "Command arguments must be an array reference\n" if ref($argv) ne 'ARRAY';
      my $paths = _build_paths();
      my $files = Demo::FileRegistry->new( paths => $paths );
      my $config = Demo::Config->new( files => $files, paths => $paths );
      die "Usage: dashboard file <resolve|locate|add|del|list> ...\n";
  }
#@@ Demo::Doctor run doctor_run 2,3,4,6 w14 p0
  sub run {
      my ($self, %args) = @_;
      my $fix = $args{fix} ? 1 : 0;
      my @roots = $self->_audit_roots(%args);
      my $hooks = $self->_doctor_hook_results(%args);
      my @hook_failures = grep { !$_->{ok} } @{$hooks};
      return { ok => 1, hook_failures => scalar @hook_failures };
  }
  #%% _helper_issues
  #%% _shell_bootstrap_issues
  #%% _ssl_certificate_issues
#@@ Demo::Prompt _git_branch git_branch_for_project 2,3,4 w13 p0
  sub _git_branch {
      my ($self, $cwd) = @_;
      my @out = capture { system 'git', 'branch'; };
      chdir $cwd or die "Unable to restore cwd to $cwd: $!";
      for my $line (@out) { return $1 if $line =~ /^\* (.+)$/; }
      return '';
  }
#@@ Demo::Housekeeper _config housekeeper_config 2,3 w7 p1
  sub _config {
      my ($self) = @_;
      my $files = Demo::FileRegistry->new( paths => $self->{paths} );
      return Demo::Config->new( files => $files, paths => $self->{paths} )->config;
  }
  #-- ->config
#@@ Demo::InternalCLI _repo_private_cli_root internal_cli_repo_private_cli_root 1 w7 p1
  sub _repo_private_cli_root {
      return File::Spec->catdir( dirname(__FILE__), '..', '..', '..', 'share', 'private-cli' );
  }
  #-- 'private-cli'
#@@ Demo::InternalCLI _shared_private_cli_root internal_cli_shared_private_cli_root 1 w5 p1
  sub _shared_private_cli_root {
      return File::Spec->catdir( File::ShareDir::dist_dir('Demo-Dist'), 'private-cli' );
  }
  #-- 'private-cli'
#@@ Demo::InternalCLI _shared_private_cli_root internal_cli_shared_private_cli_root 1 w5 p1
  sub _shared_private_cli_root {
      return File::Spec->catdir( File::ShareDir::dist_dir(Demo::Dist), 'private-cli' );
  }
  #-- 'private-cli'
#@@ Demo::DockerCompose resolve docker_compose_resolve 2,3,5 w11 p1
  sub resolve {
      my ($self, %args) = @_;
      my @files = $self->_discover_base_files(%args);
      my @services = $self->_infer_services_from_args(@{ $args{args} || [] });
      my @enabled = $self->_discover_enabled_services(%args);
      return { command => [ 'docker', 'compose', map { ( '-f', $_ ) } @files ], services => \@services };
  }
#@@ Demo::DockerCompose run docker_compose_run 3 w6 p1
  sub run {
      my ($self, %args) = @_;
      my $resolved = $self->resolve(%args);
      return capture { system @{ $resolved->{command} } } if $args{capture};
      system @{ $resolved->{command} };
      return $? >> 8;
  }
#@@ Demo::Query _parse_query_input query_parse_input 2,3,4 w15 p1
  sub _parse_query_input {
      my ($command, $text) = @_;
      return TOML::Tiny::from_toml($text) if $command eq 'toml';
      return YAML::XS::Load($text) if $command eq 'yaml';
      die "Unsupported data query command $command\n";
  }
#@@ Demo::Files _configured_alias_cache_key app_file_alias_cache_key 2 w7 p0
  sub _configured_alias_cache_key {
      my ($paths) = @_;
      return join "\n", $paths->current_project_root, $paths->runtime_roots;
  }
#@@ Demo::Helpers _helper_asset_path internal_cli_helper_asset_path 2,4 w6 p1
  sub _helper_asset_path {
      my ($name) = @_;
      my $repo = File::Spec->catfile( _repo_private_cli_root(), $name );
      return $repo if -f $repo;
      return File::Spec->catfile( _shared_private_cli_root(), $name );
  }
#@@ Demo::Helpers canonical_helper_name internal_cli_canonical_helper_name 2,3,5 w11 p1
  sub canonical_helper_name {
      my ($name) = @_;
      return '' if !defined $name || $name eq '';
      my %aliases = helper_aliases();
      return $aliases{$name} if exists $aliases{$name};
      return $name if grep { $_ eq $name } helper_names();
      return '';
  }
#@@ Demo::Query _parse_ini query_parse_ini 3 w5 p1
  sub _parse_ini {
      my ($text) = @_;
      my %data = ( _global => {} );
      my $current_section = '_global';
      return \%data;
  }
