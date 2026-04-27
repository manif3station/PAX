# PAX

**PAX** is a Perl-native adaptive compiler and standalone binary packager.

The public command surface is intentionally small:

```bash
perl bin/pax help
perl bin/pax build
perl bin/pax run
```

Everything else in the repository is compiler/runtime implementation, test
coverage, or release tooling. Users should not call internal diagnostic
subcommands through `bin/pax`.

## Goals

- Build one executable from a Perl entrypoint.
- Read repeatable build inputs from `paxfile.yml`.
- Let CLI arguments override `paxfile.yml`.
- Embed assets and dependency payloads into the executable.
- Keep PAX neutral: no project-specific package names in compiler, loader, or runtime logic.
- Preserve correctness with fallback paths while compiling supported code units and native regions.

## Quick Start

Build from a local `paxfile.yml`:

```bash
perl bin/pax build
```

Build an explicit entrypoint:

```bash
perl bin/pax build bin/my-app
```

Build to a specific output path:

```bash
perl bin/pax build -o ./build/my-app bin/my-app
perl bin/pax build --output ./build/my-app bin/my-app
```

Build and immediately run:

```bash
perl bin/pax run -- version
perl bin/pax run bin/my-app -- version
```

`pax run` uses the same build inputs as `pax build`, writes or refreshes the
standalone executable, and then executes that binary with arguments after `--`.

## CLI Contract

```text
usage:
  pax build ...
  pax run ...
```

Public commands:

- `build`: compile/package the source tree behind an entrypoint into one executable.
- `run`: build the executable, then run it.

Common options:

- `--paxfile`: read defaults from a manifest path; default is `paxfile.yml`.
- `--no-paxfile`: ignore manifest defaults.
- `--name`: artifact name.
- `--lib`: application library path; repeatable.
- `--source-root`: source tree to scan/package; repeatable.
- `--cpanfile`: dependency policy/source file; repeatable.
- `--asset`: individual asset file to embed; repeatable.
- `--asset-dir`: asset directory to embed recursively; repeatable.
- `--output` / `-o`: executable output path.
- `--runtime-mode`: runtime strategy, typically `bundled_perl` or `host_perl`.
- `--compact`: compact JSON build output.

## `paxfile.yml`

With no positional entrypoint, `pax build` and `pax run` read `paxfile.yml`.
CLI flags override file values.

Example:

```yaml
name: example-app
entrypoint: bin/example-app
output: build/example-app
libs:
  - lib
source_roots:
  - lib
assets:
  - share/banner.txt
asset_dirs:
  - share/public
cpanfiles:
  - cpanfile
runtime_mode: bundled_perl
```

Output path precedence:

1. CLI `--output` / `-o`
2. `paxfile.yml` `output`
3. fallback `.pax/standalone/<name>/<name>`

## Asset Embedding

Assets are copied into the executable payload and extracted into a private
runtime directory when the binary starts. Framework code can read them through
the embedded asset root prepared by the PAX runtime.

Example:

```bash
perl bin/pax build \
  --name webapp \
  --lib lib \
  --source-root lib \
  --asset-dir share \
  --cpanfile cpanfile \
  --runtime-mode bundled_perl \
  --output ./build/webapp \
  bin/webapp
```

This pattern supports web applications that include Perl modules, templates,
CSS, JavaScript, and other static files.

## Docker Deployment

Two-stage pattern for a generic project:

```dockerfile
FROM perl:5.42 AS builder
WORKDIR /workspace
COPY . /workspace
RUN cpanm --installdeps .
RUN perl bin/pax build --output /out/app

FROM debian:bookworm-slim
COPY --from=builder /out/app /usr/local/bin/app
CMD ["/usr/local/bin/app"]
```

The final stage receives only the built executable. It does not need the source
tree, asset tree, `cpanfile`, or web framework installation when the binary was
built in bundled runtime mode.

## Self Compile

PAX can build PAX itself:

```bash
perl bin/pax build -o /tmp/pax bin/pax
/tmp/pax help
```

In a directory with no `paxfile.yml`, the entrypoint and output path are enough.
In a project directory, `paxfile.yml` is still applied unless `--no-paxfile` is
used.

## Architecture

PAX packages an application through these stages:

1. Entrypoint and manifest loading.
2. Dependency and source-root discovery.
3. Code unit compilation into PCU or hybrid PCU records where supported.
4. Native artifact packaging for supported hot regions.
5. Asset and runtime payload embedding.
6. Standalone launcher generation.
7. Runtime extraction and dispatch with fallback safety.

Compilation is adaptive. If a module shape fails, the preferred fix is a reusable
compiler, loader, dependency discovery, or runtime improvement that works for
other projects with the same structure.

## Known Limits

- Perl’s dynamic loading and runtime mutation can require fallback code paths.
- Native speedups depend on whether PAX can prove a region is safe to compile.
- Bundled runtime artifacts are larger than source-only wrappers because they
  include enough Perl/runtime payload to run without the source tree.
- Docker validation requires a local Docker daemon and build access.

## CPAN Release Gates

Release readiness is checked by the repository gates:

```bash
make test
make release-gate
make cpan-build
make cpan-gate
```

Optional release:

```bash
make cpan-release
```

Required release files:

- `Changes`
- `README.md`
- `cpanfile`
- `dist.ini`
- `lib/PAX.pm`

The CPAN gate verifies the distribution tarball and git index exclude temporary
runtime probes, generated workspaces, coverage output, planning artifacts, and
other non-release files.

Release flow rule:

- `make cpan-dist` and `make cpan-build` bump the version by `0.001` before
  running `dzil build`.
- the build then runs `version-gate`, `changes-gate`, and `doc-gate`.
- `Changes` must have the new version as the top entry.
- `README.md` and `lib/PAX.pm` must satisfy the documentation gate before the
  tarball is built.

## Repository Map

- `bin/pax`: public command entrypoint.
- `lib/PAX/`: compiler, packager, loader, runtime, and validation modules.
- `t/`: unit, behavior, and acceptance tests.
- `examples/`: neutral examples used to validate packaging behavior.
- `paxfile.yml`: neutral example build manifest.

## Contributor Rules

- Keep PAX project-neutral.
- Turn project-specific lessons into reusable compiler/runtime rules.
- Keep `README.md` and `lib/PAX.pm` aligned.
- Update POD and tests with behavior changes.
- Run the gates before treating a release build as complete.
