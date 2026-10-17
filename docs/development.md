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
python3 tools/setup_nimony.py
python3 tools/setup_submodules.py
rustup toolchain install 1.99.0 --profile minimal --component rustfmt --no-self-update
rustup run 1.99.0 cargo fetch --locked --manifest-path native/bandersnatch/Cargo.toml
python3 tools/test.py
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

CI splits the same plan into `--suite modules` and `--suite runtime` for independent verdicts.
An explicit `--compiler` is intended for CI, whose installer also exports NIMPRETTY. Historical
individual Python runners retain references, fixtures and native-build helpers used by the
cumulative suite; their old Nim 2 build entry points are not the supported way to run this tree.

```sh
source build/toolchain/env.sh
python3 tools/format.py
python3 tools/format.py --check
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
