# GitHub automation

Keep this guide named `WORKFLOWS.md`: GitHub gives a README in `.github/` precedence over
the root README on the repository landing page.

[Project overview](../README.md) · [Testing guide](../docs/testing.md)

[`workflows/ci.yml`](workflows/ci.yml) defines GitHub Actions verification and evidence collection.
It runs the maintained Make targets on native Linux runners, with separate jobs for source
compilation, Python references/tooling, native units/corpora, runtime failures, compiler guards,
E2E networking, JAM Tart telemetry interoperability and the Docker image build/smoke check.
The Docker job runs for unit/full requests and never publishes an image. A separate PVM
reference job runs the pinned public-API probes and matching native suites for master pushes
and full/Interop requests, or standalone manual `pvm-reference` requests. It explicitly
selects the interpreter. **Perf PVM** measures validated workloads on master pushes and
full/Perf requests, with a standalone `bench-pvm` scope also available, and publishes
one speed table with raw samples. The current baseline compares Ragnarök
and the PolkaVM interpreter; compiled comparisons are deferred. Full fuzzing CI remains future work.

Pushes to `master` request full verification. Pull requests run checks when a maintainer adds
`ci:unit`, `ci:e2e` or `ci:full`; opening a PR or pushing another commit does not request a run.
The workflow also supports manual dispatch with a selected scope.

Jobs publish summaries and retain diagnostic logs and reports from `build/`. See
[requesting CI](../docs/testing.md#requesting-ci) for label scopes, reruns and revision semantics.
