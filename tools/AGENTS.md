# Tooling and registry instructions

Read [verification infrastructure](../docs/testing/infrastructure.md) for harness changes and
[registration guidance](../docs/testing/adding-tests.md) for new suites/probes.

- Use `make setup` for pinned tools/dependencies, `make` for the current proof-peer build and
  `make check` (alias `make test`) for complete verification. Make owns setup dependencies and
  command sequencing; `make clean` removes all of `build/`.
  `make check` must provision tools/sources/native dependencies without project-specific pre-steps.
  CI runs `check-modules`, `check-python`, `check-unit`, `check-failures`, `check-guards` and
  `check-e2e` as independent parallel jobs; use the affected group locally and `make check` for
  all six. Nim 2 is a historical measurement control, never a second production target. Keep compiler and dependency sources pristine. Follow [the compiler record](../docs/nimony-trial.md) for limitations/evidence.
  Implemented-scope migration parity is not full JAM functionality or compiler-wide safety.

- Format project Rust code with the pinned `rustfmt` defaults (four spaces, 100-column target).
  The shared formatting command invokes `cargo fmt --manifest-path native/bandersnatch/Cargo.toml`
  with the pinned Rust toolchain (`-- --check` in check mode). Keep C sources and headers at four-space
  indentation, matching `.editorconfig` and the existing bridges.

- Use one `COMPILE_CHECK_JOBS` setting (default 4) for compatible codec directory runs and
  all-source semantic compilation and independent contract/privacy/nominal compiler checks.
  Accept 1–4 workers;
  retain serial overrides, private caches/logs, ordered diagnostics and fresh per-suite ARC evidence.
  Keep linked profiles and network/resource scenarios sequential. Hastur scheduling artifacts belong
  under `build/`; its successful parallel worker caches are discarded, so serial codec runs can
  be faster on warm local repeats. Record timings without weakening test workloads or verdicts.

- Keep source-owned verification plans deterministic and feature-grouped. Ordinary failure-family
  files own expected identities; specialized drivers own typed mode declarations and variant plans.
  Named corpus callables own scheduling/report identities. Do not recreate a central name/count
  registry. Preserve genuinely ordered build options and dependency/task execution order; run
  `make check-inventory` for changes to these declarations.

- Native test requirements belong in `tools/native_requirements/<source-family>/<suite>.json`,
  one file per suite, named with the suite's consistent feature prefix. Keep independent JSON fields
  alphabetical; discovery groups source families and suite names lexicographically and rejects
  duplicate/misplaced profiles. Do not recreate a shared append-only requirement manifest.

- Apply module/feature grouping and lexicographic insertion to other unordered requirement/source
  registries too. Runtime provenance discovers project source/configuration and fixture directories;
  new helpers, per-suite requirement files and failure-family files need no provenance registration.
  Preserve genuinely ordered values, including native library/link/include order, positional
  diagnostic records and runtime scenario steps. Document and test any new ordering exception.

Keep independent Python references and orchestration; application assertions stay in native Nim.
Preserve standalone setup, strict failure status, group separation and fresh provenance/evidence.
Do not add duplicate build entry points or launch Python discovery from native/E2E groups.
