# GitHub automation

Keep this guide named `WORKFLOWS.md`: GitHub gives a README in `.github/` precedence over
the root README on the repository landing page.

[Project overview](../README.md) · [Testing guide](../docs/testing.md)

[`workflows/ci.yml`](workflows/ci.yml) defines GitHub Actions verification and evidence collection.
It runs the maintained Make targets on native Linux runners, plus macOS for binary builds,
with separate jobs for source compilation, Python references/tooling, native units/corpora, runtime failures, compiler guards,
E2E networking, JAM Tart telemetry interoperability and the Docker image build/smoke check.
The **Build / Docker** job runs on master pushes, full requests and manual `build`/`docker` requests,
and never publishes an image. A separate PVM
reference job runs the pinned public-API probes and matching native suites for master pushes
and full/Interop requests, or standalone manual `ref-pvm` requests. It explicitly
selects the interpreter. **Perf / PVM** measures validated workloads on master pushes and
full/Perf requests, with a standalone `bench-pvm` scope also available, and publishes
one speed table with raw samples. The current baseline compares Ragnarök
and the PolkaVM interpreter; compiled comparisons are deferred. Full fuzzing CI remains future work.

Pushes to `master` request full verification, including **Compile / Smoke**.
PR opening, reopening and source updates automatically run **Compile / Smoke**: complete read-only formatting plus unoptimized semantic compilation of every production module
and the production peer main. Heavy
checks still require a maintainer label (`ci:unit`, `ci:e2e`, `ci:interop`, `ci:perf` or `ci:full`).
Automatic smoke runs have their own cancellation group, separate from explicit heavy requests.
The workflow also supports manual dispatch with a selected scope.

Jobs publish summaries and retain diagnostic logs and reports from `build/`. See
[requesting CI](../docs/testing.md#requesting-ci) for label scopes, reruns and revision semantics.

The **Compile** aggregate also runs for automatic PR updates and manual `smoke` requests,
requiring **Compile / Smoke** alone. Master pushes and `unit`/`full` requests require all four
Compile children. Complete group requests expose concise aggregate checks: **Compile**, **Unit**, **Contract**,
**E2E**, **Interop**, **Perf**, **Build** and **Fuzz**. Each aggregate requires every child in its group to succeed,
including rejecting unexpected skips and cancellations. Standalone manual workload scopes
(such as `ref-pvm` or `bench-storage`) run only that workload and omit the complete-group gate.

**Build / Linux** and **Build / macOS** produce [relocatable binary archives](../docs/binaries.md)
for Linux x86-64 and macOS ARM64. The complete Build group runs on master/full requests and
manual `build` requests. Each archive includes maintained native ABIs, licenses, a provenance
manifest and a checksum; a separately unpacked copy must pass peer selftests before upload.
