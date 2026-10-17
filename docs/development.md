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
make setup
make
make check
```

The installer supports Linux x86-64 and macOS ARM64. [Toolchain pins](../spec/toolchain.json)
select exact official archives and SHA-256 checksums; no upstream installer runs. Both local
setup and CI use the same host/identity/version checks. Tools stay under ignored `build/toolchain/`.
Repeated setup verifies retained archives; unknown hosts fail before executing mismatched tools.
Upstream source submodules remain pristine.

`source build/toolchain/env.sh` optionally exports NIMONY, NIMPRETTY and compiler/formatter-only
PATH entries. The normal runner resolves the installation automatically. Nimpretty comes from
pinned Nim 2.2.12, but its compiler is not exported or supported as a production target. Its generic
banner is 0.2; archive and installed binary hashes retain its provenance.

## Verification and formatting

`python3 tools/test.py` audits every production module, checks formatting and protocol provenance,
rebuilds native primitives and checked drivers, and runs all migrated codec, crypto, networking,
lifecycle and enabled proof-offload workloads. It then discovers every `test_*harness.py` suite.
Cargo runs locked/offline after explicit provisioning. Failures stop the command. The parked
request-namespace, draft-text and Ed25519 normative gates remain; tests cannot settle them.

`make unit` runs all 59 ordinary application suites through the pinned Hastur runner, preparing
the maintained native crypto, Rust and QUIC libraries and required fixtures. The cumulative path
runs the same suites; see [native test migration](testing.md) for coverage and retained Python
reference, negative-probe and orchestration responsibilities.

| Command | Action |
| --- | --- |
| `make` / `make build` | Build `build/ragnarok`, the current authenticated proof peer |
| `make setup` | Ensure pinned compiler/formatter, initialize pristine source gitlinks, install pinned Rust/rustfmt and fetch locked Cargo dependencies |
| `make check` / `make test` | Complete canonical verification |
| `make unit` | All 59 Hastur suites with their exact native/fixture profiles |
| `make modules` | Every-source semantic compilation gate |
| `make runtime` | Independent codec/crypto/networking/negative/runtime verification |
| `make format` / `make format-check` | Apply or check the pinned formatter |
| `make help` | List commands without provisioning/building |

Make targets delegate to the existing Python tooling. `PYTHON=/path/to/python3` selects the host
interpreter; Rust comes from `spec/bandersnatch-pins.json`, not the global default. Ordinary targets
check the compiler manifest, binaries and pin hash via `setup_nimony.py --ensure`; healthy tools
are reused. Missing/damaged tools or changed pins use normal checksum/identity-verified setup.
Archives are cached by checksum, so a new pin selects a new archive without trusting or deleting
an old one. A corrupt archive still fails verification. Explicit `make setup` provisions submodules
and Rust/Cargo dependencies; host OS packages and rustup must already be installed.

The default executable enables the existing `integration` and `offload` profiles together. It links
only the real maintained crypto/Bandersnatch/QUIC ABIs, without test observers, and retains ARC,
Clang, checked optimized builds, LTO and Linux lld. Its compiler-location-isolated cache and native
libraries remain under `build/`; the executable is a development proof peer, not a full client.
Top-level Make targets run serially because native preparation and verification share build caches.

CI splits the same plan into `--suite modules` and `--suite runtime` for independent verdicts.
An explicit `--compiler` is intended for CI, whose installer also exports NIMPRETTY. Historical
individual Python runners retain references, fixtures and native-build helpers used by the
cumulative suite; their old Nim 2 build entry points are not the supported way to run this tree.

```sh
make format
make format-check
```

Reports/logs remain under `build/nimony-trial/verification/` and `build/nimony-ci/modules/`.
Temporary TLS keys never belong in commits or diagnostic artifacts. CI uploads logs/reports only.

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
