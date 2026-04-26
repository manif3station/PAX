package PAX;

use strict;
use warnings;

our $VERSION = '0.003';

1;

__END__

=head1 NAME

PAX - Perl Adaptive eXecution compiler + packager

=head1 VERSION

Current release version is kept in C<our $VERSION> in this module and mirrored to
all C<lib/PAX/*.pm> modules before release.

=head1 DESCRIPTION

PAX is a reusable Perl performance and packaging toolchain:

=over 4

=item * compile selected runtime regions into native units
=item * package compiled units and assets into repeatable artifacts
=item * provide CLI dispatch and diagnostics for mixed fallback/native execution
=item * produce standalone server and app launch models suitable for deployment

=back

The project target is explicit neutrality: behavior must be reusable across arbitrary
Perl applications and not coupled to any single module name or company codebase.

=head1 DESIGN GOALS (SOW-03)

=over 4

=item * start from one Perl entrypoint and follow dependencies through capture and analysis
=item * produce deployable outputs with no hard-coded application assumptions
=item * compile and embed as much runtime behavior as possible while preserving fallback safety
=item * keep project-specific hacks out of core compiler/runtime paths
=item * make C<pax build> and C<pax run> the primary standalone binary workflow
=item * read repeatable build inputs from C<paxfile.yml> when CLI arguments are omitted

=back

=head1 ARCHITECTURE

=head2 1) Capture and manifests

PAX captures runtime/compile observations from an entrypoint and emits a manifest.
The manifest is used by inspection, compatibility checks, and compilation planning.

Primary diagnostic commands:

=over 4

=item * C<capture>
=item * C<inspect>
=item * C<hir>

=back

=head2 2) Analysis and code units

Selected regions are lowered, converted into guarded SSA, and passed to code generation.

Primary commands:

=over 4

=item * C<compile>
=item * C<diff>

=back

=head2 3) Runtime dispatch

Execution uses a staged fallback strategy:

=over 4

=item * native artifact when safe and available
=item * guarded execution when assumptions hold
=item * source fallback when required

=back

Commands:

=over 4

=item * C<dispatch>, C<run-native>
=item * C<why-not>, C<trace-guards>

=back

=head2 4) Packaging

The primary packaging workflow is:

=over 4

=item * C<build> to compile a standalone executable binary

=item * C<run> to build the same standalone executable and run it with arguments after C<-->

=back

Advanced C<app-*> and C<standalone-*> commands remain available for development and
inspection. The public SOW-03 path is C<build> / C<run>. Standalone artifacts support
asset embedding, code unit packaging, and command-level argument forwarding.

=head1 CLI SURFACE

Use:

  perl bin/pax help

The canonical usage list is emitted by the command runner. Primary commands:

=over 4

=item * C<build>
=item * C<run>

=back

Advanced commands include:

=over 4

=item * C<capture>, C<inspect>, C<hir>, C<compile>, C<diff>
=item * C<bench>, C<bench-matrix>, C<run-native>, C<dispatch>
=item * C<profile>, C<why-not>, C<trace-guards>, C<gatekeeper>
=item * C<app-build>, C<app-start>, C<app-run>, C<app-stop>
=item * C<standalone-build>, C<standalone-run>, C<standalone-inspect>, C<standalone-extract>, C<standalone-why-not>, C<standalone-native-run>
=item * C<cpan-matrix>, C<core-suite>, C<corpus>

=back

Common options:

=over 4

=item * C<--name>, C<--paxfile>, C<--no-paxfile>
=item * C<--lib>, C<--source-root>, C<--asset>, C<--asset-dir>
=item * C<--cpanfile> (standalone)
=item * C<--runtime-mode> (standalone)
=item * C<--output> / C<-o> (build/run standalone output, optional: overrides C<paxfile.yml>)
=item * C<--compact> for compact JSON output

=back

=head1 PAXFILE SUPPORT

By default, C<build>, C<run>, app builders, and standalone builders read C<paxfile.yml>. Supported keys:

=over 4

=item * C<name>
=item * C<entrypoint>
=item * C<libs>
=item * C<source_roots>
=item * C<assets>
=item * C<asset_dirs>
=item * C<cpanfiles>
=item * C<output>
=item * C<runtime_mode>
=item * C<app_name>, C<app_namespace>
=item * C<app_entrypoint_env>, C<app_entrypoint_fallback>, C<app_command>

=back

CLI flags override paxfile entries. Omitting file is allowed; C<--no-paxfile> disables file reads.

For C<build>, C<run>, and C<standalone-build>, output path follows this precedence: CLI option, then C<paxfile.yml> C<output>, then the fallback C<./.pax/standalone/<name>/<name>>.

=head1 SOW-03 EXAMPLES

Build using C<paxfile.yml>:

  perl bin/pax build

Build to an explicit output path:

  perl bin/pax build -o ./bin/my-app

Build and run, passing arguments to the executable:

  perl bin/pax run -- version
  perl bin/pax run --output ./bin/my-app -- version

=head1 ENVIRONMENT

Runtime and build defaults support these variables:

=over 4

=item * C<PAX_APP_ROOT> (default C<.pax/apps>)
=item * C<PAX_STANDALONE_ROOT> (default C<.pax/standalone>)
=item * C<PAX_CODE_UNIT_CAPTURE_TIMEOUT>
=item * C<PAX_CODE_UNIT_MAX_CAPTURE_SUBS>
=item * C<PAX_CODE_UNIT_MAX_CAPTURE_BYTES>

=back

=head1 CPAN GATE

Distribution gates require:

=over 4

=item * C<Changes>, C<README.md>, C<cpanfile>, C<dist.ini>, C<lib/PAX.pm> present
=item * canonical version sync through all PAX modules
=item * comprehensive module POD in C<lib/PAX.pm>, aligned with C<README.md>
=item * CPAN targets in C<Makefile>: C<cpan-dist>, C<cpan-build>, C<cpan-release>
=item * release tarball produced via C<make cpan-build> and stale artifacts removed

=back

Run the gate:

  make cpan-bump-version VERSION=0.004
  make cpan-build

=head1 KNOWN LIMITATIONS

=over 4

=item * Runtime behavior and speed depend on workload shape and successful region selection.
=item * Dynamic module loading paths may stay in source fallback when they are not statically discoverable.
=item * Standalone launcher generation depends on local compiler availability.

=back

=head1 FILES

=over 4

=item * C<Changes> — changelog
=item * C<README.md> — user and operator docs
=item * C<cpanfile> — dependency source of truth
=item * C<dist.ini> — Dist::Zilla config
=item * C<bin/pax> — command entrypoint
=item * C<lib/PAX/*> — compiler/runtime modules
=item * C<paxfile.yml> — project build defaults

=back

=head1 SEE ALSO

L</README.md>, and SOW documents in repository root.

=cut
