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

Pinned baseline: Nim **2.2.12**, ARC, Clang; Rust **1.99.0** for the Bandersnatch primitive bridge.
Python **3.12+** runs verification/setup tools. Native builds also need CMake, zlib and OpenSSL.
See [development](docs/development.md) and [upstream ownership](docs/dependencies.md).

```sh
python3 tools/setup_submodules.py
python3 tools/format.py --check
python3 tests/test_codec.py
python3 tests/test_tickets.py
python3 tests/test_guarantees.py
python3 tests/test_disputes.py
python3 tests/test_work_package.py
python3 tests/test_header.py
python3 tests/test_block.py
python3 tests/test_crypto.py --fetch
python3 tests/test_bandersnatch.py --fetch
python3 tests/test_work_report.py
python3 tests/test_assurances.py
python3 tests/test_assurance_crypto.py
python3 tests/test_quic.py --fetch
```

The crypto step builds the native primitive library used by report and assurance-context tests.
`--fetch` initializes exact pinned sources; Bandersnatch also provisions missing locked Cargo
packages. Generated builds, temporary keys, observations and logs stay under ignored `build/`.
[Linux CI](.github/workflows/linux.yml) runs the correctness and lifecycle checks on Ubuntu 24.04.

## Code and verification

| Path | Purpose |
| --- | --- |
| `src/` | Nim codecs and owned snapshots |
| `src/crypto/` | Blake2b-256, Ed25519, Keccak-256 and signing contexts |
| `src/bandersnatch/` | Typed release-reference IETF VRF/RingVRF adapter and domain policy |
| `src/quic/` | Nonblocking LSQUIC adapter, authenticated CE 143 peer and bounded proof offload |
| `tests/` | Independent references and verification runners |
| `tests/native/` | Nim drivers, selftests and intentional compile-failure fixtures |
| `native/` | Narrow maintained C/Rust primitive and transport bridges |
| `spec/`, `vectors/`, `vendor/` | Pinned interpretations, project fixtures and upstream submodules |

Use `python3 tools/format.py` to apply Nim's bundled formatter and `--check` to verify it.
See [codec](docs/codec.md), [crypto](docs/crypto.md) and [networking](docs/networking.md) for APIs,
ownership, reproduction commands and outstanding protocol/security gates.
