# GitHub automation

Keep this guide named `WORKFLOWS.md`: GitHub gives a README in `.github/` precedence over
the root README on the repository landing page.

[Project overview](../README.md) · [Testing guide](../docs/testing.md)

[`workflows/ci.yml`](workflows/ci.yml) defines GitHub Actions verification and evidence collection.
It runs the maintained Make targets on native Linux runners, plus macOS for binary builds,
with a unified **Build** matrix for Smoke, Tooling, Linux & Docker and macOS. Other jobs cover
native units/corpora, runtime failures,
E2E networking (including official MCP SDK message exchange) and JAM Tart telemetry interoperability. **Build / Linux & Docker** combines
Linux archive packaging with the isolated Docker image build/smoke check on `ubuntu-26.04`.
It runs on master pushes, full requests and manual `build` requests. The `ci:docker` label and
manual `docker` scope select only the image check; no image is published. A separate PVM
reference job runs the pinned public-API probes and matching native suites for master pushes
and full/Interop requests, or standalone manual `ref-pvm` requests. It explicitly
selects the interpreter. **Perf / PVM** measures validated workloads on master pushes and
full/Perf requests, with a standalone `bench-pvm` scope also available, and publishes
one speed table with raw samples. The current baseline compares Ragnarök
and the PolkaVM interpreter; compiled comparisons are deferred. Full fuzzing CI remains future work.

Pushes to `master` request full verification, including **Build / Smoke**.
PR opening, reopening and source updates automatically run **Build / Smoke**: complete read-only formatting plus unoptimized semantic compilation of every production module
and the production peer main. Heavy
checks still require a maintainer label (`ci:unit`, `ci:e2e`, `ci:interop`, `ci:docker`, `ci:perf` or `ci:full`).
Automatic smoke runs have their own cancellation group, separate from explicit heavy requests.
Label requests apply only while a PR is open. Closed/merged PR label events schedule no jobs
and use isolated concurrency keys, so they cannot cancel active CI. Label removal is not a trigger.
The workflow also supports manual dispatch with a selected scope. Every workload job uses the shared `ci-job-timeout` anchor set to 60 minutes; families have no timeout overrides.

**Perf / PVM DOOM** runs alongside **Perf / PVM** on master pushes and full/Perf requests.
A standalone manual `bench-doom` scope runs DOOM alone. It checks the pinned frame-1320
state/output golden, then compares checked Ragnarök and PolkaVM interpreted CPU times for
initialization and one gameplay tick, in both process orders. Raw first-call and reused samples,
source identities and ratios are retained. Regular monitoring does not run instruction profilers.
Historical revision, prepared-engine and attribution experiments are no longer CI jobs;
maintained Make tools remain available subject to their existing platform/timing admission rules.
See [the performance monitoring contract](../spec/pvm-ci-performance.md).

Jobs publish summaries and retain diagnostic logs and reports from `build/`. See
[requesting CI](../docs/testing.md#requesting-ci) for label scopes, reruns and revision semantics.

Automatic PR updates and manual
`smoke` requests select **Build / Smoke** alone. Master/full requests select **Smoke**, **Tooling**,
**Linux & Docker** and **macOS**. Workloads retain **Build**, **Unit**, **Contract**, **E2E**, **Interop**, **Perf** and **Fuzz**
name prefixes and adjacent in-file group sections. There are no separate aggregate runners;
individual workload checks report their own results.

**Build / Linux & Docker** runs native packaging, the checked-release audit of every production
module, then isolated Docker validation. Checks retain independent
failure status, summaries and artifacts, and still run after an earlier packaging/check failure.
Smoke retains its fast unoptimized audit and formatting. Tooling runs Python references, lifecycle
model verification and compiler rejection guards, with independent verdicts, summaries and artifacts.
Model checks and rejection guards still run after earlier Tooling failures.
`unit` / `ci:unit` requests select Smoke, Tooling and **Linux Checks**, running the same source/guard
checks without adding archive packaging or Docker. Manual `build` selects Linux & Docker and
macOS; manual `docker` / `ci:docker` selects Docker alone.

Build, Interop and Perf each use one matrix job with `Group / ${{ matrix.family.name }}` display
names. Job conditions run before matrix expansion. Standalone manual workload scopes such as
`ref-pvm` or `bench-storage` select only their workload.

**Build / Linux & Docker** and **Build / macOS** produce [relocatable binary archives](../docs/binaries.md)
for Linux x86-64 and macOS ARM64. The complete Build group runs on master/full requests and
manual `build` requests. Each archive includes maintained native ABIs, licenses, a provenance
manifest and a checksum; a separately unpacked copy must pass peer selftests before upload.

Ubuntu runner versions are defined once per architecture in `ci.yml`: `ubuntu-x86-version`
selects `ubuntu-26.04`, and `ubuntu-arm-version` selects `ubuntu-26.04-arm`. Update these
anchors when changing the shared runner images.
