# PAX

**PAX** is a Perl-native adaptive execution and packaging toolchain.

It is designed to be:

- **generic**: no hard-coded project/module assumptions
- **fast**: compile and execute hot paths where feasible
- **deployable**: build single-file artifacts or app launchers for staging into minimal containers
- **repeatable**: manifest-driven inputs and versioned CPAN artifacts

This repository uses separate validation targets and example apps only.

## What changed in this iteration

PAX documentation now requires parity at the top level between:

- `lib/PAX.pm` main POD
- `README.md`
- release records (`Changes`, `cpanfile`, `dist.ini`)

## Quick start

Run a command:

```bash
perl bin/pax help
```

Build a standalone executable. With no positional argument, PAX reads `paxfile.yml`:

```bash
perl bin/pax build
perl bin/pax build -o ./bin/my-app
```

Run it. `pax run` uses the same paxfile/CLI build inputs, builds the standalone binary, and then executes it:

```bash
perl bin/pax run -- version
perl bin/pax run --output ./bin/my-app -- version
```

Lower-level app-server commands are still available for diagnostics and development, but the main workflow is `build` and `run`.

Build an app image (server-style, advanced):

```bash
perl bin/pax app-build --name dashboard "examples/webapp/bin/pax-webapp"
```

Start it and run one request (or script arguments):

```bash
perl bin/pax app-start --name dashboard --daemonize
perl bin/pax app-run --name dashboard -- version
perl bin/pax app-stop --name dashboard
```

`app-start` and `app-run` are useful for app patterns where socket lifecycle and preloading are
part of deployment.

## CLI command map

Primary commands:

- `build`
- `run`

Advanced diagnostic and compatibility commands:

- `capture`
- `inspect`
- `hir`
- `compile`
- `diff`
- `run-native`
- `dispatch`
- `bench`
- `bench-matrix`
- `profile`
- `why-not`
- `trace-guards`
- `gatekeeper`
- `corpus`
- `core-suite`
- `cpan-matrix`
- `app-build`
- `app-start`
- `app-run`
- `app-stop`
- `standalone-build`
- `standalone-run`
- `standalone-inspect`
- `standalone-extract`
- `standalone-why-not`
- `standalone-native-run`

Get complete flag-level usage:

```bash
perl bin/pax help
```

Common options include:

- `--name`
- `--paxfile` (default `paxfile.yml`)
- `--no-paxfile`
- `--lib`
- `--source-root`
- `--asset`
- `--asset-dir`
- `--cpanfile` (standalone only)
- `--runtime-mode` (standalone only)
- `--output` / `-o` (build/run output path, optional: overrides `paxfile.yml` `output`)
- `--compact`

## Runtime behavior model

PAX uses staged fallback:

1. Native dispatch when a compiled artifact can be selected
2. Guarded execution when assumptions are safe
3. Source fallback when required

This preserves correctness-first behavior while improving startup and hot-path execution
for workloads with stable region behavior.

## `paxfile.yml` contract

`build`, `run`, `standalone-build`, `app-build`, and related commands accept `paxfile.yml` values as defaults:

- `name`
- `entrypoint`
- `libs`
- `source_roots`
- `assets`
- `asset_dirs`
- `cpanfiles`
- `output`
- `runtime_mode`
- `app_name`
- `app_namespace`
- `app_entrypoint_env`
- `app_entrypoint_fallback`
- `app_command`

CLI flags always override file values. Use `--no-paxfile` to skip file reads entirely.

Output resolution for `build`, `run`, and `standalone-build`:

- `--output` / `-o` on CLI (highest priority)
- `output` in `paxfile.yml` (if not overridden)
- default path `./.pax/standalone/<name>/<name>` (final fallback)

## Building with asset embedding

To embed assets with a standalone artifact:

```bash
perl bin/pax build \
  --name dashboard \
  --paxfile paxfile.yml \
  --asset-dir "examples/webapp/share" \
  --asset "examples/webapp/share/public/favicon.ico" \
  --source-root "examples/webapp" \
  --cpanfile "examples/webapp/cpanfile" \
  "examples/webapp/bin/pax-webapp" \
  --output ./.pax/standalone/dashboard/dashboard \
  --runtime-mode bundled_perl
```

This embeds:

- compiled code units
- selected assets
- runtime dispatch metadata
- optional dependency payloads from `cpanfiles`

Validate the artifact:

```bash
perl bin/pax standalone-inspect --name dashboard
perl bin/pax standalone-why-not --name dashboard
perl bin/pax run --paxfile paxfile.yml -- version
```

## 2-stage Docker pattern

Use this when the final runtime image should only contain the final executable
(no source app tree, no `cpanfile`, no framework modules).

**Stage 1** (build): run PAX and produce artifact.

```dockerfile
FROM perl:5.42 AS builder
WORKDIR /workspace
RUN apt-get update && apt-get install -y --no-install-recommends build-essential cpanminus && rm -rf /var/lib/apt/lists/*
COPY . /workspace
RUN cpanm --installdeps .
RUN perl bin/pax build --name dashboard --paxfile paxfile.yml --runtime-mode bundled_perl --output /out/dashboard
```

**Stage 2** (runtime): ship only output binary.

```dockerfile
FROM debian:bookworm-slim
COPY --from=builder /out/dashboard /usr/local/bin/dashboard
CMD ["/usr/local/bin/dashboard"]
```

> This pattern is intentionally minimal and depends on project-specific
> `paxfile.yml` content for framework/library paths.

## CPAN release gates (must pass before release-marking)

PAX enforces release alignment through scripts and Makefile targets:

```bash
make cpan-sync-versions
make cpan-dist
make cpan-build
```

Optional release:

```bash
make cpan-release
```

Bump version:

```bash
make cpan-bump-version VERSION=0.004
```

Required checks for this gate:

- `Changes`, `README.md`, `cpanfile`, `dist.ini`, `lib/PAX.pm` exist
- `lib/PAX.pm` version is canonical
- `lib/PAX/**/*.pm` version sync is complete
- `lib/PAX.pm` POD includes current behavior and aligns with README
- Makefile contains cpan targets and release outputs are regenerated each time

## CPAN files in this repo

- `lib/PAX.pm` – canonical version, package docs, gate contract
- `cpanfile` – dependency source of truth
- `dist.ini` – Dist::Zilla config and `Prereqs::FromCPANfile`
- `Changes` – release notes

## Notes for contributors

- Keep PAX project-neutral. Never hard-code project-specific package names in core modules.
- Prefer adaptive fixes that generalize to similar module classes.
- If logic for one app shape is added, extract generic logic and re-use it.
- When core behavior changes, update docs and POD in touched modules immediately.

## Documentation parity check

This document and `lib/PAX.pm` are the canonical end-user and API-level entry points.

- `lib/PAX.pm` focuses on module contract, architecture, and formal behavior.
- `README.md` focuses on operator workflow, examples, and command usage.
- Both files should stay synchronized as features evolve.

## Repository quick map

- `bin/pax`: command entrypoint
- `lib/PAX/`: modules and runtime/compiler pipeline
- `t/`: tests
- release automation scripts: version sync and bump helpers
- `paxfile.yml`: example default build manifest
- `PAX-*.tar.gz`, `PAX-*`: release artifacts generated by `make cpan-build`
