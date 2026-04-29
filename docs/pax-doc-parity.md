# PAX Documentation Parity Rule

## Purpose

This file records the documentation rule PAX should follow after comparing the
Developer Dashboard README and main POD against the current PAX docs.

The baseline lesson is not merely "write longer docs". The baseline is:

- describe the product in operator language
- explain the problem the product solves before listing commands
- provide a real manual, not just a command summary
- explain architecture in named concepts
- give copyable workflows
- answer likely operator questions inside the main docs

## DD-Style Documentation Rule

When documenting PAX, use this structure:

1. Start with product identity and a plain introduction.
2. Explain the operational problem PAX solves.
3. Explain what the user gets from the product.
4. Name the main concepts and core modules so the architecture is navigable.
5. Provide a manual with copyable workflows:
   - installation
   - first run / first build
   - standard standalone build
   - self-hosted build
   - web application packaging
   - Docker deployment
6. Document the public command surface clearly and keep it synchronized between
   `README.md` and `lib/PAX.pm`.
7. Include known limits and caveats in both places.
8. Include FAQ-style answers for the questions an operator or contributor is
   likely to ask.
9. Keep the README and main POD aligned in structure and examples.
10. For major behavior changes, update both the operator manual and the module
    reference in the same change set.
11. Enforce documentation completeness through `POD-DOC-ALL` inside the doc
    gate, not as a separate optional cleanup step.

## POD-DOC-ALL Rule

`POD-DOC-ALL` is the documentation-completeness check for Perl assets in this
repository.

Scope:

- Perl scripts such as `bin/pax`
- Perl modules under `lib/`
- Perl tests under `t/`

Enforcement rules:

1. every changed Perl file must carry current file-level POD that explains what
   the file is for in its current shape
2. module POD must stay unique to the module and must not collapse into generic
   boilerplate that could describe any file
3. changed public or operationally meaningful subroutines must carry preceding
   comments that explain intent or behavior impact in concrete language
4. subroutine comments must not use boilerplate filler such as `helper`,
   `utility`, `method`, or similar low-information labels
5. changed tests must explain the behavior contract they validate
6. changed scripts must explain their public role and invocation shape
7. doc updates are part of the same change set as behavior updates; they are
   not deferred cleanup

Reference style:

- Use `Developer::Dashboard` modules as the breadth/clarity example for module
  POD density and subroutine-level intent comments.
- Follow that standard without copying project-specific wording into PAX.

Operational rule:

- `doc-gate` is not complete unless `POD-DOC-ALL` passes.
- If a change touches Perl behavior and the documentation was not updated to
  match, the change set is not done.

## Changes File Rule

The `Changes` file is part of the operator-facing documentation set.

When writing changelog entries:

1. describe meaningful project progress
2. describe user-visible workflow changes, release-gate changes, packaging
   changes, neutrality improvements, validation milestones, or honest internal
   checkpoints
3. do not fill entries with placeholder text such as `Version bump`
4. do not narrate file edits that carry no audience value
5. mention files only when the filename itself matters to the operator-facing
   behavior or release contract
6. if a release has no user-visible feature, describe the real checkpoint in
   plain language instead of pretending there was feature progress

The changelog audience is the project operator, evaluator, or contributor who
wants to understand what changed in substance, not which files were touched.

## Temporary File Rule

PAX must not leave temporary files in the project working tree.

Rules:

1. temporary runtime probes, scratch manifests, generated helper scripts, and
   transient extraction metadata must be created under the OS temporary area
   such as C</tmp> or the platform temp directory returned by the runtime
2. a project checkout is not a temp directory
3. if a temporary file is not meaningful project output, it must not be created
   in the repository root or inside normal source directories
4. when using C<File::Temp>, prefer an explicit temp-directory strategy such as
   C<TMPDIR =E<gt> 1>, C<DIR =E<gt> ...>, or C<tempdir(CLEANUP =E<gt> 1)>
5. generated temp-file names such as C<pax-runtime-probe-*> are implementation
   detail and must be cleaned up automatically

This rule exists to keep the repository clean, reduce operator noise, and make
release gates meaningful.

## Git Gate Rule

PAX has two git-gate requirements and both must pass before work is considered
closed:

1. forbidden non-release paths must not be tracked
2. the working tree must be clean after the required commit

That means `git-gate` is not complete if `git status --short` shows any staged,
modified, deleted, renamed, copied, or untracked files.

The correct end state is:

- required changes committed
- forbidden paths not tracked
- `git status --short` is empty

## Release Flow Rule

Release preparation and release verification are separate steps.

Rules:

1. version bumping is a deliberate release-preparation step
2. release-preparation steps may change tracked files such as `lib/PAX.pm`,
   `dist.ini`, and `Changes`
3. release-verification steps such as `make cpan-dist` and `make cpan-gate`
   must not invent changelog text or mutate tracked source files
4. `Changes` content must be written by the operator or change author in
   meaningful language before `release-gate` runs
5. `git-gate` is independent of `cpan-gate` and is the final gate in the
   closure sequence; it must verify a clean tree after the release-preparation
   commit
6. the final gate chain must compare `HEAD` against `HEAD^` and fail if a
   committed change touched release-facing files without advancing the PAX
   version
7. version examples in operator docs must use generic placeholders such as
   `<next-version>` instead of the current live release number, so the docs do
   not drift every time a checkpoint is cut
8. after a successful PAUSE upload, the release flow must move the
   `RELEASED_TO_PAUSE` git tag to the released commit and push that tag to
   `origin`

This keeps the release flow reproducible and prevents the cycle where a build
target creates new tracked changes and then fails its own git cleanliness gate.
It also prevents stacks of meaningful changes from accumulating forever under
one stale version number.

## All Gates Completion Rule

PAX work is not complete just because the code change exists or one release
gate passed.

The mandatory closure rule is:

1. run TDD gates for module- and unit-level behavior
2. run BDD gates for operator-visible CLI and workflow behavior
3. run ATDD gates for standalone/application acceptance behavior
4. run the QA gate that aggregates TDD, BDD, ATDD, and release metadata checks
5. run the committed-tree version-history and CPAN packaging gates
6. commit the required tracked changes
7. finish at git gate on the committed tree

Terminology rule:

- "all gates" means the whole closure sequence above
- it is not the semantic name of a single gate
- `make all-gates` is only a convenience target that replays the final
  verification set ending at git gate
- do not describe `make all-gates` as if it replaces the earlier gates

Operational consequences:

1. `release-gate` alone is not enough
2. `cpan-gate` alone is not enough
3. `git-gate` alone is not enough
4. a new edit after a successful gate run invalidates that gate state and the
   affected gates must be rerun
5. do not say work is done until all gates are closed or the user explicitly
   waives part of the gate chain
6. `make all-gates` must include a committed-history version check, not just a
   working-tree version consistency check

## Section Expectations

PAX main documentation should keep these section families available over time:

- Introduction
- What You Get
- Main Concepts
- Public Command Surface
- Paxfile Contract
- Manual
- Architecture
- Known Limits
- FAQ
- Files / Repository Map

## Current Line Counts

- DD README: 2226
- DD main POD module: 2981
- PAX README before this parity pass: 246
- PAX main POD before this parity pass: 267

The target is not to match DD line-for-line. The target is to match the level
of operator clarity, section breadth, and workflow completeness.
