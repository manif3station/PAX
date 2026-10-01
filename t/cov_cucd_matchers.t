use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::CodeUnitCompiler;

=pod

=head1 NAME

t/cov_cucd_matchers.t - source-shape matcher coverage for the code-unit compiler

=head1 WHY IT EXISTS

C<_compile_simple_transform_sub_from_source> holds a long chain of matchers that
recognise a named sub by its name plus literal fragments of its body. Every matcher
needs a positive case (all fragments present) and, for each fragment, a near miss
(that fragment absent) so that both outcomes of each branch and condition run.

=head1 DESCRIPTION

The table below was derived from the matcher conditions. Each row names the sub
(or subs, for matchers that accept several names), the body fragments the matcher
requires, and the fragment subsets that must NOT match. Bodies are synthesised as
C<sub NAME { fragments }> with brace balancing so the body extractor sees them intact.

=cut

# build_source($name, \@fragments)
# Builds a synthetic module source whose single sub body is the joined fragments.
# Input: sub name and fragment list. Output: Perl source text with balanced braces.
sub build_source {
    my ($name, $frags) = @_;
    my $text = join("\n", @{$frags});
    my $open  = () = $text =~ /\{/g;
    my $close = () = $text =~ /\}/g;
    my $prefix = $close > $open ? '{' x ($close - $open) : '';
    my $suffix = $open > $close ? '}' x ($open - $close) : '';
    $suffix .= '}' x length($prefix);
    $prefix = '{' x length($prefix) if length $prefix;
    return "package Demo::Mod;\nsub $name {\n$prefix$text$suffix\n}\n1;\n";
}

# compile_sub($name, \@fragments)
# Runs the matcher chain for one synthetic sub.
# Input: sub name and fragments. Output: the matcher record or undef.
sub compile_sub {
    my ($name, $frags) = @_;
    my $source = build_source($name, $frags);
    return PAX::CodeUnitCompiler::_compile_simple_transform_sub_from_source($source, $name, "Demo::Mod::$name");
}

my $cases = 
[
  {
    "frags" => [
      "legacy_instruction"
    ],
    "line" => 8964,
    "names" => [
      "canonical_instruction"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "_legacy_stash_text",
      "\$LEGACY_SEP",
      "CODE\\d+"
    ],
    "line" => 8979,
    "names" => [
      "legacy_instruction"
    ],
    "variants" => [
      [
        "\$LEGACY_SEP",
        "CODE\\d+"
      ],
      [
        "_legacy_stash_text",
        "CODE\\d+"
      ],
      [
        "_legacy_stash_text",
        "\$LEGACY_SEP"
      ]
    ]
  },
  {
    "frags" => [
      "canonical_instruction"
    ],
    "line" => 8996,
    "names" => [
      "instruction_text"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "return shift;"
    ],
    "line" => 9011,
    "names" => [
      "render_template"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "runtime_outputs",
      "runtime_errors",
      "_legacy_bootstrap",
      "<!DOCTYPE html>"
    ],
    "line" => 9025,
    "names" => [
      "render_html"
    ],
    "variants" => [
      [
        "runtime_errors",
        "_legacy_bootstrap",
        "<!DOCTYPE html>"
      ],
      [
        "runtime_outputs",
        "_legacy_bootstrap",
        "<!DOCTYPE html>"
      ],
      [
        "runtime_outputs",
        "runtime_errors",
        "<!DOCTYPE html>"
      ],
      [
        "runtime_outputs",
        "runtime_errors",
        "_legacy_bootstrap"
      ]
    ]
  },
  {
    "frags" => [
      "json_decode",
      "return {} if \$text eq ''"
    ],
    "line" => 9044,
    "names" => [
      "_decode_structured_json"
    ],
    "variants" => [
      [
        "return {} if \$text eq ''"
      ],
      [
        "json_decode"
      ]
    ]
  },
  {
    "frags" => [
      "json_decode"
    ],
    "line" => 9060,
    "names" => [
      "_decode_stash_section"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "LEGACY_SEP",
      "\@LEGACY_KEYS",
      "split /(?:"
    ],
    "line" => 9075,
    "names" => [
      "_parse_legacy_sections"
    ],
    "variants" => [
      [
        "\@LEGACY_KEYS",
        "split /(?:"
      ],
      [
        "LEGACY_SEP",
        "split /(?:"
      ],
      [
        "LEGACY_SEP",
        "\@LEGACY_KEYS"
      ]
    ]
  },
  {
    "frags" => [
      "_legacy_value",
      "join \",\\n\""
    ],
    "line" => 9091,
    "names" => [
      "_legacy_stash_text"
    ],
    "variants" => [
      [
        "join \",\\n\""
      ],
      [
        "_legacy_value"
      ]
    ]
  },
  {
    "frags" => [
      "split /\\./",
      "exists \$value->{\$part}"
    ],
    "line" => 9107,
    "names" => [
      "_template_value"
    ],
    "variants" => [
      [
        "exists \$value->{\$part}"
      ],
      [
        "split /\\./"
      ]
    ]
  },
  {
    "frags" => [
      "dashboard_ajax_singleton_cleanup",
      "fetch_value",
      "window.__dashboardAjaxSingletons",
      "window.configs"
    ],
    "line" => 9123,
    "names" => [
      "_legacy_bootstrap"
    ],
    "variants" => [
      [
        "fetch_value",
        "window.__dashboardAjaxSingletons",
        "window.configs"
      ],
      [
        "dashboard_ajax_singleton_cleanup",
        "window.__dashboardAjaxSingletons",
        "window.configs"
      ],
      [
        "dashboard_ajax_singleton_cleanup",
        "fetch_value",
        "window.configs"
      ],
      [
        "dashboard_ajax_singleton_cleanup",
        "fetch_value",
        "window.__dashboardAjaxSingletons"
      ]
    ]
  },
  {
    "frags" => [
      "_legacy_quote",
      "ref(\$value) eq 'ARRAY'",
      "ref(\$value) eq 'HASH'"
    ],
    "line" => 9140,
    "names" => [
      "_legacy_value"
    ],
    "variants" => [
      [
        "ref(\$value) eq 'ARRAY'",
        "ref(\$value) eq 'HASH'"
      ],
      [
        "_legacy_quote",
        "ref(\$value) eq 'HASH'"
      ],
      [
        "_legacy_quote",
        "ref(\$value) eq 'ARRAY'"
      ]
    ]
  },
  {
    "frags" => [
      "s/\\\\/\\\\\\\\/g",
      "s/'/\\\\'/g"
    ],
    "line" => 9157,
    "names" => [
      "_legacy_quote"
    ],
    "variants" => [
      [
        "s/'/\\\\'/g"
      ],
      [
        "s/\\\\/\\\\\\\\/g"
      ]
    ]
  },
  {
    "frags" => [
      "s/\\A\\s+//",
      "s/\\s+\\z//"
    ],
    "line" => 9172,
    "names" => [
      "_trim"
    ],
    "variants" => [
      [
        "s/\\s+\\z//"
      ],
      [
        "s/\\A\\s+//"
      ]
    ]
  },
  {
    "frags" => [
      "s/\\n+\\z//"
    ],
    "line" => 9187,
    "names" => [
      "_trim_trailing_newline"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "&amp;",
      "&lt;",
      "&gt;",
      "&quot;"
    ],
    "line" => 9201,
    "names" => [
      "_html"
    ],
    "variants" => [
      [
        "&lt;",
        "&gt;",
        "&quot;"
      ],
      [
        "&amp;",
        "&gt;",
        "&quot;"
      ],
      [
        "&amp;",
        "&lt;",
        "&quot;"
      ],
      [
        "&amp;",
        "&lt;",
        "&gt;"
      ]
    ]
  },
  {
    "frags" => [
      "PathRegistry->new",
      "workspace_roots",
      "project_roots"
    ],
    "line" => 9218,
    "names" => [
      "build_path_registry"
    ],
    "variants" => [
      [
        "workspace_roots",
        "project_roots"
      ],
      [
        "PathRegistry->new",
        "project_roots"
      ],
      [
        "PathRegistry->new",
        "workspace_roots"
      ]
    ]
  },
  {
    "frags" => [
      "GetOptionsFromArray",
      "_resolve_open_file_matches",
      "_select_open_file_matches",
      "_command_exec"
    ],
    "line" => 9235,
    "names" => [
      "run_open_file_command"
    ],
    "variants" => [
      [
        "_resolve_open_file_matches",
        "_select_open_file_matches",
        "_command_exec"
      ],
      [
        "GetOptionsFromArray",
        "_select_open_file_matches",
        "_command_exec"
      ],
      [
        "GetOptionsFromArray",
        "_resolve_open_file_matches",
        "_command_exec"
      ],
      [
        "GetOptionsFromArray",
        "_resolve_open_file_matches",
        "_select_open_file_matches"
      ]
    ]
  },
  {
    "frags" => [
      "\$ENV{VISUAL}",
      "\$ENV{EDITOR}",
      "'vim'"
    ],
    "line" => 9259,
    "names" => [
      "_default_editor"
    ],
    "variants" => [
      [
        "\$ENV{EDITOR}",
        "'vim'"
      ],
      [
        "\$ENV{VISUAL}",
        "'vim'"
      ],
      [
        "\$ENV{VISUAL}",
        "\$ENV{EDITOR}"
      ]
    ]
  },
  {
    "frags" => [
      "vim|nvim|vi|gvim|iv"
    ],
    "line" => 9275,
    "names" => [
      "_editor_supports_tabs"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "_unique_matches",
      "_selection_matches",
      "Invalid file selection"
    ],
    "line" => 9289,
    "names" => [
      "_select_open_file_matches"
    ],
    "variants" => [
      [
        "_selection_matches",
        "Invalid file selection"
      ],
      [
        "_unique_matches",
        "Invalid file selection"
      ],
      [
        "_unique_matches",
        "_selection_matches"
      ]
    ]
  },
  {
    "frags" => [
      "return \@\$matches if \$choices eq ''"
    ],
    "line" => 9307,
    "names" => [
      "_selection_matches"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "!\$seen{\$_}++"
    ],
    "line" => 9321,
    "names" => [
      "_unique_matches"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "_scope_match_rank",
      "sort {"
    ],
    "line" => 9335,
    "names" => [
      "_ordered_scope_matches"
    ],
    "variants" => [
      [
        "sort {"
      ],
      [
        "_scope_match_rank"
      ]
    ]
  },
  {
    "frags" => [
      "_compile_open_file_regex",
      "basename",
      "score = 50"
    ],
    "line" => 9352,
    "names" => [
      "_scope_match_rank"
    ],
    "variants" => [
      [
        "basename",
        "score = 50"
      ],
      [
        "_compile_open_file_regex",
        "score = 50"
      ],
      [
        "_compile_open_file_regex",
        "basename"
      ]
    ]
  },
  {
    "frags" => [
      "_named_source_matches",
      "File::Find::find",
      "_ordered_scope_matches"
    ],
    "line" => 9369,
    "names" => [
      "_resolve_open_file_matches"
    ],
    "variants" => [
      [
        "File::Find::find",
        "_ordered_scope_matches"
      ],
      [
        "_named_source_matches",
        "_ordered_scope_matches"
      ],
      [
        "_named_source_matches",
        "File::Find::find"
      ]
    ]
  },
  {
    "frags" => [
      "_open_file_roots",
      "_existing_named_files",
      "_java_archive_source_matches"
    ],
    "line" => 9388,
    "names" => [
      "_named_source_matches"
    ],
    "variants" => [
      [
        "_existing_named_files",
        "_java_archive_source_matches"
      ],
      [
        "_open_file_roots",
        "_java_archive_source_matches"
      ],
      [
        "_open_file_roots",
        "_existing_named_files"
      ]
    ]
  },
  {
    "frags" => [
      "cwd()",
      "workspace_roots",
      "\@INC"
    ],
    "line" => 9408,
    "names" => [
      "_open_file_roots"
    ],
    "variants" => [
      [
        "workspace_roots",
        "\@INC"
      ],
      [
        "cwd()",
        "\@INC"
      ],
      [
        "cwd()",
        "workspace_roots"
      ]
    ]
  },
  {
    "frags" => [
      "catfile",
      "sort \@found"
    ],
    "line" => 9424,
    "names" => [
      "_existing_named_files"
    ],
    "variants" => [
      [
        "sort \@found"
      ],
      [
        "catfile"
      ]
    ]
  },
  {
    "frags" => [
      "FileRegistry->new",
      "Config->new",
      "register_named_paths",
      "register_named_files"
    ],
    "line" => 9439,
    "names" => [
      "_open_file_registries"
    ],
    "variants" => [
      [
        "Config->new",
        "register_named_paths",
        "register_named_files"
      ],
      [
        "FileRegistry->new",
        "register_named_paths",
        "register_named_files"
      ],
      [
        "FileRegistry->new",
        "Config->new",
        "register_named_files"
      ],
      [
        "FileRegistry->new",
        "Config->new",
        "register_named_paths"
      ]
    ]
  },
  {
    "frags" => [
      "File::Spec->catfile",
      "return -f \$target ? \$target : undef"
    ],
    "line" => 9456,
    "names" => [
      "_scope_relative_path_match"
    ],
    "variants" => [
      [
        "return -f \$target ? \$target : undef"
      ],
      [
        "File::Spec->catfile"
      ]
    ]
  },
  {
    "frags" => [
      "Invalid regex",
      "qr/\$pattern/i"
    ],
    "line" => 9471,
    "names" => [
      "_compile_open_file_regex"
    ],
    "variants" => [
      [
        "qr/\$pattern/i"
      ],
      [
        "Invalid regex"
      ]
    ]
  },
  {
    "frags" => [
      "_candidate_java_source_archives",
      "_extract_java_sources_from_archive",
      "_download_java_source_matches"
    ],
    "line" => 9486,
    "names" => [
      "_java_archive_source_matches"
    ],
    "variants" => [
      [
        "_extract_java_sources_from_archive",
        "_download_java_source_matches"
      ],
      [
        "_candidate_java_source_archives",
        "_download_java_source_matches"
      ],
      [
        "_candidate_java_source_archives",
        "_extract_java_sources_from_archive"
      ]
    ]
  },
  {
    "frags" => [
      "_java_source_archive_roots",
      "File::Find::find"
    ],
    "line" => 9506,
    "names" => [
      "_candidate_java_source_archives"
    ],
    "variants" => [
      [
        "File::Find::find"
      ],
      [
        "_java_source_archive_roots"
      ]
    ]
  },
  {
    "frags" => [
      "'.m2'",
      "'.gradle'",
      "JAVA_HOME"
    ],
    "line" => 9522,
    "names" => [
      "_java_source_archive_roots"
    ],
    "variants" => [
      [
        "'.gradle'",
        "JAVA_HOME"
      ],
      [
        "'.m2'",
        "JAVA_HOME"
      ],
      [
        "'.m2'",
        "'.gradle'"
      ]
    ]
  },
  {
    "frags" => [
      "Archive::Zip->new",
      "_matching_java_archive_entries",
      "_cached_archive_source_path"
    ],
    "line" => 9538,
    "names" => [
      "_extract_java_sources_from_archive"
    ],
    "variants" => [
      [
        "_matching_java_archive_entries",
        "_cached_archive_source_path"
      ],
      [
        "Archive::Zip->new",
        "_cached_archive_source_path"
      ],
      [
        "Archive::Zip->new",
        "_matching_java_archive_entries"
      ]
    ]
  },
  {
    "frags" => [
      "member->fileName",
      "suffix"
    ],
    "line" => 9556,
    "names" => [
      "_matching_java_archive_entries"
    ],
    "variants" => [
      [
        "suffix"
      ],
      [
        "member->fileName"
      ]
    ]
  },
  {
    "frags" => [
      "md5_hex",
      "java-sources"
    ],
    "line" => 9571,
    "names" => [
      "_cached_archive_source_path"
    ],
    "variants" => [
      [
        "java-sources"
      ],
      [
        "md5_hex"
      ]
    ]
  },
  {
    "frags" => [
      "_maven_search_documents",
      "_download_maven_source_jar",
      "_extract_java_sources_from_archive"
    ],
    "line" => 9586,
    "names" => [
      "_download_java_source_matches"
    ],
    "variants" => [
      [
        "_download_maven_source_jar",
        "_extract_java_sources_from_archive"
      ],
      [
        "_maven_search_documents",
        "_extract_java_sources_from_archive"
      ],
      [
        "_maven_search_documents",
        "_download_maven_source_jar"
      ]
    ]
  },
  {
    "frags" => [
      "search.maven.org",
      "uri_escape_utf8",
      "decode_json"
    ],
    "line" => 9605,
    "names" => [
      "_maven_search_documents"
    ],
    "variants" => [
      [
        "uri_escape_utf8",
        "decode_json"
      ],
      [
        "search.maven.org",
        "decode_json"
      ],
      [
        "search.maven.org",
        "uri_escape_utf8"
      ]
    ]
  },
  {
    "frags" => [
      "repo1.maven.org",
      "mirror",
      "maven-sources"
    ],
    "line" => 9621,
    "names" => [
      "_download_maven_source_jar"
    ],
    "variants" => [
      [
        "mirror",
        "maven-sources"
      ],
      [
        "repo1.maven.org",
        "maven-sources"
      ],
      [
        "repo1.maven.org",
        "mirror"
      ]
    ]
  },
  {
    "frags" => [
      "exit \$code"
    ],
    "line" => 9637,
    "names" => [
      "_command_exit"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "indicator_dir",
      "LOCK_EX",
      "secure_file_permissions",
      "status.json"
    ],
    "line" => 9651,
    "names" => [
      "set_indicator"
    ],
    "variants" => [
      [
        "LOCK_EX",
        "secure_file_permissions",
        "status.json"
      ],
      [
        "indicator_dir",
        "secure_file_permissions",
        "status.json"
      ],
      [
        "indicator_dir",
        "LOCK_EX",
        "status.json"
      ],
      [
        "indicator_dir",
        "LOCK_EX",
        "secure_file_permissions"
      ]
    ]
  },
  {
    "frags" => [
      "_indicator_file_candidates",
      "_read_indicator_file"
    ],
    "line" => 9669,
    "names" => [
      "get_indicator"
    ],
    "variants" => [
      [
        "_read_indicator_file"
      ],
      [
        "_indicator_file_candidates"
      ]
    ]
  },
  {
    "frags" => [
      "indicators_roots",
      "get_indicator",
      "priority"
    ],
    "line" => 9686,
    "names" => [
      "list_indicators"
    ],
    "variants" => [
      [
        "get_indicator",
        "priority"
      ],
      [
        "indicators_roots",
        "priority"
      ],
      [
        "indicators_roots",
        "get_indicator"
      ]
    ]
  },
  {
    "frags" => [
      "index( \$text, '[%' )"
    ],
    "line" => 9703,
    "names" => [
      "_is_template_toolkit_text"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "Collector indicator candidate requires a collector job hash",
      "managed_by_collector",
      "_is_template_toolkit_text"
    ],
    "line" => 9717,
    "names" => [
      "collector_indicator_candidate"
    ],
    "variants" => [
      [
        "managed_by_collector",
        "_is_template_toolkit_text"
      ],
      [
        "Collector indicator candidate requires a collector job hash",
        "_is_template_toolkit_text"
      ],
      [
        "Collector indicator candidate requires a collector job hash",
        "managed_by_collector"
      ]
    ]
  },
  {
    "frags" => [
      "indicators_roots",
      "status.json"
    ],
    "line" => 9735,
    "names" => [
      "delete_indicator"
    ],
    "variants" => [
      [
        "status.json"
      ],
      [
        "indicators_roots"
      ]
    ]
  },
  {
    "frags" => [
      "page_status_icon",
      "managed_by_collector"
    ],
    "line" => 9750,
    "names" => [
      "_indicator_matches"
    ],
    "variants" => [
      [
        "managed_by_collector"
      ],
      [
        "page_status_icon"
      ]
    ]
  },
  {
    "frags" => [
      "_indicator_file_candidates",
      "_read_indicator_file"
    ],
    "line" => 9765,
    "names" => [
      "_local_indicator"
    ],
    "variants" => [
      [
        "_read_indicator_file"
      ],
      [
        "_indicator_file_candidates"
      ]
    ]
  },
  {
    "frags" => [
      "shift \@files",
      "_indicator_file_candidates",
      "_read_indicator_file"
    ],
    "line" => 9782,
    "names" => [
      "_nearest_inherited_indicator"
    ],
    "variants" => [
      [
        "_indicator_file_candidates",
        "_read_indicator_file"
      ],
      [
        "shift \@files",
        "_read_indicator_file"
      ],
      [
        "shift \@files",
        "_indicator_file_candidates"
      ]
    ]
  },
  {
    "frags" => [
      "managed_by_collector",
      "missing"
    ],
    "line" => 9800,
    "names" => [
      "_is_placeholder_missing_indicator"
    ],
    "variants" => [
      [
        "missing"
      ],
      [
        "managed_by_collector"
      ]
    ]
  },
  {
    "frags" => [
      "_nearest_inherited_indicator",
      "collector_indicator_candidate",
      "_indicator_matches",
      "managed_by_collector"
    ],
    "line" => 9815,
    "names" => [
      "sync_collectors"
    ],
    "variants" => [
      [
        "collector_indicator_candidate",
        "_indicator_matches",
        "managed_by_collector"
      ],
      [
        "_nearest_inherited_indicator",
        "_indicator_matches",
        "managed_by_collector"
      ],
      [
        "_nearest_inherited_indicator",
        "collector_indicator_candidate",
        "managed_by_collector"
      ],
      [
        "_nearest_inherited_indicator",
        "collector_indicator_candidate",
        "_indicator_matches"
      ]
    ]
  },
  {
    "frags" => [
      "stale",
      "set_indicator"
    ],
    "line" => 9841,
    "names" => [
      "mark_stale"
    ],
    "variants" => [
      [
        "set_indicator"
      ],
      [
        "stale"
      ]
    ]
  },
  {
    "frags" => [
      "updated_at",
      "time - \$item->{updated_at}"
    ],
    "line" => 9858,
    "names" => [
      "is_stale"
    ],
    "variants" => [
      [],
      [
        "updated_at"
      ]
    ]
  },
  {
    "frags" => [
      "command_in_path('docker')",
      "rev-parse', '--is-inside-work-tree'",
      "diff', '--quiet', '--ignore-submodules', 'HEAD', '--'"
    ],
    "line" => 9873,
    "names" => [
      "refresh_core_indicators"
    ],
    "variants" => [
      [
        "rev-parse', '--is-inside-work-tree'",
        "diff', '--quiet', '--ignore-submodules', 'HEAD', '--'"
      ],
      [
        "command_in_path('docker')",
        "diff', '--quiet', '--ignore-submodules', 'HEAD', '--'"
      ],
      [
        "command_in_path('docker')",
        "rev-parse', '--is-inside-work-tree'"
      ]
    ]
  },
  {
    "frags" => [
      "\$map->{ok}",
      "\$map->{error}"
    ],
    "line" => 9890,
    "names" => [
      "_status_icon_for"
    ],
    "variants" => [
      [
        "\$map->{error}"
      ],
      [
        "\$map->{ok}"
      ]
    ]
  },
  {
    "frags" => [
      "_status_icon_for",
      "PROMPT_STATUS_ICONS"
    ],
    "line" => 9905,
    "names" => [
      "prompt_status_icon"
    ],
    "variants" => [
      [
        "PROMPT_STATUS_ICONS"
      ],
      [
        "_status_icon_for"
      ]
    ]
  },
  {
    "frags" => [
      "page_status_icon",
      "_status_icon_for"
    ],
    "line" => 9921,
    "names" => [
      "_page_status_icon"
    ],
    "variants" => [
      [
        "_status_icon_for"
      ],
      [
        "page_status_icon"
      ]
    ]
  },
  {
    "frags" => [
      "list_indicators",
      "_page_status_icon",
      "prompt_visible"
    ],
    "line" => 9937,
    "names" => [
      "page_header_items"
    ],
    "variants" => [
      [
        "_page_status_icon",
        "prompt_visible"
      ],
      [
        "list_indicators",
        "prompt_visible"
      ],
      [
        "list_indicators",
        "_page_status_icon"
      ]
    ]
  },
  {
    "frags" => [
      "page_header_items",
      "status => \$STATUS_ICONS"
    ],
    "line" => 9955,
    "names" => [
      "page_header_payload"
    ],
    "variants" => [
      [
        "status => \$STATUS_ICONS"
      ],
      [
        "page_header_items"
      ]
    ]
  },
  {
    "frags" => [
      "_channel_json( 'RESULT', 'RESULT_FILE' )",
      "decode_json",
      "RESULT must decode to a hash"
    ],
    "line" => 9971,
    "names" => [
      "current"
    ],
    "variants" => [
      [
        "decode_json",
        "RESULT must decode to a hash"
      ],
      [
        "_channel_json( 'RESULT', 'RESULT_FILE' )",
        "RESULT must decode to a hash"
      ],
      [
        "_channel_json( 'RESULT', 'RESULT_FILE' )",
        "decode_json"
      ]
    ]
  },
  {
    "frags" => [
      "RESULT state must be a hash",
      "clear_current",
      "_set_channel( 'RESULT', 'RESULT_FILE'"
    ],
    "line" => 9986,
    "names" => [
      "set_current"
    ],
    "variants" => [
      [
        "clear_current",
        "_set_channel( 'RESULT', 'RESULT_FILE'"
      ],
      [
        "RESULT state must be a hash",
        "_set_channel( 'RESULT', 'RESULT_FILE'"
      ],
      [
        "RESULT state must be a hash",
        "clear_current"
      ]
    ]
  },
  {
    "frags" => [
      "_clear_channel( 'RESULT', 'RESULT_FILE' )"
    ],
    "line" => 10003,
    "names" => [
      "clear_current"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "LAST_RESULT",
      "shift if \@_",
      "decode_json"
    ],
    "line" => 10017,
    "names" => [
      "last_result"
    ],
    "variants" => [
      [
        "shift if \@_",
        "decode_json"
      ],
      [
        "LAST_RESULT",
        "decode_json"
      ],
      [
        "LAST_RESULT",
        "shift if \@_"
      ]
    ]
  },
  {
    "frags" => [
      "LAST_RESULT state must be a hash",
      "clear_last_result",
      "_set_channel( 'LAST_RESULT', 'LAST_RESULT_FILE'"
    ],
    "line" => 10032,
    "names" => [
      "set_last_result"
    ],
    "variants" => [
      [
        "clear_last_result",
        "_set_channel( 'LAST_RESULT', 'LAST_RESULT_FILE'"
      ],
      [
        "LAST_RESULT state must be a hash",
        "_set_channel( 'LAST_RESULT', 'LAST_RESULT_FILE'"
      ],
      [
        "LAST_RESULT state must be a hash",
        "clear_last_result"
      ]
    ]
  },
  {
    "frags" => [
      "LAST_RESULT",
      "_clear_channel( 'LAST_RESULT', 'LAST_RESULT_FILE' )"
    ],
    "line" => 10049,
    "names" => [
      "clear_last_result"
    ],
    "variants" => [
      [],
      [
        "LAST_RESULT"
      ]
    ]
  },
  {
    "frags" => [
      "return \$stderr =~ /\\[\\[STOP\\]\\]/"
    ],
    "line" => 10064,
    "names" => [
      "stop_requested"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "sort keys %{ current() }"
    ],
    "line" => 10077,
    "names" => [
      "names"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "exists current()->{\$name}"
    ],
    "line" => 10091,
    "names" => [
      "has"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "my \$data = current()",
      "return \$data->{\$name}"
    ],
    "line" => 10105,
    "names" => [
      "entry"
    ],
    "variants" => [
      [
        "return \$data->{\$name}"
      ],
      [
        "my \$data = current()"
      ]
    ]
  },
  {
    "frags" => [
      "my \$entry = entry(\$name)",
      "return '' if ref(\$entry) ne 'HASH'"
    ],
    "line" => 10120,
    "names" => [
      "stdout",
      "stderr"
    ],
    "variants" => [
      [
        "return '' if ref(\$entry) ne 'HASH'"
      ],
      [
        "my \$entry = entry(\$name)"
      ]
    ]
  },
  {
    "frags" => [
      "my \$entry = entry(\$name)",
      "return \$entry->{exit_code}"
    ],
    "line" => 10135,
    "names" => [
      "exit_code"
    ],
    "variants" => [
      [
        "return \$entry->{exit_code}"
      ],
      [
        "my \$entry = entry(\$name)"
      ]
    ]
  },
  {
    "frags" => [
      "my \@names = names()",
      "return \$names[-1]"
    ],
    "line" => 10150,
    "names" => [
      "last_name"
    ],
    "variants" => [
      [
        "return \$names[-1]"
      ],
      [
        "my \@names = names()"
      ]
    ]
  },
  {
    "frags" => [
      "my \$name = last_name()",
      "return entry(\$name)"
    ],
    "line" => 10165,
    "names" => [
      "last_entry"
    ],
    "variants" => [
      [
        "return entry(\$name)"
      ],
      [
        "my \$name = last_name()"
      ]
    ]
  },
  {
    "frags" => [
      "Run Report",
      "_command_name",
      "encode( 'UTF-8'"
    ],
    "line" => 10181,
    "names" => [
      "report"
    ],
    "variants" => [
      [
        "_command_name",
        "encode( 'UTF-8'"
      ],
      [
        "Run Report",
        "encode( 'UTF-8'"
      ],
      [
        "Run Report",
        "_command_name"
      ]
    ]
  },
  {
    "frags" => [
      "_channel_json( 'RESULT', 'RESULT_FILE' )"
    ],
    "line" => 10199,
    "names" => [
      "_current_json"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "\$ENV{",
      "RESULT_INLINE_MAX",
      "return 65536"
    ],
    "line" => 10213,
    "names" => [
      "_max_inline_bytes"
    ],
    "variants" => [
      [
        "RESULT_INLINE_MAX",
        "return 65536"
      ],
      [
        "\$ENV{",
        "return 65536"
      ],
      [
        "\$ENV{",
        "RESULT_INLINE_MAX"
      ]
    ]
  },
  {
    "frags" => [
      "tempfile( 'dashboard-result-XXXXXX'",
      "FD_CLOEXEC",
      "/dev/fd/\$fd"
    ],
    "line" => 10228,
    "names" => [
      "_open_channel_file"
    ],
    "variants" => [
      [
        "FD_CLOEXEC",
        "/dev/fd/\$fd"
      ],
      [
        "tempfile( 'dashboard-result-XXXXXX'",
        "/dev/fd/\$fd"
      ],
      [
        "tempfile( 'dashboard-result-XXXXXX'",
        "FD_CLOEXEC"
      ]
    ]
  },
  {
    "frags" => [
      "open my \$fh, '<:raw', \$path",
      "Unable to read \$env_name file \$path"
    ],
    "line" => 10243,
    "names" => [
      "_channel_json"
    ],
    "variants" => [
      [
        "Unable to read \$env_name file \$path"
      ],
      [
        "open my \$fh, '<:raw', \$path"
      ]
    ]
  },
  {
    "frags" => [
      "encode_json",
      "_max_inline_bytes",
      "_open_channel_file",
      "truncate"
    ],
    "line" => 10257,
    "names" => [
      "_set_channel"
    ],
    "variants" => [
      [
        "_max_inline_bytes",
        "_open_channel_file",
        "truncate"
      ],
      [
        "encode_json",
        "_open_channel_file",
        "truncate"
      ],
      [
        "encode_json",
        "_max_inline_bytes",
        "truncate"
      ],
      [
        "encode_json",
        "_max_inline_bytes",
        "_open_channel_file"
      ]
    ]
  },
  {
    "frags" => [
      "delete \$ENV{\$env_name}",
      "_clear_channel_file"
    ],
    "line" => 10276,
    "names" => [
      "_clear_channel"
    ],
    "variants" => [
      [
        "_clear_channel_file"
      ],
      [
        "delete \$ENV{\$env_name}"
      ]
    ]
  },
  {
    "frags" => [
      "CHANNEL_FILE_HANDLE",
      "CHANNEL_FILE_PATH",
      "close \$CHANNEL_FILE_HANDLE"
    ],
    "line" => 10291,
    "names" => [
      "_clear_channel_file"
    ],
    "variants" => [
      [
        "CHANNEL_FILE_PATH"
      ],
      [
        "CHANNEL_FILE_HANDLE",
        "close \$CHANNEL_FILE_HANDLE"
      ],
      [
        "CHANNEL_FILE_HANDLE",
        "CHANNEL_FILE_PATH"
      ]
    ]
  },
  {
    "frags" => [
      "\$0",
      "basename",
      "dirname",
      "\$ENV{"
    ],
    "line" => 10306,
    "names" => [
      "_command_name"
    ],
    "variants" => [
      [
        "basename",
        "dirname",
        "\$ENV{"
      ],
      [
        "\$0",
        "dirname",
        "\$ENV{"
      ],
      [
        "\$0",
        "basename",
        "\$ENV{"
      ],
      [
        "\$0",
        "basename",
        "dirname"
      ]
    ]
  },
  {
    "frags" => [
      "Usage: dashboard which [--edit]"
    ],
    "line" => 10322,
    "names" => [
      "_usage"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "workspace_roots",
      "project_roots",
      "qw(projects src work)"
    ],
    "line" => 10336,
    "names" => [
      "_build_paths"
    ],
    "variants" => [
      [
        "project_roots",
        "qw(projects src work)"
      ],
      [
        "workspace_roots",
        "qw(projects src work)"
      ],
      [
        "workspace_roots",
        "project_roots"
      ]
    ]
  },
  {
    "frags" => [
      "\$ENV{FOO_ENTRY} || 'bar_default'"
    ],
    "line" => 10352,
    "names" => [
      "my_entry_command"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "exec { \$command[0] } \@command;"
    ],
    "line" => 10368,
    "names" => [
      "_command_exec"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "qw(run run.pl run.sh run.bash run.ps1 run.cmd run.bat run.go run.java)",
      "resolve_runnable_file"
    ],
    "line" => 10381,
    "names" => [
      "_resolve_directory_runner"
    ],
    "variants" => [
      [
        "resolve_runnable_file"
      ],
      [
        "qw(run run.pl run.sh run.bash run.ps1 run.cmd run.bat run.go run.java)"
      ]
    ]
  },
  {
    "frags" => [
      "_resolve_directory_runner",
      "resolve_runnable_file"
    ],
    "line" => 10395,
    "names" => [
      "_resolved_command_path"
    ],
    "variants" => [
      [
        "resolve_runnable_file"
      ],
      [
        "_resolve_directory_runner"
      ]
    ]
  },
  {
    "frags" => [
      "reverse \$paths->cli_layers",
      "_resolved_command_path"
    ],
    "line" => 10410,
    "names" => [
      "_custom_command_path"
    ],
    "variants" => [
      [
        "_resolved_command_path"
      ],
      [
        "reverse \$paths->cli_layers"
      ]
    ]
  },
  {
    "frags" => [
      "cli_layers",
      "is_runnable_file",
      "\$command . '.d'"
    ],
    "line" => 10425,
    "names" => [
      "_command_hook_files"
    ],
    "variants" => [
      [
        "is_runnable_file",
        "\$command . '.d'"
      ],
      [
        "cli_layers",
        "\$command . '.d'"
      ],
      [
        "cli_layers",
        "is_runnable_file"
      ]
    ]
  },
  {
    "frags" => [
      "canonical_helper_name",
      "ensure_helpers",
      "helper_path"
    ],
    "line" => 10440,
    "names" => [
      "_builtin_target"
    ],
    "variants" => [
      [
        "ensure_helpers",
        "helper_path"
      ],
      [
        "canonical_helper_name",
        "helper_path"
      ],
      [
        "canonical_helper_name",
        "ensure_helpers"
      ]
    ]
  },
  {
    "frags" => [
      "_custom_command_path",
      "_command_hook_files"
    ],
    "line" => 10456,
    "names" => [
      "_custom_target"
    ],
    "variants" => [
      [
        "_command_hook_files"
      ],
      [
        "_custom_command_path"
      ]
    ]
  },
  {
    "frags" => [
      "SkillManager->new",
      "SkillDispatcher->new",
      "command_spec",
      "command_hook_paths"
    ],
    "line" => 10472,
    "names" => [
      "_locate_skill_target"
    ],
    "variants" => [
      [
        "SkillDispatcher->new",
        "command_spec",
        "command_hook_paths"
      ],
      [
        "SkillManager->new",
        "command_spec",
        "command_hook_paths"
      ],
      [
        "SkillManager->new",
        "SkillDispatcher->new",
        "command_hook_paths"
      ],
      [
        "SkillManager->new",
        "SkillDispatcher->new",
        "command_spec"
      ]
    ]
  },
  {
    "frags" => [
      "_locate_skill_target",
      "_builtin_target",
      "_custom_target"
    ],
    "line" => 10490,
    "names" => [
      "_locate_target"
    ],
    "variants" => [
      [
        "_builtin_target",
        "_custom_target"
      ],
      [
        "_locate_skill_target",
        "_custom_target"
      ],
      [
        "_locate_skill_target",
        "_builtin_target"
      ]
    ]
  },
  {
    "frags" => [
      "GetOptionsFromArray",
      "_build_paths",
      "_locate_target",
      "_command_exec"
    ],
    "line" => 10508,
    "names" => [
      "run_which_command"
    ],
    "variants" => [
      [
        "_build_paths",
        "_locate_target",
        "_command_exec"
      ],
      [
        "GetOptionsFromArray",
        "_locate_target",
        "_command_exec"
      ],
      [
        "GetOptionsFromArray",
        "_build_paths",
        "_command_exec"
      ],
      [
        "GetOptionsFromArray",
        "_build_paths",
        "_locate_target"
      ]
    ]
  },
  {
    "frags" => [
      "PathRegistry->new",
      "SkillManager->new",
      "workspace_roots",
      "project_roots"
    ],
    "line" => 10530,
    "names" => [
      "new"
    ],
    "variants" => [
      [
        "SkillManager->new",
        "workspace_roots",
        "project_roots"
      ],
      [
        "PathRegistry->new",
        "workspace_roots",
        "project_roots"
      ],
      [
        "PathRegistry->new",
        "SkillManager->new",
        "project_roots"
      ],
      [
        "PathRegistry->new",
        "SkillManager->new",
        "workspace_roots"
      ]
    ]
  },
  {
    "frags" => [
      "Unknown dashboard command",
      "top_level_suggestions"
    ],
    "line" => 10548,
    "names" => [
      "unknown_command_message"
    ],
    "variants" => [
      [
        "top_level_suggestions"
      ],
      [
        "Unknown dashboard command"
      ]
    ]
  },
  {
    "frags" => [
      "Skill '\$skill_name' not found",
      "is disabled",
      "skill_command_suggestions"
    ],
    "line" => 10569,
    "names" => [
      "unknown_skill_command_message"
    ],
    "variants" => [
      [
        "is disabled",
        "skill_command_suggestions"
      ],
      [
        "Skill '\$skill_name' not found",
        "skill_command_suggestions"
      ],
      [
        "Skill '\$skill_name' not found",
        "is disabled"
      ]
    ]
  },
  {
    "frags" => [
      "_top_level_candidates"
    ],
    "line" => 10585,
    "names" => [
      "top_level_candidates"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "_rank_candidates",
      "_top_level_candidates"
    ],
    "line" => 10599,
    "names" => [
      "top_level_suggestions"
    ],
    "variants" => [
      [
        "_top_level_candidates"
      ],
      [
        "_rank_candidates"
      ]
    ]
  },
  {
    "frags" => [
      "_skill_command_entries",
      "_all_skill_command_entries"
    ],
    "line" => 10615,
    "names" => [
      "skill_commands"
    ],
    "variants" => [
      [],
      [
        "_skill_command_entries"
      ]
    ]
  },
  {
    "frags" => [
      "_skill_command_entries",
      "_all_skill_command_entries",
      "_rank_candidates"
    ],
    "line" => 10631,
    "names" => [
      "skill_command_suggestions"
    ],
    "variants" => [
      [
        "_rank_candidates"
      ],
      [
        "_skill_command_entries",
        "_rank_candidates"
      ],
      [
        "_skill_command_entries",
        "_all_skill_command_entries"
      ]
    ]
  },
  {
    "frags" => [
      "helper_names",
      "helper_aliases",
      "cli_roots"
    ],
    "line" => 10649,
    "names" => [
      "_top_level_candidates"
    ],
    "variants" => [
      [
        "helper_aliases",
        "cli_roots"
      ],
      [
        "helper_names",
        "cli_roots"
      ],
      [
        "helper_names",
        "helper_aliases"
      ]
    ]
  },
  {
    "frags" => [
      "installed_skill_roots",
      "_skill_command_entries"
    ],
    "line" => 10665,
    "names" => [
      "_all_skill_command_entries"
    ],
    "variants" => [
      [
        "_skill_command_entries"
      ],
      [
        "installed_skill_roots"
      ]
    ]
  },
  {
    "frags" => [
      "get_skill_path",
      "_collect_skill_commands"
    ],
    "line" => 10680,
    "names" => [
      "_skill_command_entries"
    ],
    "variants" => [
      [
        "_collect_skill_commands"
      ],
      [
        "get_skill_path"
      ]
    ]
  },
  {
    "frags" => [
      "File::Spec->catdir( \$skill_root, 'cli' )",
      "File::Spec->catdir( \$skill_root, 'skills' )",
      "is_runnable_file"
    ],
    "line" => 10695,
    "names" => [
      "_collect_skill_commands"
    ],
    "variants" => [
      [
        "File::Spec->catdir( \$skill_root, 'skills' )",
        "is_runnable_file"
      ],
      [
        "File::Spec->catdir( \$skill_root, 'cli' )",
        "is_runnable_file"
      ],
      [
        "File::Spec->catdir( \$skill_root, 'cli' )",
        "File::Spec->catdir( \$skill_root, 'skills' )"
      ]
    ]
  },
  {
    "frags" => [
      "_candidate_score",
      "splice \@scored, 5"
    ],
    "line" => 10711,
    "names" => [
      "_rank_candidates"
    ],
    "variants" => [
      [
        "splice \@scored, 5"
      ],
      [
        "_candidate_score"
      ]
    ]
  },
  {
    "frags" => [
      "_normalize_token",
      "_levenshtein_distance"
    ],
    "line" => 10726,
    "names" => [
      "_candidate_score"
    ],
    "variants" => [
      [
        "_levenshtein_distance"
      ],
      [
        "_normalize_token"
      ]
    ]
  },
  {
    "frags" => [
      "lc",
      "s/[^a-z0-9]+//g"
    ],
    "line" => 10742,
    "names" => [
      "_normalize_token"
    ],
    "variants" => [
      [
        "s/[^a-z0-9]+//g"
      ],
      [
        "lc"
      ]
    ]
  },
  {
    "frags" => [
      "split //",
      "\@dist = ( 0 .. scalar \@right )"
    ],
    "line" => 10756,
    "names" => [
      "_levenshtein_distance"
    ],
    "variants" => [
      [
        "\@dist = ( 0 .. scalar \@right )"
      ],
      [
        "split //"
      ]
    ]
  },
  {
    "frags" => [
      "pl|go|java|ps1|cmd|bat|sh|bash"
    ],
    "line" => 10770,
    "names" => [
      "_logical_command_name"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "File::Spec->catfile( \$root, '.env' )",
      "File::Spec->catfile( \$root, '.env.pl' )"
    ],
    "line" => 10783,
    "names" => [
      "_env_file_candidates"
    ],
    "variants" => [
      [
        "File::Spec->catfile( \$root, '.env.pl' )"
      ],
      [
        "File::Spec->catfile( \$root, '.env' )"
      ]
    ]
  },
  {
    "frags" => [
      "abs_path",
      "File::Spec->canonpath"
    ],
    "line" => 10798,
    "names" => [
      "_path_identity"
    ],
    "variants" => [
      [
        "File::Spec->canonpath"
      ],
      [
        "abs_path"
      ]
    ]
  },
  {
    "frags" => [
      "_path_identity",
      "index( \$path_id, \$root_id . '/' ) == 0"
    ],
    "line" => 10813,
    "names" => [
      "_same_or_descendant_path"
    ],
    "variants" => [
      [
        "index( \$path_id, \$root_id . '/' ) == 0"
      ],
      [
        "_path_identity"
      ]
    ]
  },
  {
    "frags" => [
      "return undef if !defined \$name || \$name eq ''",
      "return \$ENV{\$name}"
    ],
    "line" => 10829,
    "names" => [
      "_lookup_env_symbol"
    ],
    "variants" => [
      [
        "return \$ENV{\$name}"
      ],
      [
        "return undef if !defined \$name || \$name eq ''"
      ]
    ]
  },
  {
    "frags" => [
      "cwd()",
      "current_project_root",
      "dirname",
      "reverse \@layers"
    ],
    "line" => 10844,
    "names" => [
      "_plain_directory_layers"
    ],
    "variants" => [
      [
        "current_project_root",
        "dirname",
        "reverse \@layers"
      ],
      [
        "cwd()",
        "dirname",
        "reverse \@layers"
      ],
      [
        "cwd()",
        "current_project_root",
        "reverse \@layers"
      ],
      [
        "cwd()",
        "current_project_root",
        "dirname"
      ]
    ]
  },
  {
    "frags" => [
      "_plain_directory_layers",
      "_env_file_candidates"
    ],
    "line" => 10863,
    "names" => [
      "_plain_directory_env_files"
    ],
    "variants" => [
      [
        "_env_file_candidates"
      ],
      [
        "_plain_directory_layers"
      ]
    ]
  },
  {
    "frags" => [
      "runtime_layers",
      "_env_file_candidates"
    ],
    "line" => 10880,
    "names" => [
      "_runtime_layer_env_files"
    ],
    "variants" => [
      [
        "_env_file_candidates"
      ],
      [
        "runtime_layers"
      ]
    ]
  },
  {
    "frags" => [
      "skill_layers",
      "_env_file_candidates",
      "load_files"
    ],
    "line" => 10896,
    "names" => [
      "load_skill_layers"
    ],
    "variants" => [
      [
        "_env_file_candidates",
        "load_files"
      ],
      [
        "skill_layers",
        "load_files"
      ],
      [
        "skill_layers",
        "_env_file_candidates"
      ]
    ]
  },
  {
    "frags" => [
      "Missing paths",
      "_plain_directory_env_files",
      "_runtime_layer_env_files",
      "load_files"
    ],
    "line" => 10914,
    "names" => [
      "load_runtime_layers"
    ],
    "variants" => [
      [
        "_plain_directory_env_files",
        "_runtime_layer_env_files",
        "load_files"
      ],
      [
        "Missing paths",
        "_runtime_layer_env_files",
        "load_files"
      ],
      [
        "Missing paths",
        "_plain_directory_env_files",
        "load_files"
      ],
      [
        "Missing paths",
        "_plain_directory_env_files",
        "_runtime_layer_env_files"
      ]
    ]
  },
  {
    "frags" => [
      "_path_identity",
      "_load_env_pl_file",
      "_load_env_file",
      "return \\\@loaded"
    ],
    "line" => 10934,
    "names" => [
      "load_files"
    ],
    "variants" => [
      [
        "_load_env_pl_file",
        "_load_env_file",
        "return \\\@loaded"
      ],
      [
        "_path_identity",
        "_load_env_file",
        "return \\\@loaded"
      ],
      [
        "_path_identity",
        "_load_env_pl_file",
        "return \\\@loaded"
      ],
      [
        "_path_identity",
        "_load_env_pl_file",
        "_load_env_file"
      ]
    ]
  },
  {
    "frags" => [
      "Missing in_block_comment state",
      "\${\$state}",
      "return '' if \$trimmed =~ /\\A#/;",
      "return '' if \$trimmed =~ /\\A\\/\\//;",
      "if ( \$trimmed =~ /\\A\\/\\*/ )"
    ],
    "line" => 10954,
    "names" => [
      "_strip_env_comments"
    ],
    "variants" => [
      [
        "\${\$state}",
        "return '' if \$trimmed =~ /\\A#/;",
        "return '' if \$trimmed =~ /\\A\\/\\//;",
        "if ( \$trimmed =~ /\\A\\/\\*/ )"
      ],
      [
        "Missing in_block_comment state",
        "return '' if \$trimmed =~ /\\A#/;",
        "return '' if \$trimmed =~ /\\A\\/\\//;",
        "if ( \$trimmed =~ /\\A\\/\\*/ )"
      ],
      [
        "Missing in_block_comment state",
        "\${\$state}",
        "return '' if \$trimmed =~ /\\A\\/\\//;",
        "if ( \$trimmed =~ /\\A\\/\\*/ )"
      ],
      [
        "Missing in_block_comment state",
        "\${\$state}",
        "return '' if \$trimmed =~ /\\A#/;",
        "if ( \$trimmed =~ /\\A\\/\\*/ )"
      ],
      [
        "Missing in_block_comment state",
        "\${\$state}",
        "return '' if \$trimmed =~ /\\A#/;",
        "return '' if \$trimmed =~ /\\A\\/\\//;"
      ]
    ]
  },
  {
    "frags" => [],
    "line" => 10972,
    "names" => [
      "_expand_env_value"
    ],
    "variants" => []
  },
  {
    "frags" => [
      "split /:-/, \$expression, 2",
      "_call_env_function",
      "_lookup_env_symbol",
      "_expand_env_value"
    ],
    "line" => 10987,
    "names" => [
      "_expand_braced_env_expression"
    ],
    "variants" => [
      [
        "_call_env_function",
        "_lookup_env_symbol",
        "_expand_env_value"
      ],
      [
        "split /:-/, \$expression, 2",
        "_lookup_env_symbol",
        "_expand_env_value"
      ],
      [
        "split /:-/, \$expression, 2",
        "_call_env_function",
        "_expand_env_value"
      ],
      [
        "split /:-/, \$expression, 2",
        "_call_env_function",
        "_lookup_env_symbol"
      ]
    ]
  },
  {
    "frags" => [
      "Invalid env function",
      "{\$function}{CODE}",
      "Env function \$function failed"
    ],
    "line" => 11007,
    "names" => [
      "_call_env_function"
    ],
    "variants" => [
      [
        "{\$function}{CODE}",
        "Env function \$function failed"
      ],
      [
        "Invalid env function",
        "Env function \$function failed"
      ],
      [
        "Invalid env function",
        "{\$function}{CODE}"
      ]
    ]
  },
  {
    "frags" => [
      "_strip_env_comments",
      "Invalid env line",
      "Invalid env key",
      "_expand_env_value",
      "Unterminated block comment"
    ],
    "line" => 11025,
    "names" => [
      "_load_env_file"
    ],
    "variants" => [
      [
        "Invalid env line",
        "Invalid env key",
        "_expand_env_value",
        "Unterminated block comment"
      ],
      [
        "_strip_env_comments",
        "Invalid env key",
        "_expand_env_value",
        "Unterminated block comment"
      ],
      [
        "_strip_env_comments",
        "Invalid env line",
        "_expand_env_value",
        "Unterminated block comment"
      ],
      [
        "_strip_env_comments",
        "Invalid env line",
        "Invalid env key",
        "Unterminated block comment"
      ],
      [
        "_strip_env_comments",
        "Invalid env line",
        "Invalid env key",
        "_expand_env_value"
      ]
    ]
  },
  {
    "frags" => [
      "delete \$INC{\$file}",
      "require \$file",
      "(?:[A-Za-z_][A-Za-z0-9_]*::)*EnvAudit->record"
    ],
    "line" => 11048,
    "names" => [
      "_load_env_pl_file"
    ],
    "variants" => [
      [
        "require \$file",
        "(?:[A-Za-z_][A-Za-z0-9_]*::)*EnvAudit->record"
      ],
      [
        "delete \$INC{\$file}",
        "(?:[A-Za-z_][A-Za-z0-9_]*::)*EnvAudit->record"
      ],
      [
        "delete \$INC{\$file}",
        "require \$file"
      ]
    ]
  },
  {
    "frags" => [
      "Missing paths registry",
      "paths => \$paths"
    ],
    "line" => 11064,
    "names" => [
      "new"
    ],
    "variants" => [
      [
        "paths => \$paths"
      ],
      [
        "Missing paths registry"
      ]
    ]
  },
  {
    "frags" => [
      "\$_[0]->{paths}"
    ],
    "line" => 11086,
    "names" => [
      "paths"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "ref(\$aliases) ne 'HASH'",
      "\$self->{named_files}{\$name} = \$path"
    ],
    "line" => 11101,
    "names" => [
      "register_named_files"
    ],
    "variants" => [
      [
        "\$self->{named_files}{\$name} = \$path"
      ],
      [
        "ref(\$aliases) ne 'HASH'"
      ]
    ]
  },
  {
    "frags" => [
      "delete \$self->{named_files}{\$name}",
      "delete \$self->{configured_named_files}{\$name}"
    ],
    "line" => 11116,
    "names" => [
      "unregister_named_file"
    ],
    "variants" => [
      [
        "delete \$self->{configured_named_files}{\$name}"
      ],
      [
        "delete \$self->{named_files}{\$name}"
      ]
    ]
  },
  {
    "frags" => [
      "_load_configured_named_files",
      "configured_named_files",
      "named_files"
    ],
    "line" => 11131,
    "names" => [
      "named_files"
    ],
    "variants" => [
      [
        "configured_named_files",
        "named_files"
      ],
      [
        "named_files"
      ],
      []
    ]
  },
  {
    "frags" => [
      "prompt_log",
      "collector_log",
      "dashboard_log",
      "global_config",
      "dashboard_index",
      "auth_log",
      "web_pid",
      "web_state"
    ],
    "line" => 11148,
    "names" => [
      "all_file_aliases"
    ],
    "variants" => [
      [
        "collector_log",
        "dashboard_log",
        "global_config",
        "dashboard_index",
        "auth_log",
        "web_pid",
        "web_state"
      ],
      [
        "prompt_log",
        "dashboard_log",
        "global_config",
        "dashboard_index",
        "auth_log",
        "web_pid",
        "web_state"
      ],
      [
        "prompt_log",
        "collector_log",
        "global_config",
        "dashboard_index",
        "auth_log",
        "web_pid",
        "web_state"
      ],
      [
        "prompt_log",
        "collector_log",
        "dashboard_log",
        "dashboard_index",
        "auth_log",
        "web_pid",
        "web_state"
      ],
      [
        "prompt_log",
        "collector_log",
        "dashboard_log",
        "global_config",
        "auth_log",
        "web_pid",
        "web_state"
      ],
      [
        "prompt_log",
        "collector_log",
        "dashboard_log",
        "global_config",
        "dashboard_index",
        "web_pid",
        "web_state"
      ],
      [
        "prompt_log",
        "collector_log",
        "dashboard_log",
        "global_config",
        "dashboard_index",
        "auth_log",
        "web_state"
      ],
      [
        "prompt_log",
        "collector_log",
        "dashboard_log",
        "global_config",
        "dashboard_index",
        "auth_log",
        "web_pid"
      ]
    ]
  },
  {
    "frags" => [
      "all_file_aliases",
      "named_files",
      "return \\%all"
    ],
    "line" => 11179,
    "names" => [
      "all_files"
    ],
    "variants" => [
      [
        "named_files",
        "return \\%all"
      ],
      [
        "all_file_aliases",
        "return \\%all"
      ],
      [
        "all_file_aliases",
        "named_files"
      ]
    ]
  },
  {
    "frags" => [
      "grep { defined && \$_ ne '' } \@terms",
      "paths->cwd",
      "locate_files_under"
    ],
    "line" => 11197,
    "names" => [
      "locate_files"
    ],
    "variants" => [
      [
        "paths->cwd",
        "locate_files_under"
      ],
      [
        "grep { defined && \$_ ne '' } \@terms",
        "locate_files_under"
      ],
      [
        "grep { defined && \$_ ne '' } \@terms",
        "paths->cwd"
      ]
    ]
  },
  {
    "frags" => [
      "File::Find::find",
      "\$name !~ /\\Q\$term\\E/i",
      "\$path !~ /\\Q\$term\\E/i",
      "return grep { !\$seen{\$_}++ } sort \@found"
    ],
    "line" => 11214,
    "names" => [
      "locate_files_under"
    ],
    "variants" => [
      [
        "\$name !~ /\\Q\$term\\E/i",
        "\$path !~ /\\Q\$term\\E/i",
        "return grep { !\$seen{\$_}++ } sort \@found"
      ],
      [
        "File::Find::find",
        "\$path !~ /\\Q\$term\\E/i",
        "return grep { !\$seen{\$_}++ } sort \@found"
      ],
      [
        "File::Find::find",
        "\$name !~ /\\Q\$term\\E/i",
        "return grep { !\$seen{\$_}++ } sort \@found"
      ],
      [
        "File::Find::find",
        "\$name !~ /\\Q\$term\\E/i",
        "\$path !~ /\\Q\$term\\E/i"
      ]
    ]
  },
  {
    "frags" => [
      "(?:[A-Za-z_][A-Za-z0-9_]*::)*Config->new",
      "configured_named_files",
      "file_aliases"
    ],
    "line" => 11231,
    "names" => [
      "_load_configured_named_files"
    ],
    "variants" => [
      [
        "configured_named_files",
        "file_aliases"
      ],
      [
        "(?:[A-Za-z_][A-Za-z0-9_]*::)*Config->new",
        "file_aliases"
      ],
      [
        "(?:[A-Za-z_][A-Za-z0-9_]*::)*Config->new",
        "configured_named_files"
      ]
    ]
  },
  {
    "frags" => [
      "file_name_is_absolute",
      "\$self->can(\$name)",
      "Unknown file name"
    ],
    "line" => 11247,
    "names" => [
      "resolve_file"
    ],
    "variants" => [
      [
        "\$self->can(\$name)",
        "Unknown file name"
      ],
      [
        "file_name_is_absolute",
        "Unknown file name"
      ],
      [
        "file_name_is_absolute",
        "\$self->can(\$name)"
      ]
    ]
  },
  {
    "frags" => [
      "resolve_file",
      "Unable to read",
      "local \$/"
    ],
    "line" => 11262,
    "names" => [
      "read"
    ],
    "variants" => [
      [
        "Unable to read",
        "local \$/"
      ],
      [
        "resolve_file",
        "local \$/"
      ],
      [
        "resolve_file",
        "Unable to read"
      ]
    ]
  },
  {
    "frags" => [
      "resolve_file",
      "secure_file_permissions"
    ],
    "line" => 11278,
    "names" => [
      "write",
      "append",
      "touch"
    ],
    "variants" => [
      [
        "secure_file_permissions"
      ],
      [
        "resolve_file"
      ]
    ]
  },
  {
    "frags" => [
      "resolve_file",
      "unlink \$file if -e \$file"
    ],
    "line" => 11296,
    "names" => [
      "remove"
    ],
    "variants" => [
      [
        "unlink \$file if -e \$file"
      ],
      [
        "resolve_file"
      ]
    ]
  },
  {
    "frags" => [
      "my (\$self) = \@_; return File::Spec->catfile(\$self->paths->foo_dir, 'bar.txt');"
    ],
    "line" => 11311,
    "names" => [
      "some_sub"
    ],
    "variants" => [
      []
    ]
  },
  {
    "frags" => [
      "print STDERR \$message",
      "return 2"
    ],
    "line" => 11326,
    "names" => [
      "_usage_error"
    ],
    "variants" => [
      [
        "return 2"
      ],
      [
        "print STDERR \$message"
      ]
    ]
  },
  {
    "frags" => [
      "DEVELOPER_DASHBOARD_PROGRESS",
      "install_progress_tasks",
      "dashboard skills install progress"
    ],
    "line" => 11341,
    "names" => [
      "_skills_install_progress"
    ],
    "variants" => [
      [
        "install_progress_tasks",
        "dashboard skills install progress"
      ],
      [
        "DEVELOPER_DASHBOARD_PROGRESS",
        "dashboard skills install progress"
      ],
      [
        "DEVELOPER_DASHBOARD_PROGRESS",
        "install_progress_tasks"
      ]
    ]
  },
  {
    "frags" => [
      "DEVELOPER_DASHBOARD_PROGRESS",
      "install_progress_tasks_for_sources",
      "return if !\@sources"
    ],
    "line" => 11359,
    "names" => [
      "_skills_install_progress_for_sources"
    ],
    "variants" => [
      [
        "install_progress_tasks_for_sources",
        "return if !\@sources"
      ],
      [
        "DEVELOPER_DASHBOARD_PROGRESS",
        "return if !\@sources"
      ],
      [
        "DEVELOPER_DASHBOARD_PROGRESS",
        "install_progress_tasks_for_sources"
      ]
    ]
  },
  {
    "frags" => [
      "return () if ref(\$result) ne 'HASH'",
      "operations",
      "results",
      "repo_name"
    ],
    "line" => 11377,
    "names" => [
      "_install_result_rows"
    ],
    "variants" => [
      [
        "operations",
        "results",
        "repo_name"
      ],
      [
        "return () if ref(\$result) ne 'HASH'",
        "results",
        "repo_name"
      ],
      [
        "return () if ref(\$result) ne 'HASH'",
        "operations",
        "repo_name"
      ],
      [
        "return () if ref(\$result) ne 'HASH'",
        "operations",
        "results"
      ]
    ]
  },
  {
    "frags" => [
      "\\e\\[[0-9;]*m",
      "return \$value"
    ],
    "line" => 11393,
    "names" => [
      "_plain_text"
    ],
    "variants" => [
      [
        "return \$value"
      ],
      [
        "\\e\\[[0-9;]*m"
      ]
    ]
  },
  {
    "frags" => [
      "enabled",
      "disabled"
    ],
    "line" => 11407,
    "names" => [
      "_enabled_text"
    ],
    "variants" => [
      [
        "disabled"
      ],
      [
        "enabled"
      ]
    ]
  },
  {
    "frags" => [
      "yes",
      "no"
    ],
    "line" => 11423,
    "names" => [
      "_boolean_text"
    ],
    "variants" => [
      [
        "no"
      ],
      [
        "yes"
      ]
    ]
  },
  {
    "frags" => [
      "_plain_text",
      "join '  ', \@cells"
    ],
    "line" => 11439,
    "names" => [
      "_format_row"
    ],
    "variants" => [
      [
        "join '  ', \@cells"
      ],
      [
        "_plain_text"
      ]
    ]
  },
  {
    "frags" => [
      "_plain_text",
      "_format_row",
      "'-' x \$widths"
    ],
    "line" => 11454,
    "names" => [
      "_render_table"
    ],
    "variants" => [
      [
        "_format_row",
        "'-' x \$widths"
      ],
      [
        "_plain_text",
        "'-' x \$widths"
      ],
      [
        "_plain_text",
        "_format_row"
      ]
    ]
  },
  {
    "frags" => [
      "No update",
      "_install_result_rows",
      "_render_table"
    ],
    "line" => 11471,
    "names" => [
      "_skills_install_summary_table"
    ],
    "variants" => [
      [
        "_install_result_rows",
        "_render_table"
      ],
      [
        "No update",
        "_render_table"
      ],
      [
        "No update",
        "_install_result_rows"
      ]
    ]
  },
  {
    "frags" => [
      "cli_commands_count",
      "docker_services_count",
      "_enabled_text",
      "_render_table"
    ],
    "line" => 11488,
    "names" => [
      "_skills_table"
    ],
    "variants" => [
      [
        "docker_services_count",
        "_enabled_text",
        "_render_table"
      ],
      [
        "cli_commands_count",
        "_enabled_text",
        "_render_table"
      ],
      [
        "cli_commands_count",
        "docker_services_count",
        "_render_table"
      ],
      [
        "cli_commands_count",
        "docker_services_count",
        "_enabled_text"
      ]
    ]
  },
  {
    "frags" => [
      "CLI Commands",
      "Docker Services",
      "Collectors",
      "_boolean_text",
      "_render_table"
    ],
    "line" => 11506,
    "names" => [
      "_usage_table"
    ],
    "variants" => [
      [
        "Docker Services",
        "Collectors",
        "_boolean_text",
        "_render_table"
      ],
      [
        "CLI Commands",
        "Collectors",
        "_boolean_text",
        "_render_table"
      ],
      [
        "CLI Commands",
        "Docker Services",
        "_boolean_text",
        "_render_table"
      ],
      [
        "CLI Commands",
        "Docker Services",
        "Collectors",
        "_render_table"
      ],
      [
        "CLI Commands",
        "Docker Services",
        "Collectors",
        "_boolean_text"
      ]
    ]
  },
  {
    "frags" => [
      "Unknown skills action",
      "skills install",
      "skills uninstall",
      "skills usage",
      "Foo::SkillManager->new"
    ],
    "line" => 11526,
    "names" => [
      "run_skills_command"
    ],
    "variants" => [
      [
        "skills install",
        "skills uninstall",
        "skills usage",
        "Foo::SkillManager->new"
      ],
      [
        "Unknown skills action",
        "skills uninstall",
        "skills usage",
        "Foo::SkillManager->new"
      ],
      [
        "Unknown skills action",
        "skills install",
        "skills usage",
        "Foo::SkillManager->new"
      ],
      [
        "Unknown skills action",
        "skills install",
        "skills uninstall",
        "Foo::SkillManager->new"
      ],
      [
        "Unknown skills action",
        "skills install",
        "skills uninstall",
        "skills usage"
      ]
    ]
  },
  {
    "frags" => [
      "encode_payload",
      "uri_escape",
      "raw => \$raw"
    ],
    "line" => 11552,
    "names" => [
      "zip"
    ],
    "variants" => [
      [
        "uri_escape",
        "raw => \$raw"
      ],
      [
        "encode_payload",
        "raw => \$raw"
      ],
      [
        "encode_payload",
        "uri_escape"
      ]
    ]
  },
  {
    "frags" => [
      "decode_payload",
      "return if !defined \$token"
    ],
    "line" => 11567,
    "names" => [
      "unzip"
    ],
    "variants" => [
      [
        "return if !defined \$token"
      ],
      [
        "decode_payload"
      ]
    ]
  },
  {
    "frags" => [
      "\\\\\\\\",
      "\\\\'"
    ],
    "line" => 11581,
    "names" => [
      "_js_single_quote"
    ],
    "variants" => [
      [
        "\\\\'"
      ],
      [
        "\\\\\\\\"
      ]
    ]
  },
  {
    "frags" => [
      "file is required",
      "file must be relative",
      "invalid parent traversal",
      "invalid characters"
    ],
    "line" => 11595,
    "names" => [
      "_validate_saved_ajax_file"
    ],
    "variants" => [
      [
        "file must be relative",
        "invalid parent traversal",
        "invalid characters"
      ],
      [
        "file is required",
        "invalid parent traversal",
        "invalid characters"
      ],
      [
        "file is required",
        "file must be relative",
        "invalid characters"
      ],
      [
        "file is required",
        "file must be relative",
        "invalid parent traversal"
      ]
    ]
  },
  {
    "frags" => [
      "runtime_root is required",
      "dashboards', 'ajax'",
      "_validate_saved_ajax_file"
    ],
    "line" => 11611,
    "names" => [
      "saved_ajax_file_path"
    ],
    "variants" => [
      [
        "dashboards', 'ajax'",
        "_validate_saved_ajax_file"
      ],
      [
        "runtime_root is required",
        "_validate_saved_ajax_file"
      ],
      [
        "runtime_root is required",
        "dashboards', 'ajax'"
      ]
    ]
  },
  {
    "frags" => [
      "saved_ajax_file_path",
      "Unable to read"
    ],
    "line" => 11627,
    "names" => [
      "load_saved_ajax_code"
    ],
    "variants" => [
      [
        "Unable to read"
      ],
      [
        "saved_ajax_file_path"
      ]
    ]
  },
  {
    "frags" => [
      "/ajax/%s?type=%s",
      "singleton",
      "_validate_saved_ajax_file"
    ],
    "line" => 11642,
    "names" => [
      "_saved_ajax_url"
    ],
    "variants" => [
      [
        "singleton",
        "_validate_saved_ajax_file"
      ],
      [
        "/ajax/%s?type=%s",
        "_validate_saved_ajax_file"
      ],
      [
        "/ajax/%s?type=%s",
        "singleton"
      ]
    ]
  },
  {
    "frags" => [
      "saved_ajax_file_path",
      "make_path",
      "chmod 0700",
      "_saved_ajax_url"
    ],
    "line" => 11658,
    "names" => [
      "_saved_ajax_url_and_store"
    ],
    "variants" => [
      [
        "make_path",
        "chmod 0700",
        "_saved_ajax_url"
      ],
      [
        "saved_ajax_file_path",
        "chmod 0700",
        "_saved_ajax_url"
      ],
      [
        "saved_ajax_file_path",
        "make_path",
        "_saved_ajax_url"
      ],
      [
        "saved_ajax_file_path",
        "make_path",
        "chmod 0700"
      ]
    ]
  },
  {
    "frags" => [
      "token=%s&type=%s",
      "singleton",
      "Click Here",
      "zip(\$code)"
    ],
    "line" => 11676,
    "names" => [
      "acmdx"
    ],
    "variants" => [
      [
        "singleton",
        "Click Here",
        "zip(\$code)"
      ],
      [
        "token=%s&type=%s",
        "Click Here",
        "zip(\$code)"
      ],
      [
        "token=%s&type=%s",
        "singleton",
        "zip(\$code)"
      ],
      [
        "token=%s&type=%s",
        "singleton",
        "Click Here"
      ]
    ]
  },
  {
    "frags" => [
      "jvar is required",
      "saved bookmark Ajax",
      "dashboard_ajax_singleton_cleanup",
      "set_chain_value"
    ],
    "line" => 11693,
    "names" => [
      "Ajax"
    ],
    "variants" => [
      [
        "saved bookmark Ajax",
        "dashboard_ajax_singleton_cleanup",
        "set_chain_value"
      ],
      [
        "jvar is required",
        "dashboard_ajax_singleton_cleanup",
        "set_chain_value"
      ],
      [
        "jvar is required",
        "saved bookmark Ajax",
        "set_chain_value"
      ],
      [
        "jvar is required",
        "saved bookmark Ajax",
        "dashboard_ajax_singleton_cleanup"
      ]
    ]
  },
  {
    "frags" => [
      "printf '%s'",
      "base64 -d | gunzip",
      "quotemeta"
    ],
    "line" => 11713,
    "names" => [
      "__cmdx"
    ],
    "variants" => [
      [
        "base64 -d | gunzip",
        "quotemeta"
      ],
      [
        "printf '%s'",
        "quotemeta"
      ],
      [
        "printf '%s'",
        "base64 -d | gunzip"
      ]
    ]
  },
  {
    "frags" => [
      "\$type eq 'perl' ? '-e' : '-c'",
      "__cmdx"
    ],
    "line" => 11729,
    "names" => [
      "_cmdx"
    ],
    "variants" => [
      [
        "__cmdx"
      ],
      [
        "\$type eq 'perl' ? '-e' : '-c'"
      ]
    ]
  },
  {
    "frags" => [
      "__cmdx",
      "return ( __cmdx"
    ],
    "line" => 11744,
    "names" => [
      "_cmdp"
    ],
    "variants" => [
      [],
      [
        "__cmdx"
      ]
    ]
  },
  {
    "frags" => [
      "Ticket args must be an array reference",
      "Please specify a ticket name\\n",
      "\$ticket = \$args{env_ticket} if !defined \$ticket || \$ticket eq ''"
    ],
    "line" => 11759,
    "names" => [
      "resolve_ticket_request"
    ],
    "variants" => [
      [
        "Please specify a ticket name\\n",
        "\$ticket = \$args{env_ticket} if !defined \$ticket || \$ticket eq ''"
      ],
      [
        "Ticket args must be an array reference",
        "\$ticket = \$args{env_ticket} if !defined \$ticket || \$ticket eq ''"
      ],
      [
        "Ticket args must be an array reference",
        "Please specify a ticket name\\n"
      ]
    ]
  },
  {
    "frags" => [
      "Ticket name is required\\n",
      "TICKET_REF",
      "OB => \"origin/\$ticket\""
    ],
    "line" => 11776,
    "names" => [
      "ticket_environment"
    ],
    "variants" => [
      [
        "TICKET_REF",
        "OB => \"origin/\$ticket\""
      ],
      [
        "Ticket name is required\\n",
        "OB => \"origin/\$ticket\""
      ],
      [
        "Ticket name is required\\n",
        "TICKET_REF"
      ]
    ]
  },
  {
    "frags" => [
      "tmux args must be an array reference",
      "system 'tmux', \@{\$argv}",
      "stdout => \$stdout",
      "exit_code => \$exit_code"
    ],
    "line" => 11792,
    "names" => [
      "tmux_command"
    ],
    "variants" => [
      [
        "system 'tmux', \@{\$argv}",
        "stdout => \$stdout",
        "exit_code => \$exit_code"
      ],
      [
        "tmux args must be an array reference",
        "stdout => \$stdout",
        "exit_code => \$exit_code"
      ],
      [
        "tmux args must be an array reference",
        "system 'tmux', \@{\$argv}",
        "exit_code => \$exit_code"
      ],
      [
        "tmux args must be an array reference",
        "system 'tmux', \@{\$argv}",
        "stdout => \$stdout"
      ]
    ]
  },
  {
    "frags" => [
      "Missing session name",
      "has-session",
      "return 1 if \$result->{exit_code} == 0",
      "return 0 if \$result->{exit_code} == 1",
      "Unable to inspect tmux session"
    ],
    "line" => 11810,
    "names" => [
      "session_exists"
    ],
    "variants" => [
      [
        "has-session",
        "return 1 if \$result->{exit_code} == 0",
        "return 0 if \$result->{exit_code} == 1",
        "Unable to inspect tmux session"
      ],
      [
        "Missing session name",
        "return 1 if \$result->{exit_code} == 0",
        "return 0 if \$result->{exit_code} == 1",
        "Unable to inspect tmux session"
      ],
      [
        "Missing session name",
        "has-session",
        "return 0 if \$result->{exit_code} == 1",
        "Unable to inspect tmux session"
      ],
      [
        "Missing session name",
        "has-session",
        "return 1 if \$result->{exit_code} == 0",
        "Unable to inspect tmux session"
      ],
      [
        "Missing session name",
        "has-session",
        "return 1 if \$result->{exit_code} == 0",
        "return 0 if \$result->{exit_code} == 1"
      ]
    ]
  },
  {
    "frags" => [
      "resolve_ticket_request",
      "ticket_environment",
      "session_exists",
      "new-session",
      "attach-session"
    ],
    "line" => 11830,
    "names" => [
      "build_ticket_plan"
    ],
    "variants" => [
      [
        "ticket_environment",
        "session_exists",
        "new-session",
        "attach-session"
      ],
      [
        "resolve_ticket_request",
        "session_exists",
        "new-session",
        "attach-session"
      ],
      [
        "resolve_ticket_request",
        "ticket_environment",
        "new-session",
        "attach-session"
      ],
      [
        "resolve_ticket_request",
        "ticket_environment",
        "session_exists",
        "attach-session"
      ],
      [
        "resolve_ticket_request",
        "ticket_environment",
        "session_exists",
        "new-session"
      ]
    ]
  },
  {
    "frags" => [
      "build_ticket_plan",
      "Unable to create tmux ticket session",
      "Unable to attach tmux ticket session"
    ],
    "line" => 11850,
    "names" => [
      "run_ticket_command"
    ],
    "variants" => [
      [
        "Unable to create tmux ticket session",
        "Unable to attach tmux ticket session"
      ],
      [
        "build_ticket_plan",
        "Unable to attach tmux ticket session"
      ],
      [
        "build_ticket_plan",
        "Unable to create tmux ticket session"
      ]
    ]
  }
]
;

for my $case (grep { $_->{line} != 10548 } @{$cases}) {
    my $label = "line $case->{line}";
    for my $name (@{$case->{names}}) {
        my $hit = compile_sub($name, $case->{frags});
        ok($hit && $hit->{op}, "$label $name matches") or diag("no match");
        is($hit->{name}, $name, "$label $name keeps its short name") if $hit;
        if ($name ne q{some_sub}) {
            my $miss = compile_sub(q{zz_unrelated_name}, $case->{frags});
            my $miss_op = $miss ? $miss->{op} : q{};
            isnt($miss_op, $hit ? $hit->{op} : q{none}, "$label unrelated name does not select the same op");
        }
        my $n = 0;
        for my $variant (@{$case->{variants}}) {
            $n++;
            my $near = compile_sub($name, $variant);
            my $near_op = $near ? $near->{op} : '';
            isnt($near_op, $hit ? $hit->{op} : 'none', "$label $name variant $n lacking one fragment is rejected");
        }
    }
}

done_testing;
