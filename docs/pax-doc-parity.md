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
   - testing
   - release gates
6. Document the public command surface clearly and keep it synchronized between
   `README.md` and `lib/PAX.pm`.
7. Include known limits and caveats in both places.
8. Include FAQ-style answers for the questions an operator or contributor is
   likely to ask.
9. Keep the README and main POD aligned in structure and examples.
10. For major behavior changes, update both the operator manual and the module
    reference in the same change set.

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
- Testing and Release Gates
- FAQ
- Files / Repository Map

## Current Line Counts

- DD README: 2226
- DD main POD module: 2981
- PAX README before this parity pass: 246
- PAX main POD before this parity pass: 267

The target is not to match DD line-for-line. The target is to match the level
of operator clarity, section breadth, and workflow completeness.
