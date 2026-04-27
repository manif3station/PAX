package PAX;

use strict;
use warnings;

our $VERSION = '0.010';

1;

__END__

=head1 NAME

PAX - Perl Adaptive eXecution compiler and standalone binary packager

=head1 VERSION

Current release version is kept in C<our $VERSION> in this module and mirrored
to every C<lib/PAX/*.pm> module before release.

=head1 SYNOPSIS

  perl bin/pax help
  perl bin/pax build
  perl bin/pax build -o ./build/my-app bin/my-app
  perl bin/pax run -- version
  perl bin/pax run bin/my-app -- version

=head1 DESCRIPTION

PAX turns a Perl entrypoint plus its repeatable build inputs into a standalone
executable. The executable can include compiled code units, native artifacts
where supported, asset payloads, dependency payloads, and a runtime launcher.

The project is deliberately neutral. Core compiler, packaging, loader, runtime,
and dispatch code must not embed assumptions about one application, company, or
module namespace.

=head1 INTRODUCTION

PAX exists to change the deployment shape of a Perl application.

Without PAX, a Perl application commonly depends on some mix of the original
source tree, a host Perl installation, host CPAN modules, asset directories
next to the app, and local bootstrap scripts or container images that carry the
whole working tree.

PAX aims to turn that into one executable that can carry compiled code units,
runtime payloads, embedded assets, and native artifacts where a region can be
proven safe to specialize.

The goal is not to pretend every Perl feature can become a native binary with
no trade-offs. The real goal is:

=over 4

=item *

keep Perl correctness

=item *

keep fallback execution explicit

=item *

package applications into one binary

=item *

move eligible hot paths toward native speed

=item *

stay neutral across arbitrary Perl projects

=back

=head1 WHAT YOU GET

=over 4

=item *

one public command surface with C<pax build> and C<pax run>

=item *

a repeatable build contract through C<paxfile.yml>

=item *

one standalone executable output

=item *

embedded asset packaging for web applications and static payloads

=item *

runtime payload packaging for source-tree-free execution

=item *

self-hosted build capability, including building C<bin/pax> itself

=item *

Docker-friendly multi-stage packaging

=back

=head1 MAIN CONCEPTS

=head2 Public Facade

C<PAX::CLI> owns the public operator contract behind C<pax build> and
C<pax run>.

=head2 Manifest Loading

C<PAX::Paxfile> loads repeatable build inputs from C<paxfile.yml>.

=head2 Standalone Image Builder

C<PAX::StandaloneImage> collects dependencies, packages runtime payloads,
embeds assets, and writes the standalone launcher.

=head2 Code Unit Compilation

C<PAX::CodeUnitCompiler> lowers supported Perl source shapes into PAX code unit
records. Unsupported regions remain on explicit fallback paths instead of being
silently miscompiled.

=head2 Packaged Runtime

C<PAX::StandaloneRuntime> provides the packaged helper runtime used after the
standalone executable starts.

=head2 Native Dispatch

C<PAX::StandaloneDispatch> and related runtime pieces execute packaged native
regions and deopt fallback behavior under the standalone model.

=head1 SOW-03 PUBLIC COMMAND SURFACE

PAX exposes only two public commands through C<bin/pax>:

=over 4

=item * C<build>

Compile and package the source tree behind an entrypoint into one standalone
executable.

=item * C<run>

Run the same build flow and then execute the resulting binary with arguments
after C<-->.

=back

The canonical usage is:

  pax build ...
  pax run ...

Internal diagnostics and validation modules remain available as Perl APIs for
the test suite and release gates. They are not public C<bin/pax> subcommands.

=head1 PAXFILE CONTRACT

When no positional entrypoint is supplied, C<build> and C<run> read
C<paxfile.yml> by default. C<--paxfile> selects a different manifest and
C<--no-paxfile> disables manifest loading.

Supported manifest keys:

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

=item * C<app_name>, C<app_namespace>, C<app_entrypoint_env>, C<app_entrypoint_fallback>, C<app_command>

=back

CLI flags override file values. Output path precedence is:

=over 4

=item 1. C<--output> / C<-o>

=item 2. C<paxfile.yml> C<output>

=item 3. C<.pax/standalone/<name>/<name>>

=back

=head1 MANUAL

=head2 Installation

For development from a repository checkout:

  cpanm --installdeps .
  perl bin/pax help

For release packaging:

  cpanm Dist::Zilla

=head2 First Build

The simplest workflow is a local C<paxfile.yml>:

  name: example-app
  entrypoint: bin/example-app
  output: build/example-app
  libs:
    - lib
  cpanfiles:
    - cpanfile
  runtime_mode: bundled_perl

Then build:

  perl bin/pax build

And run the result directly:

  ./build/example-app

=head2 Build Without paxfile.yml

When the CLI provides the required shape, C<paxfile.yml> is optional:

  perl bin/pax build -o ./build/example-app bin/example-app

=head2 Self Compile

PAX can build itself:

  perl bin/pax build -o /tmp/pax bin/pax
  /tmp/pax help

That self-built binary can then build another standalone application from its
own C<paxfile.yml>.

=head1 ARCHITECTURE

=head2 Entrypoint and Build Configuration

C<PAX::CLI> is a small public facade. It resolves C<build> and C<run> inputs
from CLI arguments plus C<PAX::Paxfile>, then delegates to the standalone image
builder.

=head2 Compilation and Code Units

C<PAX::CodeUnitCompiler> compiles supported Perl source shapes into PCU records.
Unsupported or partially supported module shapes use hybrid or fallback payloads
so correctness is preserved while reusable compiler support expands.

=head2 Dependency Discovery

C<PAX::StandaloneImage> follows entrypoints, library directories, source roots,
and C<cpanfile> inputs to collect application modules and dependency payloads.
The mechanism is structural and path/module based, not tied to a project name.

=head2 Asset Embedding

Individual assets and asset directories are embedded into the executable payload.
The generated runtime extracts them into a private runtime directory and exposes
that location to the packaged program.

=head2 Native and Fallback Dispatch

PAX can package native artifacts for supported hot regions. Runtime dispatch
uses native execution when assumptions hold and falls back to bundled Perl
payloads when they do not.

=head2 Standalone Launcher

The final output is an executable launcher containing package metadata, code
units, dependency payloads, optional native artifacts, assets, and runtime helper
code.

=head1 EXAMPLES

Build from C<paxfile.yml>:

  perl bin/pax build

Build a specific entrypoint:

  perl bin/pax build -o ./build/example bin/example

Run after building:

  perl bin/pax run -- status

Embed application assets:

  perl bin/pax build \
    --name webapp \
    --lib lib \
    --source-root lib \
    --asset-dir share \
    --cpanfile cpanfile \
    --runtime-mode bundled_perl \
    --output ./build/webapp \
    bin/webapp

Build PAX itself:

  perl bin/pax build -o /tmp/pax bin/pax
  /tmp/pax help

=head2 Web Applications

PAX supports the single-binary packaging shape for framework applications that
combine Perl modules, PSGI or web framework code, templates, CSS, JavaScript,
and other static assets.

The validated SOW-03 proof includes a Dancer2 + Plack/Starman + Template
Toolkit web application packaged as one executable.

=head1 DOCKER DEPLOYMENT MODEL

PAX supports a minimal multi-stage image pattern:

  FROM perl:5.42 AS builder
  WORKDIR /workspace
  COPY . /workspace
  RUN cpanm --installdeps .
  RUN perl bin/pax build --output /out/app

  FROM debian:bookworm-slim
  COPY --from=builder /out/app /usr/local/bin/app
  CMD ["/usr/local/bin/app"]

The final image contains only the executable. The source tree, assets, cpanfile,
and framework installation are builder-stage inputs.

For an external application, the validated packaging pattern is:

=over 4

=item 1.

build a standalone C<pax> binary

=item 2.

copy that C<pax> binary into the application build stage

=item 3.

compile the application into its own standalone binary

=item 4.

copy only that final binary into the runtime stage

=back

=head1 ADAPTIVE COMPILATION RULE

When a module or framework fails under PAX, fixes should improve a reusable
compiler, packaging, loader, or runtime path for arbitrary modules of the same
class. A project-specific branch is not complete when a neutral generalized
implementation is locally actionable.

=head1 RELEASE GATES

Release readiness requires:

=over 4

=item * C<Changes>, C<README.md>, C<cpanfile>, C<dist.ini>, and C<lib/PAX.pm>.

=item * canonical version synchronization across all PAX modules.

=item * POD and README parity for public behavior.

=item * C<make test>.

=item * C<make release-gate>.

=item * C<make cpan-build> and C<make cpan-gate>.

=back

C<cpan-gate> also verifies that release tarballs and the git index exclude
temporary probes, generated workspaces, planning artifacts, and other
non-release paths.

C<make cpan-dist> and C<make cpan-build> bump the distribution version by
C<0.001> before running C<dzil build>. The release flow then enforces a version
gate, a C<Changes> gate, and a documentation gate for C<README.md> plus this
module POD before building the tarball.

=head1 TESTING AND COVERAGE

Primary validation from a repository checkout is:

  make test
  make release-gate
  make cpan-gate

=head1 KNOWN LIMITATIONS

=over 4

=item * Dynamic loading and runtime mutation can require fallback paths.

=item * Native speed depends on region selection and guard validity.

=item * Bundled runtime executables are larger than wrappers because they carry
runtime payloads needed to run without the source tree.

=item * Docker validation requires local Docker access.

=back

=head1 FAQ

=head2 Is PAX tied to one specific project?

No. Example applications are validation corpora. Core compiler and runtime
logic are expected to stay neutral and reusable.

=head2 Does PAX guarantee Rust-like speed for all Perl code?

No. PAX packages the whole application correctly and accelerates hot paths that
it can safely specialize. Dynamic regions continue to use fallback execution.

=head2 Does pax run require a separate app server?

No. Under SOW-03, C<pax run> builds the standalone executable and then executes
that binary directly.

=head2 Can PAX package web applications with embedded static assets?

Yes. The validated packaging path includes templates, CSS, JavaScript, and
framework code embedded into one standalone executable.

=head1 FILES

=over 4

=item * C<bin/pax> - public command entrypoint.

=item * C<lib/PAX/> - compiler, packaging, runtime, and validation modules.

=item * C<paxfile.yml> - neutral build manifest.

=item * C<README.md> - operator documentation.

=item * C<Changes>, C<cpanfile>, C<dist.ini> - release metadata.

=back

=head1 SEE ALSO

The repository C<README.md> mirrors the public command contract and operator
workflow documented here.

The internal documentation rule for DD-style parity is recorded in
F<docs/pax-doc-parity.md>.

=cut
