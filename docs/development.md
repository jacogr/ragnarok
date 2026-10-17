# Development and verification

Use pinned **Nimony 0.6.3**, revision `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, with ARC and
Clang LTO. Assertions, bounds and supported access contracts stay enabled. Nimony arithmetic
wraps intentionally; protocol sizes/conversions need explicit validation. Initialize every local
scalar and pointer explicitly. The [compiler record](nimony-trial.md) documents the remaining
safety limitations. Nim 2 is a historical control only.

## Setup

Install Python 3.12+, Clang/C++, CMake, zlib, OpenSSL and Rust 1.99.0. On macOS select an Xcode
command-line SDK; Linux also needs lld. Then run:

```sh
make clean
make check
make
```

The installer supports Linux x86-64 and macOS ARM64. [Toolchain pins](../spec/toolchain.json)
select exact official archives and SHA-256 checksums; no upstream installer runs. Both local
setup and CI use the same host/identity/version checks. Tools stay under ignored `build/toolchain/`.
Repeated setup verifies retained archives; unknown hosts fail before executing mismatched tools.
Upstream source submodules remain pristine.

`source build/toolchain/env.sh` optionally exports NIMONY, NIMPRETTY and compiler/formatter-only
PATH entries. Make activates this managed environment for compiler/formatter commands. Nimpretty comes from
pinned Nim 2.2.12, but its compiler is not exported or supported as a production target. Its generic
banner is 0.2; archive and installed binary hashes retain its provenance.

## Verification and formatting

`make check` runs six independently selectable groups: source compilation, Python discovery,
native unit/corpus checks, runtime failure probes, compiler rejection guards and E2E networking.
Use the affected group during development;
CI schedules all six concurrently on separate runners. Python references/tooling/provenance
unittests execute once in their own group; native and E2E groups do not rerun that discovery.
Make first ensures the pinned compiler, pristine source submodules and locked Cargo dependencies;
native builds then run Cargo locked/offline. Failures stop the command. The parked
request-namespace, draft-text and Ed25519 normative gates remain; tests cannot settle them.

`make unit` runs all 76 ordinary application suites through the pinned Hastur runner, preparing
the maintained native crypto, Rust and QUIC libraries and required fixtures. The cumulative path
runs the same suites; see [native test migration](testing.md) for coverage and retained Python
reference, negative-probe and orchestration responsibilities.

| Command | Action |
| --- | --- |
| `make` / `make build` | Build `build/ragnarok`, the current authenticated proof peer |
| `make clean` | Remove all of `build/`, including installed tools and cached archives |
| `make setup` | Ensure pinned compiler/formatter, initialize pristine source gitlinks, install pinned Rust/rustfmt and fetch locked Cargo dependencies |
| `make check` / `make test` | Complete canonical verification |
| `make unit` | All 76 Hastur suites with their exact native/fixture profiles |
| `make check-modules` / `make modules` | Every-source semantic compilation gate |
| `make check-python` | Python reference/tooling/provenance tests |
| `make check-unit` / `make runtime` | Native unit suites and independent corpora |
| `make check-failures` | Runtime assertion/contract probes and positive controls |
| `make check-guards` | Compiler rejection guards (701 probes) |
| `make check-e2e` | Peer/service/resilience/soak/offload scenarios |
| `make format` / `make format-check` | Apply or check the pinned formatter |
| `make help` | List commands without provisioning/building |

Make owns setup dependencies, logging and verification sequencing. `make clean` followed by
`make check` needs no activation, manual directories, downloads or native-build pre-steps.
`make`, `make runtime` and `make unit` also provision their dependencies automatically.
`PYTHON=/path/to/python3` selects the host interpreter; Rust comes from the shared pin.
Healthy compiler/formatter installations are verified and reused; missing or changed tools use
checksum/identity-verified installation. Archives are cached by checksum, and corrupt archives fail.

Make and Python 3.12+ are bootstrap prerequisites. Ubuntu's missing native packages are installed
by Make through apt/sudo. On macOS, Apple's command-line tools, CMake, zlib and OpenSSL must be
available. The Rust manager `rustup` must be installed; Make installs the pinned Rust/rustfmt and
fetches locked registry dependencies. No project-specific setup commands are required first.

The default executable enables the existing `integration` and `offload` profiles together. It links
only the real maintained crypto/Bandersnatch/QUIC ABIs, without test observers, and retains ARC,
Clang, checked optimized builds, LTO and Linux lld. Its compiler-location-isolated cache and native
libraries remain under `build/`; the executable is a development proof peer, not a full client.
Top-level Make targets run serially because native preparation and verification share build caches.

CI invokes the six `make check-*` targets independently after checkout/Python setup.
The workflow has no separate directory, compiler, source, Rust or OS-package bootstrap recipes.
`make summary-modules`, `summary-python`, `summary-unit`, `summary-failures`, `summary-guards` and `summary-e2e` render existing reports
even after a failed job;
`SUMMARY_OUTPUT` selects the local Markdown file or GitHub step summary.
Superseded standalone codec/state Python runners are removed. Older commands recorded in
specification/trial evidence describe historical runs, not additional supported runners.

```sh
make format
make format-check
```

Reports/logs remain under `build/tests/{runtime,failures,guards,modules,python,e2e}/` and `build/ci/`.
Temporary TLS keys never belong in commits or diagnostic artifacts. CI uploads logs/reports only.

## Tooling audit

Command sequencing moved from `tools/test.py` into Make; that helper is removed. Shell setup,
Rust installation/fetch, directories, logging and cleanup are direct recipes. Retained Python is
logic that would become longer, less portable or harder to validate as shell commands:

| Helpers | Responsibility |
| --- | --- |
| `setup_nimony.py`, `toolchain_archives.py` | Host/archive identity, checksums, safe extraction and installed binary validation |
| `setup_submodules.py` | Pinned/clean gitlink validation and focused vector checkout |
| `build.py` | Checked platform-specific linker profile and maintained native library preparation |
| `format.py` | Canonical formatter comparison without modifying files in check mode |
| `native_tests.py` | Hastur discovery, linking profiles, fixture integrity and ARC observations |
| `test_modules.py`, `test_runtime.py`, `test_guards.py` | Source inventory, units/references, selectable runtime contracts and compiler guards |
| `test_python.py` | Single independent Python unittest discovery and report |
| `test_e2e.py`, `e2e_checks.py` | Peer-entry selftests and unchanged live networking/resource workloads |
| `native_checks.py` | Shared checked compiler/linker profile and command diagnostics |
| `summarize_tests.py` | Structured evidence rendering and explicit missing/failed report handling |
| `compare_nimony.py` | Optional historical compiler performance control; excluded from normal builds/tests |

## Bounded performance control

Correctness and performance stay separate. The optional comparison extracts the pre-port Nim 2
snapshot into ignored storage and builds an identical workload against it and current sources:

```sh
python3 tools/compare_nimony.py --baseline-compiler /absolute/path/to/nim-2.2.12
```

This requires Git object `aea27ad0789ddb0abbea24c3923d0eb192a67e3a` and the already-built pinned
crypto library. Both builds use ARC, Clang, LTO and checked profiles. Seven samples alternate
execution order with equal iteration counts. Setup, startup, compilation and preflight are outside
native timing. A separate non-LTO observer prevents result pruning; overhead is reported without
subtraction. Raw samples/source/tool hashes are retained in `build/nimony-comparison/results.json`.
See [the measured comparison](nimony-performance.md) for scope and results; this is not a throughput
or full-client performance promise, and adds no dual-compiler production path.


## Make front-end verification

Local macOS ARM64 verification built `build/ragnarok` with both features enabled, ran setup
against current pins, checked all 45 modules through `make modules`, and passed all 59 suites
through `make unit`. Parser, UDP, mesh-policy and integration smoke modes pass; the existing
offload fixture harness verifies completion capacity and held shutdown for the same executable.
`make format-check`, all 23 setup/CI safeguards and 246 Python harness tests pass (the existing
parked-policy skip remains). Command plans for `make check`/`make test` delegate to the complete
Python runner; that full runtime was already verified for the migration revision. Logs and the
offload smoke record live under ignored `build/make/`. The Make front end does not change
implementation behavior or dependency pins.
