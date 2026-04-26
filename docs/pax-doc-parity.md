# PAX Documentation Parity (DD Source Baseline)

## INTRODUCTION

This note records the documentation comparison and the rule applied for SOW-02.
It explicitly aligns with the DD Source documentation style: sectioned POD + operational
manual flow + practical usage examples + explicit caveats.

## BASELINE METRICS

Compared artifacts:

- `Developer` module in DD source application (reference style baseline)
- `lib/PAX.pm`
- `README.md`

Measured today:

| File | Total lines | `=head1` | `=head2` | `=pod` present |
|---|---:|---:|---:|---:|
| `Developer/Dashboard.pm` | 2981 | 9 | 34 | yes |
| `lib/PAX.pm` | 231 | 12 | 4 | yes |
| `README.md` | 264 | 0 | 0 | no (`README` is Markdown) |

## COMPARISON RESULT

Before this update, `lib/PAX.pm` and `README.md` were too compact for SOW-02 expectations.
After this update:

- `lib/PAX.pm` now documents architecture, compilation flow, CLI surface, paxfile contract, environment
  variables, CPAN gates, and limits.
- `README.md` now documents practical flows for app/standalone builds, asset embedding, two-stage Docker,
  and release gates.

DD still has more extensive prose and more headings, but PAX now has a comparable structure
for implementation contract + operations manual.

## DOCUMENT STYLE RULE (APPLIED)

For all future work:

1. Top-level module docs (`lib/*/..pm`) must include:
   - design intent
   - architecture
   - command surface (or API surface)
   - config/inputs
   - known limitations
2. `README.md` must include:
   - quick start
   - full command examples
   - packaging/deployment pattern examples
   - explicit gate/checklist and expected pass/fail outputs
3. Docs are reviewed whenever core modules are changed.
4. If command usage changes, both `lib/PAX.pm` and `README.md` are updated together.

## COMPLETION EVIDENCE

- Documentation rewritten in `lib/PAX.pm`.
- Deployment + examples expanded in `README.md`.
- Baseline-level documentation rule is now tracked in repository governance files.
- Metrics recorded in this file for future regression checks.
