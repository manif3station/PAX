use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use PAX::CodeUnitCompiler;

=pod

=head1 NAME

t/cov_cucb_matchers.t - source-shape matcher coverage for CodeUnitCompiler

=head1 WHY IT EXISTS

C<_compile_simple_transform_sub_from_source> recognises many subs by a sub name, a package tail
and loose regexes over the sub body. Each recogniser has a "matches" outcome and
several "just misses" outcomes (wrong name, wrong package, one regex missing).
This file drives every recogniser in the range with synthetic sources so both
outcomes of every condition are exercised.

=head1 DESCRIPTION

Each table row is: source line of the recogniser, sub name, package tail,
expected op, a body satisfying every regex, whether the name is itself a regex,
and one body per regex with that regex's evidence removed.

=cut

my @rows = (
[3002,"_command_exit","","query_command_exit","exit \$code",0,[""]],
[3016,"api_dashboard_page","","seeded_pages_api_dashboard_page","api-dashboard.page\n_page_from_asset",0,["_page_from_asset","api-dashboard.page"]],
[3032,"sql_dashboard_page","","seeded_pages_sql_dashboard_page","sql-dashboard.page\n_page_from_asset",0,["_page_from_asset","sql-dashboard.page"]],
[3048,"page_for_id","","seeded_pages_page_for_id","_seeded_page_asset_filename\n_page_from_asset",0,["_page_from_asset","_seeded_page_asset_filename"]],
[3065,"seed_manifest_path","","seeded_pages_manifest_path","config_root\nseeded-pages.json",0,["seeded-pages.json","config_root"]],
[3080,"known_managed_page_md5s","","seeded_pages_known_managed_page_md5s","_seeded_page_asset_filename\ncontent_md5\nLEGACY_MANAGED_PAGE_MD5",0,["content_md5\nLEGACY_MANAGED_PAGE_MD5","_seeded_page_asset_filename\nLEGACY_MANAGED_PAGE_MD5","_seeded_page_asset_filename\ncontent_md5"]],
[3105,"is_known_managed_page_md5","","seeded_pages_is_known_managed_page_md5","known_managed_page_md5s\nreturn 0 if \$id eq '' || \$md5 eq ''",0,["return 0 if \$id eq '' || \$md5 eq ''","known_managed_page_md5s"]],
[3121,"_page_from_asset","","seeded_pages_page_from_asset","_seeded_page_instruction\nPageDocument->from_instruction",0,["PageDocument->from_instruction","_seeded_page_instruction"]],
[3138,"_seeded_page_instruction","","seeded_pages_instruction","_seeded_page_asset_path\nPAGE_CACHE\nUnable to read",0,["PAGE_CACHE\nUnable to read","_seeded_page_asset_path\nUnable to read","_seeded_page_asset_path\nPAGE_CACHE"]],
[3155,"_seeded_page_asset_filename","","seeded_pages_asset_filename","Unknown seeded page id\nID_TO_ASSET",0,["ID_TO_ASSET","Unknown seeded page id"]],
[3174,"_seeded_page_asset_path","","seeded_pages_asset_path","_repo_seeded_pages_root\n_shared_seeded_pages_root",0,["_shared_seeded_pages_root","_repo_seeded_pages_root"]],
[3191,"_repo_seeded_pages_root","","seeded_pages_repo_root","dirname(__FILE__)\nseeded-pages\nFile::Spec->updir",0,["seeded-pages\nFile::Spec->updir","dirname(__FILE__)\nFile::Spec->updir","dirname(__FILE__)\nseeded-pages"]],
[3207,"_shared_seeded_pages_root","","seeded_pages_shared_root","dist_dir\nseeded-pages",0,["seeded-pages","dist_dir"]],
[3222,"_read_manifest","","seeded_pages_read_manifest","seed_manifest_path\njson_decode\nmust decode to a hash",0,["json_decode\nmust decode to a hash","seed_manifest_path\nmust decode to a hash","seed_manifest_path\njson_decode"]],
[3239,"_write_manifest","","seeded_pages_write_manifest","seed_manifest_path\njson_encode\nsecure_file_permissions",0,["json_encode\nsecure_file_permissions","seed_manifest_path\nsecure_file_permissions","seed_manifest_path\njson_encode"]],
[3256,"_record_manifest_md5","","seeded_pages_record_manifest_md5","_read_manifest\n_seeded_page_asset_filename\n_write_manifest",0,["_seeded_page_asset_filename\n_write_manifest","_read_manifest\n_write_manifest","_read_manifest\n_seeded_page_asset_filename"]],
[3275,"_manifest_md5_matches","","seeded_pages_manifest_md5_matches","_read_manifest\nreturn 0 if \$id eq '' || \$md5 eq ''",0,["return 0 if \$id eq '' || \$md5 eq ''","_read_manifest"]],
[3291,"ensure_seeded_page","","seeded_pages_ensure_seeded_page","canonical_instruction\n_manifest_md5_matches\nis_known_managed_page_md5",0,["_manifest_md5_matches\nis_known_managed_page_md5","canonical_instruction\nis_known_managed_page_md5","canonical_instruction\n_manifest_md5_matches"]],
[3311,"_load_configured_aliases","","folder_load_configured_aliases","FileRegistry->new\nConfig->new\npath_aliases",0,["Config->new\npath_aliases","FileRegistry->new\npath_aliases","FileRegistry->new\nConfig->new"]],
[3331,"_resolve_path","","folder_resolve_path","_paths_obj\n_load_configured_aliases\nDEVELOPER_DASHBOARD_PATH_",0,["_load_configured_aliases\nDEVELOPER_DASHBOARD_PATH_","_paths_obj\nDEVELOPER_DASHBOARD_PATH_","_paths_obj\n_load_configured_aliases"]],
[3351,"AUTOLOAD","","folder_autoload","Unknown folder\n_resolve_path\nmake_path",0,["_resolve_path\nmake_path","Unknown folder\nmake_path","Unknown folder\n_resolve_path"]],
[3369,"cd","","folder_cd","",0,[]],
[3383,"ls","","folder_ls","_resolve_path\nreaddir\ntype => -d \$path ? 'folder' : 'file'\nsort { \$b->{type} cmp \$a->{type}\n}",0,["readdir\ntype => -d \$path ? 'folder' : 'file'\nsort { \$b->{type} cmp \$a->{type}\n}","_resolve_path\ntype => -d \$path ? 'folder' : 'file'\nsort { \$b->{type} cmp \$a->{type}\n}","_resolve_path\nreaddir\nsort { \$b->{type} cmp \$a->{type}\n}","_resolve_path\nreaddir\ntype => -d \$path ? 'folder' : 'file'"]],
[3401,"locate","","folder_locate","workspace_roots\nFile::Find::find\nreturn grep { !\$seen{\$_}++ } sort \@found",0,["File::Find::find\nreturn grep { !\$seen{\$_}++ } sort \@found","workspace_roots\nreturn grep { !\$seen{\$_}++ } sort \@found","workspace_roots\nFile::Find::find"]],
[3418,"_state_root_has_live_collectors","","housekeeper_state_root_has_live_collectors","collectors\n.pid\\z\nkill 0, \$pid",0,[".pid\\z\nkill 0, \$pid","collectors\nkill 0, \$pid","collectors\n.pid\\z"]],
[3434,"_state_root_is_stale","","housekeeper_state_root_is_stale","_path_is_old_enough\n_state_root_has_live_collectors\n_read_state_metadata",0,["_state_root_has_live_collectors\n_read_state_metadata","_path_is_old_enough\n_read_state_metadata","_path_is_old_enough\n_state_root_has_live_collectors"]],
[3453,"_cleanup_state_roots","","housekeeper_cleanup_state_roots","state_base_root\nruntime_layers\n_state_root_is_stale\n_remove_tree",0,["runtime_layers\n_state_root_is_stale\n_remove_tree","state_base_root\n_state_root_is_stale\n_remove_tree","state_base_root\nruntime_layers\n_remove_tree","state_base_root\nruntime_layers\n_state_root_is_stale"]],
[3472,"_cleanup_temp_files","","housekeeper_cleanup_temp_files","tmpdir\n_temp_file_kind\n_path_is_old_enough\nUnable to remove stale",0,["_temp_file_kind\n_path_is_old_enough\nUnable to remove stale","tmpdir\n_path_is_old_enough\nUnable to remove stale","tmpdir\n_temp_file_kind\nUnable to remove stale","tmpdir\n_temp_file_kind\n_path_is_old_enough"]],
[3491,"_rotate_collector_logs","","housekeeper_rotate_collector_logs","_config->collectors\n_collector_rotation\n_collector_store->rotate_log",0,["_collector_rotation\n_collector_store->rotate_log","_config->collectors\n_collector_store->rotate_log","_config->collectors\n_collector_rotation"]],
[3510,"run","","housekeeper_run","min_age_seconds must be a non-negative integer\n_cleanup_state_roots\n_cleanup_temp_files\n_rotate_collector_logs\n_now_iso8601",0,["_cleanup_state_roots\n_cleanup_temp_files\n_rotate_collector_logs\n_now_iso8601","min_age_seconds must be a non-negative integer\n_cleanup_temp_files\n_rotate_collector_logs\n_now_iso8601","min_age_seconds must be a non-negative integer\n_cleanup_state_roots\n_rotate_collector_logs\n_now_iso8601","min_age_seconds must be a non-negative integer\n_cleanup_state_roots\n_cleanup_temp_files\n_now_iso8601","min_age_seconds must be a non-negative integer\n_cleanup_state_roots\n_cleanup_temp_files\n_rotate_collector_logs"]],
[3532,"_current_backend","","dancerapp_current_backend","\$BACKEND_APP\nMissing backend web app",0,["Missing backend web app","\$BACKEND_APP"]],
[3548,"_request_headers","","dancerapp_request_headers","request->header('Host')\nrequest->header('Cookie')",0,["request->header('Cookie')","request->header('Host')"]],
[3563,"_request_args","","dancerapp_request_args","SERVER_NAME\nPATH_INFO\n_request_headers",0,["PATH_INFO\n_request_headers","SERVER_NAME\n_request_headers","SERVER_NAME\nPATH_INFO"]],
[3580,"_capture","","dancerapp_capture","my \@parts = splat;\nref( \$parts[0] ) eq 'ARRAY'",0,["ref( \$parts[0] ) eq 'ARRAY'","my \@parts = splat;"]],
[3595,"_looks_like_disconnect_error","","dancerapp_disconnect_error","broken pipe\nconnection reset\nwrite failed",0,["connection reset\nwrite failed","broken pipe\nwrite failed","broken pipe\nconnection reset"]],
[3611,"_response_from_result","","dancerapp_response_from_result","default_headers\ndelayed {\nresponse_header\ncontent_type\n}",0,["delayed {\nresponse_header\ncontent_type\n}","default_headers\nresponse_header\ncontent_type","default_headers\ndelayed {\ncontent_type\n}","default_headers\ndelayed {\nresponse_header\n}"]],
[3630,"_run_backend","","dancerapp_run_backend","_current_backend\n_request_args\n_response_from_result\ndoes not implement",0,["_request_args\n_response_from_result\ndoes not implement","_current_backend\n_response_from_result\ndoes not implement","_current_backend\n_request_args\ndoes not implement","_current_backend\n_request_args\n_response_from_result"]],
[3650,"_run_authorized","","dancerapp_run_authorized","authorize_request\n_current_backend\n_request_args\n_response_from_result",0,["_current_backend\n_request_args\n_response_from_result","authorize_request\n_request_args\n_response_from_result","authorize_request\n_current_backend\n_response_from_result","authorize_request\n_current_backend\n_request_args"]],
[3670,"new","","web_server_new","Missing web app\nWorker count must be a positive integer\ngenerate_self_signed_cert",0,["Worker count must be a positive integer\ngenerate_self_signed_cert","Missing web app\ngenerate_self_signed_cert","Missing web app\nWorker count must be a positive integer"]],
[3687,"run","","web_server_run","start_daemon\nlistening_url\nserve_daemon",0,["listening_url\nserve_daemon","start_daemon\nserve_daemon","start_daemon\nlistening_url"]],
[3706,"listening_url","","web_server_listening_url","https\nhttp\nlocalhost",0,["http\nlocalhost","localhost","https\nhttp"]],
[3722,"serve_daemon","","web_server_serve_daemon","_serve_ssl_frontend\n_build_runner\npsgi_app",0,["_build_runner\npsgi_app","_serve_ssl_frontend\npsgi_app","_serve_ssl_frontend\n_build_runner"]],
[3741,"psgi_app","","web_server_psgi_app","Web::DancerApp->build_psgi_app\n_default_headers\n_ssl_redirect_response",0,["_default_headers\n_ssl_redirect_response","Web::DancerApp->build_psgi_app\n_ssl_redirect_response","Web::DancerApp->build_psgi_app\n_default_headers"]],
[3760,"start_daemon","","web_server_start_daemon","IO::Socket::INET->new\nUnable to reserve internal SSL backend port\nWeb::Server::Daemon->new",0,["Unable to reserve internal SSL backend port\nWeb::Server::Daemon->new","IO::Socket::INET->new\nWeb::Server::Daemon->new","IO::Socket::INET->new\nUnable to reserve internal SSL backend port"]],
[3776,"_serve_ssl_frontend","","web_server_serve_ssl_frontend","Unable to fork SSL backend process\n_build_runner\n_handle_ssl_frontend_client\n_stop_ssl_backend",0,["_build_runner\n_handle_ssl_frontend_client\n_stop_ssl_backend","Unable to fork SSL backend process\n_handle_ssl_frontend_client\n_stop_ssl_backend","Unable to fork SSL backend process\n_build_runner\n_stop_ssl_backend","Unable to fork SSL backend process\n_build_runner\n_handle_ssl_frontend_client"]],
[3800,"_build_runner","","web_server_build_runner","Plack::Runner->new\n--server', 'Starman'\nget_ssl_cert_paths",0,["--server', 'Starman'\nget_ssl_cert_paths","Plack::Runner->new\nget_ssl_cert_paths","Plack::Runner->new\n--server', 'Starman'"]],
[3817,"_handle_ssl_frontend_client","","web_server_handle_ssl_frontend_client","MSG_PEEK\n_socket_looks_like_tls\n_read_http_request_head\n_http_redirect_response\n\$self->_request_host_from_head(\$request, \$daemon)",0,["_socket_looks_like_tls\n_read_http_request_head\n_http_redirect_response\n\$self->_request_host_from_head(\$request, \$daemon)","MSG_PEEK\n_read_http_request_head\n_http_redirect_response\n\$self->_request_host_from_head(\$request, \$daemon)","MSG_PEEK\n_socket_looks_like_tls\n_http_redirect_response\n\$self->_request_host_from_head(\$request, \$daemon)","MSG_PEEK\n_socket_looks_like_tls\n_read_http_request_head\n\$self->_request_host_from_head(\$request, \$daemon)","MSG_PEEK\n_socket_looks_like_tls\n_read_http_request_head\n_http_redirect_response"]],
[3840,"_proxy_streams","","web_server_proxy_streams","IO::Select->new\nsysread\nsyswrite",0,["sysread\nsyswrite","IO::Select->new\nsyswrite","IO::Select->new\nsysread"]],
[3856,"_socket_looks_like_tls","","web_server_socket_looks_like_tls","return 0 if !defined \$byte || \$byte eq ''\nord(\$byte) == 22",0,["ord(\$byte) == 22","return 0 if !defined \$byte || \$byte eq ''"]],
[3871,"_read_http_request_head","","web_server_read_http_request_head","length(\$head) < 16384\nsysread( \$socket, \$chunk, 1024 )\n\\r?\\n\\r?\\n",0,["sysread( \$socket, \$chunk, 1024 )\n\\r?\\n\\r?\\n","length(\$head) < 16384\n\\r?\\n\\r?\\n","length(\$head) < 16384\nsysread( \$socket, \$chunk, 1024 )"]],
[3887,"_request_target_from_head","","web_server_request_target_from_head","return '/' if !defined \$head || \$head eq ''\nHTTP",0,["HTTP","return '/' if !defined \$head || \$head eq ''"]],
[3902,"_request_host_from_head","","web_server_request_host_from_head","Host:\\s*([^\\r\\n]+)\nsockhost\nsockport",0,["sockhost\nsockport","Host:\\s*([^\\r\\n]+)\nsockport","Host:\\s*([^\\r\\n]+)\nsockhost"]],
[3918,"_http_redirect_response","","web_server_http_redirect_response","307 Temporary Redirect\nLocation: https://\nRedirecting to HTTPS",0,["Location: https://\nRedirecting to HTTPS","307 Temporary Redirect\nRedirecting to HTTPS","307 Temporary Redirect\nLocation: https://"]],
[3934,"_stop_ssl_backend","","web_server_stop_ssl_backend","return 1 if !\$pid\nkill 15, \$pid\nwaitpid( \$pid, 0 )",0,["kill 15, \$pid\nwaitpid( \$pid, 0 )","return 1 if !\$pid\nwaitpid( \$pid, 0 )","return 1 if !\$pid\nkill 15, \$pid"]],
[3950,"_ssl_term_handler","","web_server_ssl_signal_handler","return _handle_ssl_signal('",1,[""]],
[3967,"_handle_ssl_signal","","web_server_handle_ssl_signal","_stop_ssl_backend(\$SSL_BACKEND_PID)\n_run_previous_signal\n\$SSL_SHUTDOWN_REQUESTED = 1;",0,["_run_previous_signal\n\$SSL_SHUTDOWN_REQUESTED = 1;","_stop_ssl_backend(\$SSL_BACKEND_PID)\n\$SSL_SHUTDOWN_REQUESTED = 1;","_stop_ssl_backend(\$SSL_BACKEND_PID)\n_run_previous_signal"]],
[3984,"_run_previous_signal","","web_server_run_previous_signal","ref(\$handler) eq 'CODE'\n_signal_default_term",0,["_signal_default_term","ref(\$handler) eq 'CODE'"]],
[4000,"_signal_default_term","","web_server_signal_default_term","kill 15, \$\$\nreturn 1",0,["return 1","kill 15, \$\$"]],
[4015,"_default_headers","","web_server_default_headers","X-Frame-Options\nContent-Security-Policy",0,["Content-Security-Policy","X-Frame-Options"]],
[4030,"_request_is_https","","web_server_request_is_https","psgi.url_scheme\nHTTP_X_FORWARDED_PROTO",0,["HTTP_X_FORWARDED_PROTO","psgi.url_scheme"]],
[4045,"_ssl_redirect_response","","web_server_ssl_redirect_response","Redirecting to HTTPS\n\$self->_https_redirect_location(\$env)",0,["\$self->_https_redirect_location(\$env)","Redirecting to HTTPS"]],
[4061,"_https_redirect_location","","web_server_https_redirect_location","HTTP_HOST\nSCRIPT_NAME\nPATH_INFO\nQUERY_STRING",0,["SCRIPT_NAME\nPATH_INFO\nQUERY_STRING","HTTP_HOST\nPATH_INFO\nQUERY_STRING","HTTP_HOST\nSCRIPT_NAME\nQUERY_STRING","HTTP_HOST\nSCRIPT_NAME\nPATH_INFO"]],
[4078,"_ssl_expected_subject_alt_names","","web_server_ssl_expected_subject_alt_names","localhost\n_normalize_ssl_subject_alt_name\n_ssl_subject_alt_name_is_wildcard",0,["_normalize_ssl_subject_alt_name\n_ssl_subject_alt_name_is_wildcard","localhost\n_ssl_subject_alt_name_is_wildcard","localhost\n_normalize_ssl_subject_alt_name"]],
[4096,"_normalize_ssl_subject_alt_name","","web_server_normalize_ssl_subject_alt_name","return '' if !defined \$name\n^\\[(.+)\\]",0,["^\\[(.+)\\]","return '' if !defined \$name"]],
[4111,"_ssl_subject_alt_name_is_wildcard","","web_server_ssl_subject_alt_name_is_wildcard","0.0.0.0\n0:0:0:0:0:0:0:0",0,["0:0:0:0:0:0:0:0","0.0.0.0"]],
[4126,"_ssl_subject_alt_name_is_ip","","web_server_ssl_subject_alt_name_is_ip","\\d{1,3}\nreturn 1 if \$name =~ /:",0,["return 1 if \$name =~ /:","\\d{1,3}"]],
[4141,"_ssl_cert_has_expected_profile","","web_server_ssl_cert_has_expected_profile","openssl', 'x509'\nBasic Constraints\nopenssl', 'verify'",0,["Basic Constraints\nopenssl', 'verify'","openssl', 'x509'\nopenssl', 'verify'","openssl', 'x509'\nBasic Constraints"]],
[4159,"generate_self_signed_cert","","web_server_generate_self_signed_cert","dd-openssl-XXXXXX\nopenssl', 'req'\nGenerated certificate is missing",0,["openssl', 'req'\nGenerated certificate is missing","dd-openssl-XXXXXX\nGenerated certificate is missing","dd-openssl-XXXXXX\nopenssl', 'req'"]],
[4178,"get_ssl_cert_paths","","web_server_get_ssl_cert_paths","server.crt\nserver.key",0,["server.key","server.crt"]],
[4193,"new","","runtime_manager_new","Missing config\nMissing path registry\nMissing app builder",0,["Missing path registry\nMissing app builder","Missing config\nMissing app builder","Missing config\nMissing path registry"]],
[4209,"web_log","","runtime_manager_web_log","Line count must be a positive integer\n_tail_text\n_follow_log_file",0,["_tail_text\n_follow_log_file","Line count must be a positive integer\n_follow_log_file","Line count must be a positive integer\n_tail_text"]],
[4227,"_tail_text","","runtime_manager_tail_text","split /\\n/, \$text, -1\njoin \"\\n\"\nhad_trailing_newline",0,["join \"\\n\"\nhad_trailing_newline","split /\\n/, \$text, -1\nhad_trailing_newline","split /\\n/, \$text, -1\njoin \"\\n\""]],
[4243,"_follow_log_file","","runtime_manager_follow_log_file","Missing log file\nsysread( \$fh, \$chunk, 8192 )\nsleep \$interval",0,["sysread( \$fh, \$chunk, 8192 )\nsleep \$interval","Missing log file\nsleep \$interval","Missing log file\nsysread( \$fh, \$chunk, 8192 )"]],
[4259,"web_state","","runtime_manager_web_state","return if !-f \$file\njson_decode\nweb_state",0,["json_decode\nweb_state","return if !-f \$file\nweb_state","return if !-f \$file\njson_decode"]],
[4275,"_shutdown_web","","runtime_manager_shutdown_web","updated_at => _now_iso8601\nstatus     => \$final_status\nexit 0",0,["status     => \$final_status\nexit 0","updated_at => _now_iso8601\nexit 0","updated_at => _now_iso8601\nstatus     => \$final_status"]],
[4293,"_write_web_state","","runtime_manager_write_web_state","json_encode\nsecure_file_permissions\nrename \$tmp, \$file",0,["secure_file_permissions\nrename \$tmp, \$file","json_encode\nrename \$tmp, \$file","json_encode\nsecure_file_permissions"]],
[4309,"_cleanup_web_files","","runtime_manager_cleanup_web_files","remove('web_pid')\nremove('web_state')",0,["remove('web_state')","remove('web_pid')"]],
[4324,"_web_process_title","","runtime_manager_web_process_title","dashboard web: \$host:\$port",0,[""]],
[4338,"_portable_signal","","runtime_manager_portable_signal","Unsupported signal name\nTERM => 15\nreturn \$signal + 0 if \$signal =~",0,["TERM => 15\nreturn \$signal + 0 if \$signal =~","Unsupported signal name\nreturn \$signal + 0 if \$signal =~","Unsupported signal name\nTERM => 15"]],
[4354,"_send_signal","","runtime_manager_send_signal","_portable_signal\nkill \$portable_signal, \@targets",0,["kill \$portable_signal, \@targets","_portable_signal"]],
[4370,"_proc_owned_by_current_user","","runtime_manager_proc_owned_by_current_user","return 1 if !defined \$proc->{uid}\n( \$< + 0 )",0,["( \$< + 0 )","return 1 if !defined \$proc->{uid}"]],
[4385,"_find_legacy_web_processes","","runtime_manager_find_legacy_web_processes","_find_web_processes\n!~ /^dashboard web:/",0,["!~ /^dashboard web:/","_find_web_processes"]],
[4401,"_looks_like_web_process","","runtime_manager_looks_like_web_process","dashboard web:\nbin/dashboard\ndashboard serve",0,["bin/dashboard\ndashboard serve","dashboard web:\ndashboard serve","dashboard web:\nbin/dashboard"]],
[4417,"_ps_processes","","runtime_manager_ps_processes","system 'ps', '-eo', 'pid=,uid=,args='\npush \@procs",0,["push \@procs","system 'ps', '-eo', 'pid=,uid=,args='"]],
[4432,"_find_processes_by_prefix","","runtime_manager_find_processes_by_prefix","_proc_owned_by_current_user\n_ps_processes",0,["_ps_processes","_proc_owned_by_current_user"]],
[4449,"_find_web_processes","","runtime_manager_find_web_processes","_ps_processes\n_looks_like_web_process\n_proc_owned_by_current_user",0,["_looks_like_web_process\n_proc_owned_by_current_user","_ps_processes\n_proc_owned_by_current_user","_ps_processes\n_looks_like_web_process"]],
[4468,"_is_managed_web","","runtime_manager_is_managed_web","_read_process_env_marker\n_read_process_title\n_web_process_title",0,["_read_process_title\n_web_process_title","_read_process_env_marker\n_web_process_title","_read_process_env_marker\n_read_process_title"]],
[4486,"_pkill_perl","","runtime_manager_pkill_perl","system 'pkill', '-15', '-f', \$pattern\n_ps_processes\n_send_signal",0,["_ps_processes\n_send_signal","system 'pkill', '-15', '-f', \$pattern\n_send_signal","system 'pkill', '-15', '-f', \$pattern\n_ps_processes"]],
[4505,"_managed_listener_pids_for_port","","runtime_manager_managed_listener_pids_for_port","_is_managed_web\n_listener_pids_for_port",0,["_listener_pids_for_port","_is_managed_web"]],
[4522,"_listener_pids_for_port","","runtime_manager_listener_pids_for_port","system 'ss', '-ltnp',\n_listener_pids_for_port_via_proc",0,["_listener_pids_for_port_via_proc","system 'ss', '-ltnp',"]],
[4538,"_listener_pids_for_port_via_proc","","runtime_manager_listener_pids_for_port_via_proc","_listener_socket_inodes_for_port\n_process_pids_for_socket_inodes",0,["_process_pids_for_socket_inodes","_listener_socket_inodes_for_port"]],
[4555,"_listener_socket_inodes_for_port","","runtime_manager_listener_socket_inodes_for_port","_listener_socket_table_paths\nsprintf '%04X', \$port\n\$fields[3] ne '0A'",0,["sprintf '%04X', \$port\n\$fields[3] ne '0A'","_listener_socket_table_paths\n\$fields[3] ne '0A'","_listener_socket_table_paths\nsprintf '%04X', \$port"]],
[4572,"_process_pids_for_socket_inodes","","runtime_manager_process_pids_for_socket_inodes","_process_fd_paths\nreadlink \$fd_path\nsocket:[(\\d+)]",0,["readlink \$fd_path\nsocket:[(\\d+)]","_process_fd_paths\nsocket:[(\\d+)]","_process_fd_paths\nreadlink \$fd_path"]],
[4589,"start_collectors","","runtime_manager_start_collectors","_progress_emit\ncollectors\nstart_loop\n_collector_runtime_ready",0,["collectors\nstart_loop\n_collector_runtime_ready","_progress_emit\nstart_loop\n_collector_runtime_ready","_progress_emit\ncollectors\n_collector_runtime_ready","_progress_emit\ncollectors\nstart_loop"]],
[4608,"stop_collectors","","runtime_manager_stop_collectors","running_loops\nstop_loop\ndashboard collector:",0,["stop_loop\ndashboard collector:","running_loops\ndashboard collector:","running_loops\nstop_loop"]],
[4628,"stop_all","","runtime_manager_stop_all","stop_web\nstop_collectors",0,["stop_collectors","stop_web"]],
[4645,"stop_progress_tasks","","runtime_manager_stop_progress_tasks","running_loops\nstop_collector:",0,["stop_collector:","running_loops"]],
[4660,"restart_progress_tasks","","runtime_manager_restart_progress_tasks","stop_progress_tasks\nstart_collector:\nstart_web",0,["start_collector:\nstart_web","stop_progress_tasks\nstart_web","stop_progress_tasks\nstart_collector:"]],
[4677,"serve_all","","runtime_manager_serve_all","start_collectors\nstart_web\nstop_collectors",0,["start_web\nstop_collectors","start_collectors\nstop_collectors","start_collectors\nstart_web"]],
[4696,"restart_all","","runtime_manager_restart_all","stop_all\nstart_collectors\n_restart_web_with_retry",0,["start_collectors\n_restart_web_with_retry","stop_all\n_restart_web_with_retry","stop_all\nstart_collectors"]],
[4715,"_listener_socket_table_paths","","runtime_manager_listener_socket_table_paths","/proc/net/tcp\n/proc/net/tcp6",0,["","/proc/net/tcp"]],
[4730,"_process_fd_paths","","runtime_manager_process_fd_paths","glob '/proc/[0-9]*/fd/*'",0,[""]],
[4744,"_wait_for_port_release","","runtime_manager_wait_for_port_release","_listener_pids_for_port\nfor ( 1 .. 50 )\nsleep 0.1",0,["for ( 1 .. 50 )\nsleep 0.1","_listener_pids_for_port\nsleep 0.1","_listener_pids_for_port\nfor ( 1 .. 50 )"]],
[4761,"_progress_emit","","runtime_manager_progress_emit","ref(\$progress) ne 'CODE'\n\$progress->(\$event)",0,["\$progress->(\$event)","ref(\$progress) ne 'CODE'"]],
[4776,"_runtime_stability_polls","","runtime_manager_runtime_stability_polls","DEVELOPER_DASHBOARD_RUNTIME_STABILITY_POLLS\nDevel::Cover\nreturn 100",0,["Devel::Cover\nreturn 100","DEVELOPER_DASHBOARD_RUNTIME_STABILITY_POLLS\nreturn 100","DEVELOPER_DASHBOARD_RUNTIME_STABILITY_POLLS\nDevel::Cover"]],
[4792,"_runtime_confirmation_polls","","runtime_manager_runtime_confirmation_polls","DEVELOPER_DASHBOARD_RUNTIME_CONFIRMATION_POLLS\nreturn 3",0,["return 3","DEVELOPER_DASHBOARD_RUNTIME_CONFIRMATION_POLLS"]],
[4807,"_runtime_poll_interval","","runtime_manager_runtime_poll_interval","return 0.1",0,[""]],
[4821,"_port_accepting_connections","","runtime_manager_port_accepting_connections","IO::Socket::INET->new\nPeerAddr => '127.0.0.1'\nProto    => 'tcp'",0,["PeerAddr => '127.0.0.1'\nProto    => 'tcp'","IO::Socket::INET->new\nProto    => 'tcp'","IO::Socket::INET->new\nPeerAddr => '127.0.0.1'"]],
[4837,"_read_process_env_marker","","collector_runner_read_process_env_marker","/proc/\$pid/environ\nsplit /\\0/, \$env\nreturn \$2 if \$1 eq \$key",0,["split /\\0/, \$env\nreturn \$2 if \$1 eq \$key","/proc/\$pid/environ\nreturn \$2 if \$1 eq \$key","/proc/\$pid/environ\nsplit /\\0/, \$env"]],
[4853,"_read_process_title","","runtime_manager_read_process_title","/proc/\$pid/cmdline\nsystem 'ps', '-o', 'args=', '-p', \$pid",0,["system 'ps', '-o', 'args=', '-p', \$pid","/proc/\$pid/cmdline"]],
[4868,"_system_context","","page_runtime_system_context","cwd\nruntime_context\nparams",0,["runtime_context\nparams","cwd\nparams","cwd\nruntime_context"]],
[4884,"_noop_writer","","page_runtime_noop_writer","return ''",0,[""]],
[4898,"_looks_like_stream_disconnect_error","","page_runtime_stream_disconnect_error","__DD_AJAX_STREAM_DISCONNECTED__\nbroken pipe\nclosed handle",0,["broken pipe\nclosed handle","__DD_AJAX_STREAM_DISCONNECTED__\nclosed handle","__DD_AJAX_STREAM_DISCONNECTED__\nbroken pipe"]],
[4914,"_stream_sysread","","page_runtime_stream_sysread","sysread\n8192",0,[8192,"sysread"]],
[4929,"_saved_ajax_inline_env_limit","","page_runtime_saved_ajax_inline_env_limit","131_072",0,[""]],
[4943,"_cleanup_saved_ajax_temp_files","","page_runtime_cleanup_saved_ajax_temp_files","saved ajax temp file\nunlink \$path",0,["unlink \$path","saved ajax temp file"]],
[4958,"_normalize_saved_ajax_singleton","","page_runtime_normalize_saved_ajax_singleton","Invalid ajax singleton name\n[[:cntrl:]]",0,["[[:cntrl:]]","Invalid ajax singleton name"]],
[4973,"_kill_saved_ajax_singleton","","page_runtime_kill_saved_ajax_singleton","_quote_process_pattern_literal\n_pkill_perl",0,["_pkill_perl","_quote_process_pattern_literal"]],
[4989,"_quote_process_pattern_literal","","page_runtime_quote_process_pattern_literal","\\\\\$|(){}[]*+?",0,[""]],
[5003,"_query_string_from_params","","page_runtime_query_string_from_params","URI::Escape\njoin '&'",0,["join '&'","URI::Escape"]],
[5018,"_runtime_legacy_quote","","page_runtime_legacy_quote","\\\\\\\\\n\\\\'",0,["\\\\'","\\\\\\\\"]],
[5033,"_runtime_legacy_value","","page_runtime_legacy_value","ref(\$value) eq 'ARRAY'\nref(\$value) eq 'HASH'\n_runtime_legacy_quote",0,["ref(\$value) eq 'HASH'\n_runtime_legacy_quote","ref(\$value) eq 'ARRAY'\n_runtime_legacy_quote","ref(\$value) eq 'ARRAY'\nref(\$value) eq 'HASH'"]],
[5051,"_runtime_value_text","","page_runtime_value_text","ref(\$value) ne 'HASH' && ref(\$value) ne 'ARRAY'\n_runtime_legacy_value",0,["_runtime_legacy_value","ref(\$value) ne 'HASH' && ref(\$value) ne 'ARRAY'"]],
[5067,"_saved_ajax_command","","page_runtime_saved_ajax_command","Missing saved ajax file path\ncommand_argv_for_path\ncommand_in_path('python3')",0,["command_argv_for_path\ncommand_in_path('python3')","Missing saved ajax file path\ncommand_in_path('python3')","Missing saved ajax file path\ncommand_argv_for_path"]],
[5084,"_saved_ajax_env","","page_runtime_saved_ajax_env","DEVELOPER_DASHBOARD_AJAX_PARAMS\n_saved_ajax_inline_env_limit\n_runtime_local_perl_env",0,["_saved_ajax_inline_env_limit\n_runtime_local_perl_env","DEVELOPER_DASHBOARD_AJAX_PARAMS\n_runtime_local_perl_env","DEVELOPER_DASHBOARD_AJAX_PARAMS\n_saved_ajax_inline_env_limit"]],
[5105,"_runtime_local_perl_env","","page_runtime_local_perl_env","PERL5LIB\nruntime_local_lib_roots",0,["runtime_local_lib_roots","PERL5LIB"]],
[5120,"_saved_ajax_temp_file","","page_runtime_saved_ajax_temp_file","tempfile\nsaved ajax temp file",0,["saved ajax temp file","tempfile"]],
[5135,"_drain_saved_ajax_ready_handle","","page_runtime_drain_saved_ajax_ready_handle","_stream_sysread\nstdout_writer\nstderr_writer",0,["stdout_writer\nstderr_writer","_stream_sysread\nstderr_writer","_stream_sysread\nstdout_writer"]],
[5153,"_close_saved_ajax_streams","","page_runtime_close_saved_ajax_streams","select->can('handles')\nclose \$fh",0,["close \$fh","select->can('handles')"]],
[5168,"_terminate_saved_ajax_process","","page_runtime_terminate_saved_ajax_process","kill 15, \$pid\nkill 9, \$pid if kill 0, \$pid",0,["kill 9, \$pid if kill 0, \$pid","kill 15, \$pid"]],
[5183,"stash","","page_runtime_ajax_stash","\$AJAX_STASH\nno input",0,["no input","\$AJAX_STASH"]],
[5198,"hide","","page_runtime_ajax_hide","__DD_HIDE__\nstash(\$input) if ref(\$input) eq 'HASH'",0,["stash(\$input) if ref(\$input) eq 'HASH'","__DD_HIDE__"]],
[5214,"void","","page_runtime_ajax_void","stash(\$input) if defined \$input\nreturn",0,["return","stash(\$input) if defined \$input"]],
[5230,"stop","","page_runtime_ajax_stop","die defined \$message",0,[""]],
[5244,"params","","page_runtime_ajax_params","\$AJAX_PARAMS",0,[""]],
[5258,"_code_header","","page_runtime_code_header","my \@keys = grep\nmy (%s) = \@{ \$stash }{qw\n}",0,["my (%s) = \@{ \$stash }{qw\n}","my \@keys = grep"]],
[5273,"_destroy_sandpit","","page_runtime_destroy_sandpit","no strict 'refs'\n%{\"\${stash}::\"} = ()",0,["%{\"\${stash}::\"} = ()","no strict 'refs'"]],
[5288,"_quote_process_pattern_literal","","page_runtime_quote_process_pattern_literal","\\.^\$|(){}\\[\\]*+?",0,[""]],
[5302,"_saved_ajax_perl_wrapper","","page_runtime_saved_ajax_perl_wrapper","DEVELOPER_DASHBOARD_AJAX_PARAMS_FILE\ndashboard ajax:\neval \"{ \$code }\"",0,["dashboard ajax:\neval \"{ \$code }\"","DEVELOPER_DASHBOARD_AJAX_PARAMS_FILE\neval \"{ \$code }\"","DEVELOPER_DASHBOARD_AJAX_PARAMS_FILE\ndashboard ajax:"]],
[5318,"__add_error","","page_runtime_sandpit_add_error","push \\\@errors\ndefined \\\$_ && \\\$_ ne ''",0,["defined \\\$_ && \\\$_ ne ''","push \\\@errors"]],
[5333,"__errors","","page_runtime_sandpit_errors","my \\\@copy = \\\@errors\n\\\@errors = ()",0,["\\\@errors = ()","my \\\@copy = \\\@errors"]],
[5348,"__initial_context","","page_runtime_sandpit_initial_context","\\\$stash = \\\$next_stash || {}\n\\\$runtime = \\\$next_runtime || {}",0,["\\\$runtime = \\\$next_runtime || {}","\\\$stash = \\\$next_stash || {}"]],
[5363,"__run_code","","page_runtime_sandpit_run_code","my \\\@result = eval \"{\\\$code}\"\n__add_error",0,["__add_error","my \\\@result = eval \"{\\\$code}\""]],
[5379,"_new_sandpit","","page_runtime_new_sandpit","Sandpit\n__initial_context\nUnable to setup sandpit",0,["__initial_context\nUnable to setup sandpit","Sandpit\nUnable to setup sandpit","Sandpit\n__initial_context"]],
[5395,"_run_single_block","","page_runtime_run_single_block","Folder->configure\n_new_sandpit\n_code_header\n__run_code\n__errors",0,["_new_sandpit\n_code_header\n__run_code\n__errors","Folder->configure\n_code_header\n__run_code\n__errors","Folder->configure\n_new_sandpit\n__run_code\n__errors","Folder->configure\n_new_sandpit\n_code_header\n__errors","Folder->configure\n_new_sandpit\n_code_header\n__run_code"]],
[5416,"stream_code_block","","page_runtime_stream_code_block","StreamHandle\n_new_sandpit\n__run_code\nreturn_writer",0,["_new_sandpit\n__run_code\nreturn_writer","StreamHandle\n__run_code\nreturn_writer","StreamHandle\n_new_sandpit\nreturn_writer","StreamHandle\n_new_sandpit\n__run_code"]],
[5438,"stream_saved_ajax_file","","page_runtime_stream_saved_ajax_file","open3\n_saved_ajax_command\n_saved_ajax_env\n_drain_saved_ajax_ready_handle",0,["_saved_ajax_command\n_saved_ajax_env\n_drain_saved_ajax_ready_handle","open3\n_saved_ajax_env\n_drain_saved_ajax_ready_handle","open3\n_saved_ajax_command\n_drain_saved_ajax_ready_handle","open3\n_saved_ajax_command\n_saved_ajax_env"]],
[5465,"run_code_blocks","","page_runtime_run_code_blocks","_new_sandpit\n_run_single_block\n_runtime_value_text\n_destroy_sandpit",0,["_run_single_block\n_runtime_value_text\n_destroy_sandpit","_new_sandpit\n_runtime_value_text\n_destroy_sandpit","_new_sandpit\n_run_single_block\n_destroy_sandpit","_new_sandpit\n_run_single_block\n_runtime_value_text"]],
[5486,"_render_templates","","page_runtime_render_templates","Template->new\n_system_context\n_run_single_block\nruntime_errors",0,["_system_context\n_run_single_block\nruntime_errors","Template->new\n_run_single_block\nruntime_errors","Template->new\n_system_context\nruntime_errors","Template->new\n_system_context\n_run_single_block"]],
[5505,"prepare_page","","page_runtime_prepare_page","run_code_blocks\n_render_templates\nruntime_outputs",0,["_render_templates\nruntime_outputs","run_code_blocks\nruntime_outputs","run_code_blocks\n_render_templates"]],
[5523,"_status_prefix","","progress_status_prefix","return '[OK]' if defined \$status && \$status eq 'done';\nreturn '->'   if defined \$status && \$status eq 'running';\nreturn '[X]'  if defined \$status && \$status eq 'failed';\nreturn '[ ]';",0,["return '->'   if defined \$status && \$status eq 'running';\nreturn '[X]'  if defined \$status && \$status eq 'failed';\nreturn '[ ]';","return '[OK]' if defined \$status && \$status eq 'done';\nreturn '[X]'  if defined \$status && \$status eq 'failed';\nreturn '[ ]';","return '[OK]' if defined \$status && \$status eq 'done';\nreturn '->'   if defined \$status && \$status eq 'running';\nreturn '[ ]';","return '[OK]' if defined \$status && \$status eq 'done';\nreturn '->'   if defined \$status && \$status eq 'running';\nreturn '[X]'  if defined \$status && \$status eq 'failed';"]],
[5539,"_colorize","","progress_colorize","return \$text if !\$self->{color};\n\\e[32m\$text\\e[0m\n\\e[34m\$text\\e[0m\n\\e[31m\$text\\e[0m",0,["\\e[32m\$text\\e[0m\n\\e[34m\$text\\e[0m\n\\e[31m\$text\\e[0m","return \$text if !\$self->{color};\n\\e[34m\$text\\e[0m\n\\e[31m\$text\\e[0m","return \$text if !\$self->{color};\n\\e[32m\$text\\e[0m\n\\e[31m\$text\\e[0m","return \$text if !\$self->{color};\n\\e[32m\$text\\e[0m\n\\e[34m\$text\\e[0m"]],
[5555,"render_text","","progress_render_text","my \@lines = (\$self->{title});\n\$self->_status_prefix\n\$self->_colorize\nreturn join( \"\\n\", \@lines ) . \"\\n\";",0,["\$self->_status_prefix\n\$self->_colorize\nreturn join( \"\\n\", \@lines ) . \"\\n\";","my \@lines = (\$self->{title});\n\$self->_colorize\nreturn join( \"\\n\", \@lines ) . \"\\n\";","my \@lines = (\$self->{title});\n\$self->_status_prefix\nreturn join( \"\\n\", \@lines ) . \"\\n\";","my \@lines = (\$self->{title});\n\$self->_status_prefix\n\$self->_colorize"]],
[5573,"render","","progress_render","my \$board  = \$self->render_text;\nif (\$self->{dynamic} && \$self->{rendered})\nprint {\$stream} \"\\e[1A\\e[2K\";\nprint {\$stream} \$board;\n\$self->{rendered} = 1;",0,["if (\$self->{dynamic} && \$self->{rendered})\nprint {\$stream} \"\\e[1A\\e[2K\";\nprint {\$stream} \$board;\n\$self->{rendered} = 1;","my \$board  = \$self->render_text;\nprint {\$stream} \"\\e[1A\\e[2K\";\nprint {\$stream} \$board;\n\$self->{rendered} = 1;","my \$board  = \$self->render_text;\nif (\$self->{dynamic} && \$self->{rendered})\nprint {\$stream} \$board;\n\$self->{rendered} = 1;","my \$board  = \$self->render_text;\nif (\$self->{dynamic} && \$self->{rendered})\nprint {\$stream} \"\\e[1A\\e[2K\";\n\$self->{rendered} = 1;","my \$board  = \$self->render_text;\nif (\$self->{dynamic} && \$self->{rendered})\nprint {\$stream} \"\\e[1A\\e[2K\";\nprint {\$stream} \$board;"]],
[5591,"update","","progress_update","return 1 if !\$event || ref(\$event) ne 'HASH';\nmy \$id = \$event->{task_id} || return 1;\n\$self->render;",0,["my \$id = \$event->{task_id} || return 1;\n\$self->render;","return 1 if !\$event || ref(\$event) ne 'HASH';\n\$self->render;","return 1 if !\$event || ref(\$event) ne 'HASH';\nmy \$id = \$event->{task_id} || return 1;"]],
[5607,"callback","","progress_callback","return sub {\n\$self->update(\$event);\n}",0,["\$self->update(\$event);","return sub {\n}"]],
[5622,"finish","","progress_finish","return 1 if !\$self->{dynamic} || !\$self->{rendered};\nprint {\$stream} \"\\n\";",0,["print {\$stream} \"\\n\";","return 1 if !\$self->{dynamic} || !\$self->{rendered};"]],
[5636,"new","","progress_new","Progress tasks must be an array reference\nProgress task missing id\n\$self->render;\ntitle    => \$args{title} || 'dashboard progress'",0,["Progress task missing id\n\$self->render;\ntitle    => \$args{title} || 'dashboard progress'","Progress tasks must be an array reference\n\$self->render;\ntitle    => \$args{title} || 'dashboard progress'","Progress tasks must be an array reference\nProgress task missing id\ntitle    => \$args{title} || 'dashboard progress'","Progress tasks must be an array reference\nProgress task missing id\n\$self->render;"]],
[5655,"_now_iso8601","","action_now_iso8601","gmtime\nstrftime\n%Y-%m-%dT%H:%M:%SZ",0,["strftime\n%Y-%m-%dT%H:%M:%SZ","gmtime\n%Y-%m-%dT%H:%M:%SZ","gmtime\nstrftime"]],
[5670,"_is_action_trusted","","action_is_trusted","allow_untrusted_actions\ntrusted_actions\nreturn 1 if \$action->{safe}",0,["trusted_actions\nreturn 1 if \$action->{safe}","return 1 if \$action->{safe}","allow_untrusted_actions\ntrusted_actions"]],
[5685,"_run_builtin_action","","action_run_builtin","page.source\npage.state\npaths.list",0,["page.state\npaths.list","page.source\npaths.list","page.source\npage.state"]],
[5700,"encode_action_payload","","action_encode_payload","trusted_id\nsha256_hex\nencode_payload",0,["sha256_hex\nencode_payload","trusted_id\nencode_payload","trusted_id\nsha256_hex"]],
[5715,"decode_action_payload","","action_decode_payload","json_decode\ndecode_payload\nAction payload must be a hash",0,["decode_payload\nAction payload must be a hash","json_decode\nAction payload must be a hash","json_decode\ndecode_payload"]],
[5730,"run_encoded_action","","action_run_encoded","PageDocument\nfrom_instruction\nrun_page_action\nCommand actions cannot be executed through an encoded action token\nsource => 'transient'",0,["from_instruction\nrun_page_action\nCommand actions cannot be executed through an encoded action token\nsource => 'transient'","PageDocument\nrun_page_action\nCommand actions cannot be executed through an encoded action token\nsource => 'transient'","PageDocument\nfrom_instruction\nCommand actions cannot be executed through an encoded action token\nsource => 'transient'","PageDocument\nfrom_instruction\nrun_page_action\nsource => 'transient'","PageDocument\nfrom_instruction\nrun_page_action\nCommand actions cannot be executed through an encoded action token"]],
[5748,"run_page_action","","action_run_page_action","_run_builtin_action\nrun_command_action\n_is_action_trusted",0,["run_command_action\n_is_action_trusted","_run_builtin_action\n_is_action_trusted","_run_builtin_action\nrun_command_action"]],
[5766,"run_command_action","","action_run_command_action","Unable to fork background action\ndashboard_log\n_run_command",0,["dashboard_log\n_run_command","Unable to fork background action\n_run_command","Unable to fork background action\ndashboard_log"]],
[5783,"_run_command","","action_run_command","__ACTION_TIMEOUT__\nshell_command_argv\nstarted_at=>_now_iso8601",0,["shell_command_argv\nstarted_at=>_now_iso8601","__ACTION_TIMEOUT__\nstarted_at=>_now_iso8601","__ACTION_TIMEOUT__\nshell_command_argv"]],
[5799,"_iso8601_after","","utc_iso8601_after","time +\ngmtime(\$epoch)\n%Y-%m-%dT%H:%M:%SZ",0,["gmtime(\$epoch)\n%Y-%m-%dT%H:%M:%SZ","time +\n%Y-%m-%dT%H:%M:%SZ","time +\ngmtime(\$epoch)"]],
[5814,"_iso8601_to_epoch","","utc_iso8601_to_epoch","Time::Local\ntimegm\nT(\\d{2}):(\\d{2}):(\\d{2})Z",0,["timegm\nT(\\d{2}):(\\d{2}):(\\d{2})Z","Time::Local\nT(\\d{2}):(\\d{2}):(\\d{2})Z","Time::Local\ntimegm"]],
[5829,"_iso8601_to_epoch","","iso8601_to_epoch_with_zone","Z|[+-]\\d{4}|[+-]\\d{2}:\\d{2}\nUnsupported collector log timestamp\ntimegm",0,["Unsupported collector log timestamp\ntimegm","Z|[+-]\\d{4}|[+-]\\d{2}:\\d{2}\ntimegm","Z|[+-]\\d{4}|[+-]\\d{2}:\\d{2}\nUnsupported collector log timestamp"]],
[5844,"_with_trailing_newline","","text_with_trailing_newline","return \$text =~ /\\n\\z/ ? \$text : \$text . \"\\n\";",0,[""]],
[5857,"_slurp","","fs_slurp","return '' if !-f \$file;\nUnable to read \$file",0,["Unable to read \$file","return '' if !-f \$file;"]],
[5871,"_atomic_write_text","","fs_atomic_write_text","\$tmp = \"\$file.pending\"\nrename \$tmp, \$file\nsecure_file_permissions",0,["rename \$tmp, \$file\nsecure_file_permissions","\$tmp = \"\$file.pending\"\nsecure_file_permissions","\$tmp = \"\$file.pending\"\nrename \$tmp, \$file"]],
[5886,"_atomic_write_json","","fs_atomic_write_json","json_encode\n_atomic_write_text",0,["_atomic_write_text","json_encode"]],
[5901,"_now_iso8601","","local_iso8601_now","localtime\nstrftime\n%Y-%m-%dT%H:%M:%S%z",0,["strftime\n%Y-%m-%dT%H:%M:%S%z","localtime\n%Y-%m-%dT%H:%M:%S%z","localtime\nstrftime"]],
[5916,"new_from_all_folders","","collector_new_from_all_folders","require PathRegistry;\nnew_from_all_folders",0,["new_from_all_folders","require PathRegistry;"]],
[5930,"collector_paths","","collector_paths","collector_dir\nstatus.json\njob.json",0,["status.json\njob.json","collector_dir\njob.json","collector_dir\nstatus.json"]],
[5945,"write_job","","collector_write_job","collector_paths\n_atomic_write_json\n\$paths->{job}",0,["_atomic_write_json\n\$paths->{job}","collector_paths\n\$paths->{job}","collector_paths\n_atomic_write_json"]],
[5962,"_collector_file_candidates","","collector_file_candidates","collectors_roots\nFile::Spec->catfile",0,["File::Spec->catfile","collectors_roots"]],
[5976,"read_job","","collector_read_job","_collector_file_candidates\njson_decode\njob.json",0,["json_decode\njob.json","_collector_file_candidates\njob.json","_collector_file_candidates\njson_decode"]],
[5992,"read_status","","collector_read_status","_collector_file_candidates\neval { json_decode(\$raw) }\nstatus.json",0,["eval { json_decode(\$raw) }\nstatus.json","_collector_file_candidates\nstatus.json","_collector_file_candidates\neval { json_decode(\$raw) }"]],);

my $root = tempdir('pax-cov-cucb-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# _run($name, $package, $body)
# Builds a tiny module source containing one sub and runs the simple-transform matcher on it.
# Input: sub name, package name, sub body text. Output: the compiled record or undef (always one scalar).
sub _run {
    my ($name, $package, $body) = @_;
    my $source = "package $package;\nuse strict;\nsub $name {\n$body\n}\n1;\n";
    my $record = PAX::CodeUnitCompiler::_compile_simple_transform_sub_from_source($source, $name, $package . "::" . $name);
    return $record;
}

# _is_miss($record, $op)
# True when the record does not claim the given op.
# Input: record or undef and the op name. Output: boolean.
sub _is_miss {
    my ($record, $op) = @_;
    return !defined($record) || ($record->{op} // '') ne $op;
}

for my $row (@rows) {
    my ($line, $name, $tail, $op, $body, $namere, $drops) = @$row;
    my $package = $tail eq '' ? 'Cov::App' : "Cov::App::$tail";
    my $filler = "my \$zz = 0;";

    my $hit = _run($name, $package, $body);
    is($hit && $hit->{op}, $op, "recogniser line $line ($op) matches");

    ok(_is_miss(_run($namere ? 'zzz_other' : $name . '_x', $package, $body), $op), "line $line: wrong sub name misses");
    if ($tail ne '') {
        ok(_is_miss(_run($name, 'Cov::Other::Zed', $body), $op), "line $line: wrong package misses");
    }
    for my $i (0 .. $#$drops) {
        ok(_is_miss(_run($name, $package, $drops->[$i] . "\n" . $filler), $op), "line $line: missing evidence $i misses");
    }
}

done_testing;
