use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::CodeUnitCompiler;

=pod

=head1 NAME

t/cov_cucc_custom_ops.t - source-shape matcher coverage for the transform-sub recognizers

=head1 DESCRIPTION

C<PAX::CodeUnitCompiler::_compile_simple_transform_sub_from_source> recognizes
many framework-style subs by loose regexes against the sub body and emits a
named op for each. This file drives every one of those recognizers with a
synthetic sub body that satisfies each regex (the op must be emitted), with
bodies that satisfy only a prefix of the regexes (no such op may be emitted),
with a different sub name, and with a different package tail where the
recognizer is package-scoped.

=head1 WHY IT EXISTS

Each recognizer is a chain of C<&&> conditions; the compiler's own coverage
requires both outcomes of every term. The table below lists, per recognizer,
the sub names it accepts and one literal snippet per body regex, so the match
and every near-miss are exercised without depending on any external source tree.

=cut

# The recognizer table: line (in the compiler source when generated), op, names, package tail, snippets, skip.
my $table = 
[
  {
    "line" => 5992,
    "names" => [
      "read_status"
    ],
    "op" => "collector_read_status",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_collector_file_candidates",
      "eval { json_decode(\$raw) }",
      "status.json"
    ]
  },
  {
    "line" => 6008,
    "names" => [
      "_first_existing_text_file"
    ],
    "op" => "collector_first_existing_text_file",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_collector_file_candidates",
      "_slurp",
      "return ''"
    ]
  },
  {
    "line" => 6025,
    "names" => [
      "read_output"
    ],
    "op" => "collector_read_output",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_first_existing_text_file",
      "last_run",
      "combined"
    ]
  },
  {
    "line" => 6041,
    "names" => [
      "collector_exists"
    ],
    "op" => "collector_exists",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "collectors_roots",
      "Missing collector name",
      "File::Spec->catdir"
    ]
  },
  {
    "line" => 6056,
    "names" => [
      "_log_payload_present"
    ],
    "op" => "collector_log_payload_present",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "stdout stderr combined last_run",
      "last_exit_code last_run last_completed_at last_started_at timed_out"
    ]
  },
  {
    "line" => 6070,
    "names" => [
      "_format_log_entry"
    ],
    "op" => "collector_format_log_entry",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "=== collector",
      "[stdout]",
      "[stderr]",
      "_with_trailing_newline"
    ]
  },
  {
    "line" => 6087,
    "names" => [
      "append_log_entry"
    ],
    "op" => "collector_append_log_entry",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_format_log_entry",
      "Unable to append",
      "secure_file_permissions"
    ]
  },
  {
    "line" => 6104,
    "names" => [
      "write_result"
    ],
    "op" => "collector_write_result",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "append_log_entry",
      "updated_at_epoch => time",
      "last_success_at",
      "timed_out"
    ]
  },
  {
    "line" => 6126,
    "names" => [
      "write_status"
    ],
    "op" => "collector_write_status",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "read_status",
      "updated_at_epoch => time",
      "_atomic_write_json"
    ]
  },
  {
    "line" => 6144,
    "names" => [
      "_render_latest_log_entry"
    ],
    "op" => "collector_render_latest_log_entry",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "collector_exists",
      "_log_payload_present",
      "latest state snapshot"
    ]
  },
  {
    "line" => 6164,
    "names" => [
      "read_log"
    ],
    "op" => "collector_read_log",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_collector_file_candidates",
      "_render_latest_log_entry",
      "Missing collector name"
    ]
  },
  {
    "line" => 6182,
    "names" => [
      "inspect_collector"
    ],
    "op" => "collector_inspect",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "read_job",
      "read_output",
      "read_status"
    ]
  },
  {
    "line" => 6200,
    "names" => [
      "list_collectors"
    ],
    "op" => "collector_list",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "collectors_roots",
      "readdir",
      "read_status",
      "sort { \$a->{name} cmp \$b->{name} }"
    ]
  },
  {
    "line" => 6217,
    "names" => [
      "_normalize_rotation"
    ],
    "op" => "collector_normalize_rotation",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "collector rotation for",
      "must be a hash reference",
      "months"
    ]
  },
  {
    "line" => 6232,
    "names" => [
      "_rotation_retention_seconds"
    ],
    "op" => "collector_rotation_retention_seconds",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "minutes",
      "months",
      "seconds_per_unit"
    ]
  },
  {
    "line" => 6247,
    "names" => [
      "_split_log_entries"
    ],
    "op" => "collector_split_log_entries",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "split /(?=^=== collector )/m"
    ]
  },
  {
    "line" => 6260,
    "names" => [
      "_entry_timestamp_epoch"
    ],
    "op" => "collector_entry_timestamp_epoch",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "Unable to parse collector log timestamp",
      "_iso8601_to_epoch",
      "=== collector "
    ]
  },
  {
    "line" => 6276,
    "names" => [
      "_trim_log_by_age"
    ],
    "op" => "collector_trim_log_by_age",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_split_log_entries",
      "_entry_timestamp_epoch",
      "return \$text if \$text eq ''"
    ]
  },
  {
    "line" => 6293,
    "names" => [
      "_trim_log_by_lines"
    ],
    "op" => "collector_trim_log_by_lines",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "split /\\n/, \$text, -1",
      "return \$text if \@parts <= \$lines"
    ]
  },
  {
    "line" => 6307,
    "names" => [
      "_apply_log_rotation"
    ],
    "op" => "collector_apply_log_rotation",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_rotation_retention_seconds",
      "_trim_log_by_age",
      "_trim_log_by_lines"
    ]
  },
  {
    "line" => 6325,
    "names" => [
      "rotate_log"
    ],
    "op" => "collector_rotate_log",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_normalize_rotation",
      "_apply_log_rotation",
      "collector-log-rotation"
    ]
  },
  {
    "line" => 6345,
    "names" => [
      "new"
    ],
    "op" => "config_new",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "Missing file registry",
      "Missing path registry",
      "repo_root"
    ]
  },
  {
    "line" => 6361,
    "names" => [
      "_global_config_file"
    ],
    "op" => "config_global_config_file",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "config_root",
      "config.json"
    ]
  },
  {
    "line" => 6376,
    "names" => [
      "_global_config_files"
    ],
    "op" => "config_global_config_files",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "config_roots",
      "map { File::Spec->catfile"
    ]
  },
  {
    "line" => 6391,
    "names" => [
      "_merge_named_hash_item"
    ],
    "op" => "config_merge_named_hash_item",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "ref(\$left) ne 'HASH'",
      "_merge_hashes"
    ]
  },
  {
    "line" => 6407,
    "names" => [
      "_merge_named_hash_array"
    ],
    "op" => "config_merge_named_hash_array",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "%positions",
      "_merge_named_hash_item",
      "identity_key"
    ]
  },
  {
    "line" => 6424,
    "names" => [
      "_merge_hashes"
    ],
    "op" => "config_merge_hashes",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "collectors",
      "providers",
      "_merge_named_hash_array"
    ]
  },
  {
    "line" => 6441,
    "names" => [
      "load_global"
    ],
    "op" => "config_load_global",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "reverse \$self->_global_config_files",
      "_skill_config_fragments",
      "_merge_hashes"
    ]
  },
  {
    "line" => 6460,
    "names" => [
      "save_global"
    ],
    "op" => "config_save_global",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_global_config_file",
      "json_encode",
      "secure_file_permissions"
    ]
  },
  {
    "line" => 6477,
    "names" => [
      "_load_writable_global"
    ],
    "op" => "config_load_writable_global",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_global_config_file",
      "json_decode",
      "return {} if !-f \$file"
    ]
  },
  {
    "line" => 6494,
    "names" => [
      "save_global_defaults"
    ],
    "op" => "config_save_global_defaults",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_load_writable_global",
      "_merge_hashes",
      "save_global"
    ]
  },
  {
    "line" => 6513,
    "names" => [
      "ensure_global_file"
    ],
    "op" => "config_ensure_global_file",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "return \$file if -e \$file",
      "save_global( {} )"
    ]
  },
  {
    "line" => 6530,
    "names" => [
      "load_repo"
    ],
    "op" => "config_load_repo",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "current_project_root",
      "json_decode"
    ]
  },
  {
    "line" => 6545,
    "names" => [
      "merged"
    ],
    "op" => "config_merged",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "load_global",
      "load_repo",
      "_merge_hashes"
    ]
  },
  {
    "line" => 6564,
    "names" => [
      "_builtin_collectors"
    ],
    "op" => "config_builtin_collectors",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "housekeeper",
      "PathRegistry->new",
      "workspace_roots"
    ]
  },
  {
    "line" => 6580,
    "names" => [
      "_skill_config_entries"
    ],
    "op" => "config_skill_config_entries",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "SkillDispatcher->new",
      "installed_skill_roots",
      "get_skill_config"
    ]
  },
  {
    "line" => 6597,
    "names" => [
      "_skill_config_fragments"
    ],
    "op" => "config_skill_config_fragments",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_skill_config_entries",
      "config_fragment"
    ]
  },
  {
    "line" => 6613,
    "names" => [
      "_skill_collectors"
    ],
    "op" => "config_skill_collectors",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_skill_config_entries",
      "qualified_name",
      "skill_root"
    ]
  },
  {
    "line" => 6630,
    "names" => [
      "collectors"
    ],
    "op" => "config_collectors",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_builtin_collectors",
      "_skill_collectors",
      "DEVELOPER_DASHBOARD_CHECKERS"
    ]
  },
  {
    "line" => 6650,
    "names" => [
      "_normalize_home_path"
    ],
    "op" => "config_normalize_home_path",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "\$HOME",
      "home_prefix"
    ]
  },
  {
    "line" => 6665,
    "names" => [
      "_expand_config_path"
    ],
    "op" => "config_expand_config_path",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "\$HOME",
      " return \$home",
      "path =~ /^~"
    ]
  },
  {
    "line" => 6681,
    "names" => [
      "_expand_path_aliases"
    ],
    "op" => "config_expand_path_aliases",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_expand_config_path",
      "%expanded"
    ]
  },
  {
    "line" => 6697,
    "names" => [
      "path_aliases"
    ],
    "op" => "config_path_aliases",
    "pkgcheck" => 1,
    "skip" => [
      2
    ],
    "tail" => "",
    "terms" => [
      "merged",
      "_expand_path_aliases",
      "path_aliases"
    ]
  },
  {
    "line" => 6716,
    "names" => [
      "file_aliases"
    ],
    "op" => "config_path_aliases",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "merged",
      "_expand_path_aliases",
      "file_aliases"
    ]
  },
  {
    "line" => 6735,
    "names" => [
      "global_path_aliases"
    ],
    "op" => "config_global_aliases",
    "pkgcheck" => 1,
    "skip" => [
      2
    ],
    "tail" => "",
    "terms" => [
      "load_global",
      "_expand_path_aliases",
      "path_aliases"
    ]
  },
  {
    "line" => 6754,
    "names" => [
      "global_file_aliases"
    ],
    "op" => "config_global_aliases",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "load_global",
      "_expand_path_aliases",
      "file_aliases"
    ]
  },
  {
    "line" => 6773,
    "names" => [
      "web_workers"
    ],
    "op" => "config_web_workers",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "workers",
      "return 1 if !defined \$workers"
    ]
  },
  {
    "line" => 6789,
    "names" => [
      "_normalize_ssl_subject_alt_names"
    ],
    "op" => "config_normalize_ssl_subject_alt_names",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "ref(\$names) ne 'ARRAY'",
      "push \@normalized"
    ]
  },
  {
    "line" => 6804,
    "names" => [
      "save_global_web_workers"
    ],
    "op" => "config_save_global_web_workers",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "Worker count must be a positive integer",
      "_load_writable_global",
      "save_global"
    ]
  },
  {
    "line" => 6822,
    "names" => [
      "web_settings"
    ],
    "op" => "config_web_settings",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "ssl_subject_alt_names",
      "no_editor",
      "no_indicators"
    ]
  },
  {
    "line" => 6840,
    "names" => [
      "save_global_web_settings"
    ],
    "op" => "config_save_global_web_settings",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "Host cannot be empty",
      "Port must be numeric",
      "Worker count must be numeric",
      "ssl_subject_alt_names"
    ]
  },
  {
    "line" => 6860,
    "names" => [
      "save_global_path_alias",
      "save_global_file_alias"
    ],
    "op" => "config_save_global_alias",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "Missing x alias name",
      "_normalize_home_path",
      "_expand_config_path"
    ]
  },
  {
    "line" => 6883,
    "names" => [
      "remove_global_path_alias",
      "remove_global_file_alias"
    ],
    "op" => "config_remove_global_alias",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "removed",
      "delete \$cfg",
      "save_global"
    ]
  },
  {
    "line" => 6904,
    "names" => [
      "docker_config"
    ],
    "op" => "config_docker_config",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "merged",
      "cfg->{docker}"
    ]
  },
  {
    "line" => 6920,
    "names" => [
      "providers"
    ],
    "op" => "config_providers",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "cfg->{providers}",
      "push \@providers"
    ]
  },
  {
    "line" => 6936,
    "names" => [
      "new"
    ],
    "op" => "skill_dispatcher_new",
    "pkgcheck" => 1,
    "tail" => "SkillDispatcher",
    "terms" => [
      "SkillManager->new",
      "manager => \$manager"
    ]
  },
  {
    "line" => 6952,
    "names" => [
      "_arrayref_or_empty"
    ],
    "op" => "skill_dispatcher_arrayref_or_empty",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "ref(\$value) eq 'ARRAY'",
      "my \@empty"
    ]
  },
  {
    "line" => 6967,
    "names" => [
      "_hashref_or_empty"
    ],
    "op" => "skill_dispatcher_hashref_or_empty",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "ref(\$value) eq 'HASH'",
      "my %empty"
    ]
  },
  {
    "line" => 6982,
    "names" => [
      "_defined_or_default"
    ],
    "op" => "skill_dispatcher_defined_or_default",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "return defined \$value ? \$value : \$default"
    ]
  },
  {
    "line" => 6996,
    "names" => [
      "_merge_array_items_by_identity"
    ],
    "op" => "skill_dispatcher_merge_array_items_by_identity",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "%positions",
      "_arrayref_or_empty",
      "exists \$positions"
    ]
  },
  {
    "line" => 7013,
    "names" => [
      "_skill_layers"
    ],
    "op" => "skill_dispatcher_skill_layers",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "skill_layers",
      "get_skill_path"
    ]
  },
  {
    "line" => 7028,
    "names" => [
      "_skill_lookup_roots"
    ],
    "op" => "skill_dispatcher_skill_lookup_roots",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "reverse \$self->_skill_layers"
    ]
  },
  {
    "line" => 7043,
    "names" => [
      "_command_root_specs"
    ],
    "op" => "skill_dispatcher_command_root_specs",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "split_index",
      "nested_segments",
      "command_name"
    ]
  },
  {
    "line" => 7059,
    "names" => [
      "_nested_skill_path"
    ],
    "op" => "skill_dispatcher_nested_skill_path",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "push \@parts, 'skills', \$segment",
      "File::Spec->catdir"
    ]
  },
  {
    "line" => 7074,
    "names" => [
      "_page_location"
    ],
    "op" => "skill_dispatcher_page_location",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_skill_lookup_roots",
      "dashboards",
      "return ( \$file, \$skill_path ) if -f \$file"
    ]
  },
  {
    "line" => 7091,
    "names" => [
      "_skill_bookmark_entries"
    ],
    "op" => "skill_dispatcher_skill_bookmark_entries",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_skill_lookup_roots",
      "dashboards",
      "\$entries{\$entry} ||= 1"
    ]
  },
  {
    "line" => 7108,
    "names" => [
      "_skill_nav_route_ids"
    ],
    "op" => "skill_dispatcher_skill_nav_route_ids",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_skill_lookup_roots",
      "dashboards', 'nav'",
      "\$routes{\$entry} ||= 'nav/' . \$entry"
    ]
  },
  {
    "line" => 7125,
    "names" => [
      "_merge_skill_hashes"
    ],
    "op" => "skill_dispatcher_merge_skill_hashes",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "collectors",
      "providers",
      "_merge_array_items_by_identity"
    ]
  },
  {
    "line" => 7142,
    "names" => [
      "get_skill_config"
    ],
    "op" => "skill_dispatcher_get_skill_config",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "config/config.json",
      "decode_json",
      "_merge_skill_hashes"
    ]
  },
  {
    "line" => 7160,
    "names" => [
      "config_fragment"
    ],
    "op" => "skill_dispatcher_config_fragment",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "get_skill_config",
      "'_' . \$skill_name"
    ]
  },
  {
    "line" => 7176,
    "names" => [
      "get_skill_path"
    ],
    "op" => "skill_dispatcher_get_skill_path",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "manager->get_skill_path"
    ]
  },
  {
    "line" => 7190,
    "names" => [
      "_command_spec"
    ],
    "op" => "skill_dispatcher_command_spec",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_command_root_specs",
      "resolve_runnable_file",
      "skill_layers"
    ]
  },
  {
    "line" => 7209,
    "names" => [
      "command_path"
    ],
    "op" => "skill_dispatcher_command_path",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_command_spec",
      "cmd_path"
    ]
  },
  {
    "line" => 7225,
    "names" => [
      "command_spec"
    ],
    "op" => "skill_dispatcher_command_spec_public",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "return \$self->_command_spec"
    ]
  },
  {
    "line" => 7240,
    "names" => [
      "command_hook_paths"
    ],
    "op" => "skill_dispatcher_command_hook_paths",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_command_spec",
      "cli', \"\\\$resolved_command\\xd\"",
      "is_runnable_file"
    ]
  },
  {
    "line" => 7257,
    "names" => [
      "new"
    ],
    "op" => "collector_runner_new",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "Missing collector store",
      "Missing file registry",
      "Missing path registry"
    ]
  },
  {
    "line" => 7273,
    "names" => [
      "run_once"
    ],
    "op" => "collector_runner_run_once",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_collector_source",
      "_run_job",
      "_materialize_indicator_state",
      "write_result"
    ]
  },
  {
    "line" => 7294,
    "names" => [
      "_materialize_indicator_state"
    ],
    "op" => "collector_runner_materialize_indicator_state",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "icon_template",
      "_render_indicator_icon_template"
    ]
  },
  {
    "line" => 7310,
    "names" => [
      "_render_indicator_icon_template"
    ],
    "op" => "collector_runner_render_indicator_icon_template",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_indicator_template_vars",
      "Template->new",
      "process"
    ]
  },
  {
    "line" => 7327,
    "names" => [
      "_indicator_template_vars"
    ],
    "op" => "collector_runner_indicator_template_vars",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "json_decode",
      "collector stdout JSON"
    ]
  },
  {
    "line" => 7342,
    "names" => [
      "_append_error_text"
    ],
    "op" => "collector_runner_append_error_text",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "\$stderr .= \"\\n\"",
      "return \$stderr . \$error . \"\\n\""
    ]
  },
  {
    "line" => 7357,
    "names" => [
      "_collector_source"
    ],
    "op" => "collector_runner_source",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "return ( 'command', \$job->{command} )",
      "missing command or code"
    ]
  },
  {
    "line" => 7372,
    "names" => [
      "_run_job"
    ],
    "op" => "collector_runner_run_job",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "return \$self->_run_command(%args) if \$mode eq 'command'",
      "return \$self->_run_code(%args) if \$mode eq 'code'"
    ]
  },
  {
    "line" => 7389,
    "names" => [
      "start_loop"
    ],
    "op" => "collector_runner_start_loop",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_pidfile",
      "_write_loop_state",
      "_fork_process",
      "_run_loop_child"
    ]
  },
  {
    "line" => 7413,
    "names" => [
      "_fork_process"
    ],
    "op" => "collector_runner_fork_process",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "return fork"
    ]
  },
  {
    "line" => 7427,
    "names" => [
      "_run_loop_child"
    ],
    "op" => "collector_runner_run_loop_child",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_scrub_coverage_environment",
      "_write_loop_state",
      "_job_is_due",
      "run_once",
      "collector_log"
    ]
  },
  {
    "line" => 7451,
    "names" => [
      "stop_loop"
    ],
    "op" => "collector_runner_stop_loop",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_pidfile",
      "_is_managed_loop",
      "_cleanup_loop_files"
    ]
  },
  {
    "line" => 7471,
    "names" => [
      "running_loops"
    ],
    "op" => "collector_runner_running_loops",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "collectors_root",
      "_is_managed_loop",
      "_cleanup_loop_files",
      "sort _sort_loop_names"
    ]
  },
  {
    "line" => 7493,
    "names" => [
      "_sort_loop_names"
    ],
    "op" => "collector_runner_sort_loop_names",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "\$a->{name} cmp \$b->{name}"
    ]
  },
  {
    "line" => 7507,
    "names" => [
      "loop_state"
    ],
    "op" => "collector_runner_loop_state",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_statefile",
      "json_decode",
      "return if !-f \$file"
    ]
  },
  {
    "line" => 7524,
    "names" => [
      "_pidfile"
    ],
    "op" => "collector_runner_pidfile",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "collectors_root",
      "\"\$name.pid\""
    ]
  },
  {
    "line" => 7539,
    "names" => [
      "_statefile"
    ],
    "op" => "collector_runner_statefile",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "collector_dir",
      "'loopxjson'"
    ]
  },
  {
    "line" => 7554,
    "names" => [
      "_process_title"
    ],
    "op" => "collector_runner_process_title",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "dashboard collector: \$name"
    ]
  },
  {
    "line" => 7568,
    "names" => [
      "_read_proc_file"
    ],
    "op" => "collector_runner_read_proc_file",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "return if !-r \$file",
      "open my \$fh, '<', \$file or return"
    ]
  },
  {
    "line" => 7583,
    "names" => [
      "_read_process_env_marker"
    ],
    "op" => "collector_runner_read_process_env_marker",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "/proc/\$pid/environ",
      "split /\\0/, \$env",
      "return \$2 if \$1 eq \$key"
    ]
  },
  {
    "line" => 7599,
    "names" => [
      "_read_process_title"
    ],
    "op" => "collector_runner_read_process_title",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_read_proc_file",
      "system 'ps', '-o', 'args=', '-p', \$pid"
    ]
  },
  {
    "line" => 7615,
    "names" => [
      "_is_managed_loop"
    ],
    "op" => "collector_runner_is_managed_loop",
    "pkgcheck" => 1,
    "skip" => [
      2
    ],
    "tail" => "",
    "terms" => [
      "_read_process_env_marker",
      "_read_process_title",
      "_process_title"
    ]
  },
  {
    "line" => 7634,
    "names" => [
      "_write_loop_state"
    ],
    "op" => "collector_runner_write_loop_state",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_statefile",
      "json_encode",
      "rename \$tmp, \$file"
    ]
  },
  {
    "line" => 7652,
    "names" => [
      "_cleanup_loop_files"
    ],
    "op" => "collector_runner_cleanup_loop_files",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "unlink \$self->_pidfile",
      "unlink \$self->_statefile"
    ]
  },
  {
    "line" => 7669,
    "names" => [
      "_scrub_coverage_environment"
    ],
    "op" => "collector_runner_scrub_coverage_environment",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_coverage_instrumentation_active",
      "delete \@ENV"
    ]
  },
  {
    "line" => 7685,
    "names" => [
      "_coverage_instrumentation_active"
    ],
    "op" => "collector_runner_coverage_instrumentation_active",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "PERL5OPT",
      "HARNESS_PERL_SWITCHES",
      "Devel::Cover"
    ]
  },
  {
    "line" => 7701,
    "names" => [
      "_job_is_due"
    ],
    "op" => "collector_runner_job_is_due",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "return 0 if \$mode eq 'manual'",
      "return 1 if \$mode eq 'interval'",
      "_cron_due"
    ]
  },
  {
    "line" => 7718,
    "names" => [
      "_cron_due"
    ],
    "op" => "collector_runner_cron_due",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "split /\\s+/, \$expr",
      "last_cron_slot",
      "_write_loop_state"
    ]
  },
  {
    "line" => 7737,
    "names" => [
      "_cron_match"
    ],
    "op" => "collector_runner_cron_match",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "split /,/, \$spec",
      "\\*/(\\d+)",
      "if ( \$part =~ /^(\\d+)-(\\d+)\$/"
    ]
  },
  {
    "line" => 7753,
    "names" => [
      "_slurp"
    ],
    "op" => "fs_slurp",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "Unable to read \$file",
      "return <\$fh>;"
    ]
  },
  {
    "line" => 7768,
    "names" => [
      "_run_command"
    ],
    "op" => "collector_runner_run_command",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "shell_command_argv",
      "__COLLECTOR_TIMEOUT__",
      "chdir \$cwd"
    ]
  },
  {
    "line" => 7784,
    "names" => [
      "_run_code"
    ],
    "op" => "collector_runner_run_code",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "eval \$code",
      "__COLLECTOR_TIMEOUT__",
      "chdir \$cwd"
    ]
  },
  {
    "line" => 7800,
    "names" => [
      "_shutdown_loop"
    ],
    "op" => "collector_runner_shutdown_loop",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_write_loop_state",
      "_cleanup_loop_files",
      "exit 0"
    ]
  },
  {
    "line" => 7820,
    "names" => [
      "_signal_stop"
    ],
    "op" => "collector_runner_signal_stop",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "\$SIGNAL_RUNNER->_shutdown_loop"
    ]
  },
  {
    "line" => 7834,
    "names" => [
      "dispatch"
    ],
    "op" => "skill_dispatcher_dispatch",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "unknown_skill_command_message",
      "execute_hooks",
      "_skill_env",
      "command_argv_for_path"
    ]
  },
  {
    "line" => 7855,
    "names" => [
      "exec_command"
    ],
    "op" => "skill_dispatcher_exec_command",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "unknown_skill_command_message",
      "_execute_hooks_streaming",
      "_exec_resolved_command"
    ]
  },
  {
    "line" => 7876,
    "names" => [
      "execute_hooks"
    ],
    "op" => "skill_dispatcher_execute_hooks",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_command_spec",
      "_skill_env",
      "load_runtime_layers",
      "load_skill_layers"
    ]
  },
  {
    "line" => 7896,
    "names" => [
      "_execute_hooks_streaming"
    ],
    "op" => "skill_dispatcher_execute_hooks_streaming",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_arrayref_or_empty",
      "_skill_env",
      "_run_child_command_streaming"
    ]
  },
  {
    "line" => 7915,
    "names" => [
      "_run_child_command_streaming"
    ],
    "op" => "skill_dispatcher_run_child_command_streaming",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_arrayref_or_empty",
      "_hashref_or_empty",
      "_defined_or_default",
      "open3",
      "IO::Select"
    ]
  },
  {
    "line" => 7936,
    "names" => [
      "_exec_resolved_command"
    ],
    "op" => "skill_dispatcher_exec_resolved_command",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_arrayref_or_empty",
      "_exec_replacement"
    ]
  },
  {
    "line" => 7953,
    "names" => [
      "_exec_replacement"
    ],
    "op" => "skill_dispatcher_exec_replacement",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "!exec \@command, \@args"
    ]
  },
  {
    "line" => 7967,
    "names" => [
      "get_skill_config"
    ],
    "op" => "skill_dispatcher_get_skill_config",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_skill_layers",
      "config/', 'config.json'|config', 'configxjson",
      "_merge_skill_hashes"
    ]
  },
  {
    "line" => 7985,
    "names" => [
      "get_skill_path"
    ],
    "op" => "skill_dispatcher_get_skill_path",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "manager}->get_skill_path"
    ]
  },
  {
    "line" => 7999,
    "names" => [
      "command_hook_paths"
    ],
    "op" => "skill_dispatcher_command_hook_paths",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_command_spec",
      "cli', \"\$resolved_command.d\"",
      "is_runnable_file"
    ]
  },
  {
    "line" => 8016,
    "names" => [
      "route_response"
    ],
    "op" => "skill_dispatcher_route_response",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_skill_layers",
      "_skill_bookmark_entries",
      "_skill_page_response"
    ]
  },
  {
    "line" => 8035,
    "names" => [
      "skill_nav_pages"
    ],
    "op" => "skill_dispatcher_skill_nav_pages",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_skill_nav_route_ids",
      "_load_skill_page"
    ]
  },
  {
    "line" => 8052,
    "names" => [
      "all_skill_nav_pages"
    ],
    "op" => "skill_dispatcher_all_skill_nav_pages",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "installed_skill_roots",
      "skill_nav_pages"
    ]
  },
  {
    "line" => 8068,
    "names" => [
      "_skill_page_response"
    ],
    "op" => "skill_dispatcher_skill_page_response",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_load_skill_page",
      "_page_with_runtime_state",
      "_page_response"
    ]
  },
  {
    "line" => 8085,
    "names" => [
      "_load_skill_page"
    ],
    "op" => "skill_dispatcher_load_skill_page",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_page_location",
      "PageDocument->from_instruction",
      "source_kind"
    ]
  },
  {
    "line" => 8103,
    "names" => [
      "_skill_env"
    ],
    "op" => "skill_dispatcher_skill_env",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "DEVELOPER_DASHBOARD_SKILL_NAME",
      "PERL5LIB",
      "DEVELOPER_DASHBOARD_SKILL_LOCAL_ROOT"
    ]
  },
  {
    "line" => 8119,
    "names" => [
      "_session_file"
    ],
    "op" => "session_file_path",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "sessions_root",
      "\"\$session_id.json\""
    ]
  },
  {
    "line" => 8133,
    "names" => [
      "_session_file_candidates"
    ],
    "op" => "session_file_candidates",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "sessions_roots",
      "map { File::Spec->catfile"
    ]
  },
  {
    "line" => 8147,
    "names" => [
      "create"
    ],
    "op" => "session_create",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "Missing username",
      "sha256_hex",
      "chmod 0600"
    ]
  },
  {
    "line" => 8165,
    "names" => [
      "get"
    ],
    "op" => "session_get",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_session_file_candidates",
      "json_decode",
      "return if !defined \$session_id"
    ]
  },
  {
    "line" => 8181,
    "names" => [
      "delete"
    ],
    "op" => "session_delete",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "unlink \$_ for grep { -f \$_ }",
      "_session_file_candidates"
    ]
  },
  {
    "line" => 8196,
    "names" => [
      "from_cookie"
    ],
    "op" => "session_from_cookie",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "dashboard_session",
      "_iso8601_to_epoch",
      "remote_addr"
    ]
  },
  {
    "line" => 8214,
    "names" => [
      "_user_file"
    ],
    "op" => "auth_user_file_path",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "users_root",
      "File::Spec->catfile",
      "\$safe =~ s/[^A-Za-z0-9_.-]+/_/g"
    ]
  },
  {
    "line" => 8229,
    "names" => [
      "_user_file_candidates"
    ],
    "op" => "auth_user_file_candidates",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "users_roots",
      "map { File::Spec->catfile",
      "\$safe =~ s/[^A-Za-z0-9_.-]+/_/g"
    ]
  },
  {
    "line" => 8244,
    "names" => [
      "_password_hash"
    ],
    "op" => "auth_password_hash",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "sha256_hex",
      "join ':', \$salt, \$username, \$password"
    ]
  },
  {
    "line" => 8258,
    "names" => [
      "add_user"
    ],
    "op" => "auth_add_user",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "Username contains unsupported characters",
      "Password must be at least 8 characters long",
      "chmod 0600",
      "_password_hash",
      "_user_file"
    ]
  },
  {
    "line" => 8278,
    "names" => [
      "get_user"
    ],
    "op" => "auth_get_user",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_user_file_candidates",
      "json_decode",
      "Unable to read \$file"
    ]
  },
  {
    "line" => 8294,
    "names" => [
      "verify_user"
    ],
    "op" => "auth_verify_user",
    "pkgcheck" => 0,
    "skip" => [
      2
    ],
    "tail" => "",
    "terms" => [
      "get_user",
      "_password_hash",
      "password_hash"
    ]
  },
  {
    "line" => 8311,
    "names" => [
      "list_users"
    ],
    "op" => "auth_list_users",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "users_roots",
      "readdir",
      "get_user",
      "username"
    ]
  },
  {
    "line" => 8328,
    "names" => [
      "remove_user"
    ],
    "op" => "auth_remove_user",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "unlink \$_ for grep { -f \$_ }",
      "_user_file_candidates"
    ]
  },
  {
    "line" => 8343,
    "names" => [
      "helper_users_enabled"
    ],
    "op" => "auth_helper_users_enabled",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "list_users",
      "return \@users ? 1 : 0"
    ]
  },
  {
    "line" => 8358,
    "names" => [
      "_canonical_host"
    ],
    "op" => "auth_canonical_host",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "s/^\\s+//",
      "s/\\s+\$//",
      "return if \$host eq ''",
      "\$host =~ /^\\[",
      "\$host =~ /^([^:]+):\\d+\$",
      "return lc \$host"
    ]
  },
  {
    "line" => 8376,
    "names" => [
      "_canonical_ip"
    ],
    "op" => "auth_canonical_ip",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "inet_pton",
      "inet_ntop",
      "\\A(?:\\d{1,3}\\x){3}\\d{1,3}\\z"
    ]
  },
  {
    "line" => 8391,
    "names" => [
      "_ip_is_loopback"
    ],
    "op" => "auth_ip_is_loopback",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      127,
      "::1",
      "0:0:0:0:0:0:0:1"
    ]
  },
  {
    "line" => 8406,
    "names" => [
      "_resolve_host_ips"
    ],
    "op" => "auth_resolve_host_ips",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "getaddrinfo",
      "unpack_sockaddr_in",
      "unpack_sockaddr_in6"
    ]
  },
  {
    "line" => 8422,
    "names" => [
      "_host_resolves_only_to_loopback"
    ],
    "op" => "auth_host_resolves_only_to_loopback",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_resolve_host_ips",
      "_ip_is_loopback",
      "return !grep"
    ]
  },
  {
    "line" => 8439,
    "names" => [
      "_request_is_loopback_admin"
    ],
    "op" => "auth_request_is_loopback_admin",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "extra_loopback_hosts",
      "_ip_is_loopback",
      "_host_resolves_only_to_loopback"
    ]
  },
  {
    "line" => 8457,
    "names" => [
      "trust_tier"
    ],
    "op" => "auth_trust_tier",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "_canonical_ip",
      "_canonical_host",
      "_request_is_loopback_admin"
    ]
  },
  {
    "line" => 8475,
    "names" => [
      "login_page"
    ],
    "op" => "auth_login_page",
    "pkgcheck" => 0,
    "tail" => "",
    "terms" => [
      "Developer Dashboard Login",
      "Helper access requires login",
      "action=\"/login\""
    ]
  },
  {
    "line" => 8490,
    "names" => [
      "_normalized_page_id"
    ],
    "op" => "page_store_normalized_page_id",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "s{\\A/+app/+}{}",
      "s{\\A/+}{}"
    ]
  },
  {
    "line" => 8505,
    "names" => [
      "page_file"
    ],
    "op" => "page_store_page_file",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "Missing page id",
      "dashboards_root",
      "_normalized_page_id"
    ]
  },
  {
    "line" => 8522,
    "names" => [
      "_page_file_candidates"
    ],
    "op" => "page_store_file_candidates",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "dashboards_roots",
      "_normalized_page_id",
      "map { File::Spec->catfile"
    ]
  },
  {
    "line" => 8539,
    "names" => [
      "_existing_page_file"
    ],
    "op" => "page_store_existing_page_file",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_page_file_candidates",
      "return \$file if -f \$file"
    ]
  },
  {
    "line" => 8555,
    "names" => [
      "load_transient_page"
    ],
    "op" => "page_store_load_transient_page",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "decode_payload",
      "PageDocument->from_instruction"
    ]
  },
  {
    "line" => 8571,
    "names" => [
      "encode_page"
    ],
    "op" => "page_store_encode_page",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "from_hash",
      "raw_instruction",
      "canonical_instruction",
      "encode_payload"
    ]
  },
  {
    "line" => 8589,
    "names" => [
      "editable_url",
      "render_url",
      "source_url"
    ],
    "op" => "page_store_token_url",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "uri_escape",
      "encode_page"
    ]
  },
  {
    "line" => 8611,
    "names" => [
      "_looks_like_raw_nav_fragment"
    ],
    "op" => "page_store_looks_like_raw_nav_fragment",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "[%",
      "<\\s*[A-Za-z!\\/][^>]*>"
    ]
  },
  {
    "line" => 8626,
    "names" => [
      "_normalize_legacy_icon_markup"
    ],
    "op" => "page_store_normalize_legacy_icon_markup",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "1F9D1",
      "FFFD",
      "span\\s+class=\"icon\""
    ]
  },
  {
    "line" => 8642,
    "names" => [
      "_read_saved_instruction"
    ],
    "op" => "page_store_read_saved_instruction",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "decode( 'UTF-8', \$raw, FB_CROAK )",
      "_normalize_legacy_icon_markup"
    ]
  },
  {
    "line" => 8658,
    "names" => [
      "_raw_nav_fragment_page"
    ],
    "op" => "page_store_raw_nav_fragment_page",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "PageDocument->new",
      "raw-nav-tt"
    ]
  },
  {
    "line" => 8674,
    "names" => [
      "_load_page_file"
    ],
    "op" => "page_store_load_page_file",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_read_saved_instruction",
      "from_instruction",
      "_looks_like_raw_nav_fragment",
      "_raw_nav_fragment_page"
    ]
  },
  {
    "line" => 8695,
    "names" => [
      "read_saved_entry"
    ],
    "op" => "page_store_read_saved_entry",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "Page '\$id' not found",
      "_existing_page_file",
      "_read_saved_instruction"
    ]
  },
  {
    "line" => 8713,
    "names" => [
      "load_saved_page"
    ],
    "op" => "page_store_load_saved_page",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_existing_page_file",
      "_load_page_file",
      "raw_instruction"
    ]
  },
  {
    "line" => 8732,
    "names" => [
      "save_page"
    ],
    "op" => "page_store_save_page",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "canonical_instruction",
      "secure_file_permissions",
      "from_hash"
    ]
  },
  {
    "line" => 8750,
    "names" => [
      "_saved_page_entries_for_root"
    ],
    "op" => "page_store_saved_page_entries_for_root",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "File::Find::find",
      "abs2rel"
    ]
  },
  {
    "line" => 8765,
    "names" => [
      "list_saved_pages"
    ],
    "op" => "page_store_list_saved_pages",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "dashboards_roots",
      "_saved_page_entries_for_root",
      "_load_page_file"
    ]
  },
  {
    "line" => 8783,
    "names" => [
      "migrate_legacy_json_pages"
    ],
    "op" => "page_store_migrate_legacy_json_pages",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      ".json\\z",
      "from_json",
      "canonical_instruction",
      "unlink \$file"
    ]
  },
  {
    "line" => 8802,
    "names" => [
      "_indicator_file_candidates"
    ],
    "op" => "indicator_store_file_candidates",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "indicators_roots",
      "status.json"
    ]
  },
  {
    "line" => 8817,
    "names" => [
      "_read_indicator_file"
    ],
    "op" => "indicator_store_read_indicator_file",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "json_decode",
      "<:raw"
    ]
  },
  {
    "line" => 8832,
    "names" => [
      "new"
    ],
    "op" => "page_document_new",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "bless {",
      "title => \$args{title} // 'Untitled'",
      "meta => \$args{meta} || {}"
    ]
  },
  {
    "line" => 8848,
    "names" => [
      "from_hash"
    ],
    "op" => "page_document_from_hash",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "Page document must be a hash reference",
      "return \$class->new(%\$hash)"
    ]
  },
  {
    "line" => 8864,
    "names" => [
      "from_json"
    ],
    "op" => "page_document_from_json",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "json_decode",
      "from_hash"
    ]
  },
  {
    "line" => 8880,
    "names" => [
      "from_instruction"
    ],
    "op" => "page_document_from_instruction",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "source_format = 'modern'",
      "_parse_legacy_sections",
      "Instruction document did not contain any sections",
      "_decode_stash_section",
      "\$class->new"
    ]
  },
  {
    "line" => 8903,
    "names" => [
      "merge_state"
    ],
    "op" => "page_document_merge_state",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "ref(\$state) ne 'HASH'",
      "\$self->{state}{\$key} = \$state->{\$key}"
    ]
  },
  {
    "line" => 8918,
    "names" => [
      "with_mode"
    ],
    "op" => "page_document_with_mode",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "\$self->{mode} = \$mode if defined \$mode && \$mode ne ''"
    ]
  },
  {
    "line" => 8932,
    "names" => [
      "as_hash"
    ],
    "op" => "page_document_as_hash",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "source_version",
      "permissions",
      "meta"
    ]
  },
  {
    "line" => 8948,
    "names" => [
      "canonical_json"
    ],
    "op" => "page_document_canonical_json",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "json_encode",
      "as_hash"
    ]
  },
  {
    "line" => 8964,
    "names" => [
      "canonical_instruction"
    ],
    "op" => "page_document_canonical_instruction",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "legacy_instruction"
    ]
  },
  {
    "line" => 8979,
    "names" => [
      "legacy_instruction"
    ],
    "op" => "page_document_legacy_instruction",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "_legacy_stash_text",
      "\$LEGACY_SEP",
      "CODE\\d+"
    ]
  },
  {
    "line" => 8996,
    "names" => [
      "instruction_text"
    ],
    "op" => "page_document_instruction_text",
    "pkgcheck" => 1,
    "tail" => "",
    "terms" => [
      "canonical_instruction"
    ]
  }
];

# _body($name, \@snippets)
# Builds a module source holding one sub whose body is the snippets, one per line,
# with braces balanced so the compiler's brace-counting body extractor terminates.
# Input: sub name and snippet list. Output: source text.
sub _body {
    my ($name, $snips) = @_;
    my $b = join("\n", @{$snips});
    my $depth = 0;
    for my $ch (split //, $b) {
        $depth++ if $ch eq '{';
        $depth-- if $ch eq '}';
    }
    $b .= "\n" . ('}' x $depth) if $depth > 0;
    $b = ('{' x -$depth) . "\n" . $b if $depth < 0;
    return "sub $name {\n$b\n}\n";
}

# _op($name, $package, \@snippets)
# Runs the transform-sub recognizer over a synthetic sub.
# Input: sub name, package, body snippets. Output: the op name, or 'none'.
sub _op {
    my ($name, $package, $snips) = @_;
    my $r = PAX::CodeUnitCompiler::_compile_simple_transform_sub_from_source(
        _body($name, $snips), $name, $package . '::' . $name);
    return $r ? $r->{op} : 'none';
}

for my $e (@{$table}) {
    my $op = $e->{op};
    my $pkg = 'Zed::Pkg' . (length $e->{tail} ? '::' . $e->{tail} : '');
    my @terms = @{ $e->{terms} };
    my %skip = map { $_ => 1 } @{ $e->{skip} || [] };
    for my $name (@{ $e->{names} }) {
        is(_op($name, $pkg, \@terms), $op, "$op: matches as $name");
    }
    my $name = $e->{names}[0];
    for my $k (0 .. $#terms) {
        next if $skip{$k};
        my @prefix = @terms[0 .. $k - 1];
        isnt(_op($name, $pkg, \@prefix), $op, "$op: no match when body regex $k is missing");
    }
    isnt(_op('zz_other_name', $pkg, \@terms), $op, "$op: no match for another sub name");
    if (length $e->{tail}) {
        isnt(_op($name, 'Zed::Pkg::Elsewhere', \@terms), $op, "$op: no match for another package");
    }
}

done_testing;
