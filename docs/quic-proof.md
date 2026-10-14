# Running the QUIC proof

The proof targets the pinned JAMNP-S version-1 transport and CE 143 preimage
exchange. [Current adapter results and remaining limits](../results/quic-adapters.md)
are recorded separately from the historical wrapper proof. Both languages now
use [explicit project-maintained adapters](quic-adapters.md) over the same C ABI.

With Python 3.12+, CMake, clang/clang++, Ed25519-capable OpenSSL and the existing
pinned Nim/Odin compilers, run from Ragnarok:

```sh
python3 tools/format.py --check
python3 interoperability/test_quic.py --fetch
```

`--fetch` initializes missing pinned source submodules under `vendor/`.
For a fresh checkout, run `python3 tools/setup_submodules.py` first; see
[the source guide](dependencies.md).
The runner builds matching LSQUIC/BoringSSL, compiles Nim with ARC and Odin with
vet/strict-style checks, runs native parser and I/O selftests and executes the peer
matrix over **localhost UDP**. It generates test identities inside ignored
`build/quic/fixtures`; their private keys are local test artifacts.

For subsequent runs:

```sh
python3 interoperability/test_quic.py
python3 interoperability/test_quic.py --skip-build
```

The first rebuilds from retained sources. The second reruns selftests and the
network matrix against existing binaries; use it only after a successful build
with the current native sources. Logs and machine-readable results remain in
`build/quic/build.log`, `build/quic/cases/` and `build/quic/results.json`.
Build output and downloaded sources are isolated from global toolchains/packages.

Native sources are `nim/quic/transport.nim`, `nim/quic/peer.nim` and
`odin/quic/peer.odin`. No third-party Nim package or source patch is used.
Both accept:

```text
server|client <loopback port> <certificate PEM> <private-key PEM> <expected-key file or -> <ALPN> <timeout-ms> [test case]
```

A key file contains 32 raw Ed25519 public-key bytes. Dialers must specify the
expected server key; acceptors may use a dash to discover a consistent peer.
The script handles peer startup, deadlines and teardown. `--selftest` instead
runs each native parser fuzz entry point without opening network sockets.

The original proof uses bounded buffers, eight concurrent streams and one
connection per process. The explicit-adapter implementation passes locally on
macOS, and the maintainer has reported that Linux CI also passes. The
[bounded lifecycle soak](quic-soak.md) reuses each native process across repeated
sessions with mixed healthy and adversarial streams. This remains an experiment,
not a reusable client networking API or a completed M3 gate. The existing
codec test command remains independent:

```sh
python3 interoperability/test_codec.py
```
