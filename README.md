# JAM Ragnarök

Ragnarök is a joint effort between the maintainer and AI coding agents, and we are proud of it.
The maintainer sets direction, steers each increment and owns decisions; AI agents help research,
implement, test and document the work. We make that collaboration explicit.

Protocol target: **Gray Paper 0.8.0**. The implemented report codec and validator-set domains
and the release-designated ark-vrf 0.2.2 reference are migrated. Exact Bandersnatch draft-text
parity remains gated by its 16-byte versus reference 32-byte challenge discrepancy.
See the [migration audit](spec/graypaper-0.8.0.md) for coverage, fixture provenance and open gates.

An independent **Nim** implementation of the Join-Accumulate Machine (JAM), built against pinned
Gray Paper and JAMNP-S specifications. Language selection is complete; its sources, comparisons
and observations are preserved in the
[`language-selection` release](https://github.com/jacogr/ragnarok/releases/tag/language-selection).

The current foundation includes canonical codecs and immutable snapshots, native crypto adapters,
and authenticated nonblocking QUIC with bounded ownership/cancellation tests. It is not yet a full
JAM client or production validator. [M1 codec progress](docs/m1.md) and [design/remaining work](docs/design.md) describe the scope.

## Setup

The supported compiler is **Nimony 0.6.3**, pinned to the 2026-10-15 nightly
`5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, with ARC and checked Clang LTO.
Setup supports Linux x86-64 and macOS ARM64 from checksum-pinned official archives. Rust **1.99.0**
provides the maintained Bandersnatch primitive bridge; Python **3.12+** runs tooling. CMake, zlib,
OpenSSL and Clang are required; Linux additionally uses lld. See [development](docs/development.md).

```sh
make setup   # Provision pinned tools, pristine submodules and locked Cargo dependencies.
make         # Build the current proof peer as build/ragnarok.
make check   # Run complete verification (make test is an alias).
```

Make uses the existing Python commands; `make help` lists the bounded test and formatting targets.
`make setup` reuses an intact compiler/formatter and refreshes them when pins change. System
packages and rustup remain prerequisites. The default artifact is the current authenticated QUIC
proof peer with integration and bounded offload enabled; it is not a full validator executable.

The normal verification command resolves the installed compiler and formatter automatically;
there is no global Nim compiler requirement. `build/toolchain/env.sh` optionally activates the
same tools in a shell. Only `nimpretty` is exposed from its pinned formatter archive. Normal
verification never invokes the historical Nim 2 compiler.

Verification includes the all-source audit, protocol provenance, formatting, independent Python
harnesses and checked codec/crypto/networking/offload suites. Linux CI uses the same command plan
in separate runtime and module jobs. Generated builds, fixture keys and logs stay under ignored
`build/`. Implemented-scope local migration coverage is complete; final Linux confirmation and
normative policy gates remain explicit in the [compiler record](docs/nimony-trial.md).

For all 59 native application suites, use `make unit`. This prepares
the pinned crypto/QUIC libraries and generated fixtures. See
[native test migration](docs/testing.md) for coverage and retained Python responsibilities.

## Code and verification

| Path | Purpose |
| --- | --- |
| `src/codec/` | Nim codecs, consensus-facing types and owned snapshots |
| `src/crypto/` | Blake2b-256, Ed25519, Keccak-256 and signing contexts |
| `src/bandersnatch/` | Typed release-reference IETF VRF/RingVRF adapter and domain policy |
| `src/quic/` | Nonblocking LSQUIC adapter, authenticated CE 143 peer and bounded proof offload |
| `tests/` | Independent references and verification runners |
| `tests/unit/` | Nim application tests executed by the pinned native Hastur runner |
| `tests/fixtures/` | Native test inputs with hashes and independent-reference checks |
| `tests/native/` | Native drivers, remaining selftests and intentional compile-failure fixtures |
| `native/` | Narrow maintained C/Rust primitive and transport bridges |
| `spec/`, `vectors/`, `vendor/` | Pinned interpretations, project fixtures and upstream submodules |

Use `make format` to apply the pinned formatter and `make format-check` to verify it.
The underlying Python entry points remain available; no global Nim compiler is required.
See [codec](docs/codec.md), [crypto](docs/crypto.md) and [networking](docs/networking.md) for APIs,
ownership, reproduction commands and outstanding protocol/security gates.
