# Verification instructions

Read [registration guidance](../docs/testing/adding-tests.md) when adding/changing suites or probes,
and [infrastructure](../docs/testing/infrastructure.md) when changing the harness.

- Put implementation unit/boundary/ownership/fuzz assertions in Nim and migrate coherent groups
  to `tests/unit/` through the pinned Hastur native runner (`make unit`). All ordinary suites run through
  the native runner; preserve explicit output, linking and fixture contracts. Preserve
  independent Python references and process/tooling orchestration. Remove superseded standalone
  runners once the supported path preserves their coverage; do not keep duplicate build entry points.
  This nightly has no `std/unittest`; do not vendor Nim 2's library or invent a replacement DSL.
  Retain strict compiler-failure/crash probes until native runner semantics prove equally strong; `.exitcode` alone does
  not require failure in the current Hastur. See [the migration plan](../docs/testing.md).

- Add important negative compilation checks and malformed/truncated/overflow/fuzz cases for decoders.
  Retain official vectors and independent test-only references; no Python production protocol runtime.

- Use one `COMPILE_CHECK_JOBS` setting (default 4) for compatible codec directory runs and
  all-source semantic compilation and independent contract/privacy/nominal compiler checks.
  Accept 1–4 workers;
  retain serial overrides, private caches/logs, ordered diagnostics and fresh per-suite ARC evidence.
  Keep linked profiles and network/resource scenarios sequential. Hastur scheduling artifacts belong
  under `build/`. Codec workers reuse private caches serially across their assigned mains;
  never share writable caches concurrently. Record timings without weakening workloads or verdicts.

- Run Python reference/tooling/provenance unittest discovery once in `make check-python`.
  Native unit/corpus checks and E2E networking must not launch duplicate Python discovery or
  claim another group's verdict. Preserve every group's inventory, standalone setup, failure status,
  logs and summary. E2E owns peer-entry selftests and live peer/service/resilience/soak/offload work;
  unit checks own component suites and independent corpora;
  `check-failures` owns runtime assertion/contract probes and their positive controls;
  compiler Guards retain only documented compiler regressions, distinct ownership hazards and
  material application safety/admission boundaries. Do not add routine private-field, accessor,
  nominal-substitution or invalid-constant matrices. Each Guard needs a source-local rationale
  and reference; preserve exact diagnostic rejection. See `docs/testing/adding-tests.md`.

- Keep rolling suite/probe totals out of `README.md`, `AGENTS.md` and shared testing guides.
  Maintain coverage in source-owned verification plans and report observed totals in verification
  results; adding a feature should not require updating counts in shared prose.

Run only affected local checks; `make unit SUITE=<name>` selects one native suite. Preserve
complete CI verification, exact diagnostics, output/link/fixture contracts and fresh ARC evidence.
Do not add tests that merely mirror code or configuration layout. Follow the
[Python testing guidance](../docs/testing/adding-tests.md#python-reference-and-tooling-tests):
assert observable behavior and complete configured coverage, not comments, display names, job order,
YAML anchor spelling or internal call sequences. Keep independent literal/provenance witnesses and
strict failure, cleanup, archive-safety and fresh-evidence checks.
