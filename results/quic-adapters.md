# QUIC adapter comparison

## Outcome

Both candidates now use explicitly maintained adapters over the same pinned
LSQUIC/BoringSSL build and the same transport/TLS C ABI. Nim uses standard
selectors and nonblocking UDP; Odin retains core:nbio. JAM identity policy,
CE 143 framing, fixture selection and payload validation remain independent
native-language code. [Architecture and ownership](../docs/quic-adapters.md)
are documented separately.

Chronos, nim-lsquic and their Nim dependency closure are removed from the active
build. The three local Nim dependency patches and transformation functions are
removed. The source pins contain four native entries and an empty patch list;
the runner rejects any nonempty patch list. A fresh native-only source tree and
separate native/Nim build caches exclude the old modified wrapper directories.
No global Nimble installation or third-party Nim import path is used.

The shared engine, TLS, native submodule, compiler and protocol revisions remain
unchanged. LSQUIC and BoringSSL are the existing iftech/vacp2p forks. The C bridge
and Odin peer are unchanged in this round. Nim continues using ARC, with stable
stack owners and synchronous callbacks instead of async closure ownership.

## Executed verification

Local Apple Silicon macOS results, using the pinned Nim 2.2.12 ARC and Odin
compiler toolchains. Fresh native archives were obtained with `--fetch`; the
successful final build and peer matrix used the retained unmodified sources:

```sh
python3 tools/format.py
python3 tools/format.py --check
python3 interoperability/test_quic.py
python3 interoperability/test_quic_soak_harness.py
python3 interoperability/test_quic_soak.py --skip-build
git diff --check
```

The shared native C build passed `-Wall -Wextra -Werror`, and Odin passed
vet/strict-style compilation. Nim's generated C callback signatures compile
against the same headers, including read-only certificate/datagram byte types.
There are no wrapper ARC-cycle warnings or dependency error-type patches.

The 64-case peer matrix passed:

- Four valid pairings, each with eight concurrent authenticated CE 143 exchanges.
- 36 TLS/key/SAN/ALPN rejection pairs.
- 24 authenticated framing/protocol rejection pairs.
- Each native parser passed 10,000 deterministic malformed DER/frame inputs.
  Nim also checks every prefix of known-valid request/reply frames with and
  without FIN.
- Nim passed 256 idle/ready UDP selector registration retirements; Odin passed
  256 idle/ready receive cancellations on its actual I/O backend.
- All five soak harness regression checks passed.

The default 40-round soak passed all four pairings: **160 same-process
sessions**, each with five healthy streams and three adversarial streams.
Each session demonstrated a genuinely blocked large write, cancellation,
missing-FIN timeout and continued healthy sibling service. All native peers
exited normally after cleanup. Active observations showed one OS thread per
peer and a maximum RSS of 14.14 MiB, below the existing 256 MiB budget.

After eight warmup sessions, observed idle resource ranges were:

| Server / client | Server RSS range (KiB) | Client RSS range (KiB) | Descriptor range, both | Live language allocation range, both |
| --- | ---: | ---: | ---: | ---: |
| Nim / Nim | 192 | 160 | 0 | 0 bytes |
| Odin / Odin | 224 | 1360 | 0 | 0 bytes |
| Nim / Odin | 224 | 1264 | 0 | 0 bytes |
| Odin / Nim | 176 | 176 | 0 | 0 bytes |

These are finite resource observations, not throughput benchmarks or proof of
leak freedom for every native path. C/TLS allocations are covered by RSS but
not the language allocation counters. Machine-readable results and build/case
logs remain under ignored `build/quic/`.

## Interpretation and remaining work

This removes the unequal third-party-wrapper patch obligation from the language
comparison. Both adapters now make buffer and callback ownership explicit in
project code over the same native transport substrate. Maintenance of those
adapters remains our responsibility; this does not select a language or pass M3.

The proof still uses IPv4 loopback and one connection per recreated engine.
Persistent-engine multi-peer operation, IPv6, independent JAM peer testing,
broader protocol coverage and deeper C/TLS allocation instrumentation remain.
The Linux workflow runs the same commands with fresh sources; the maintainer reported on 2026-10-14 that Linux CI passes for
this adapter revision (no run URL was supplied). Earlier Linux results describe
the historical wrapper implementation, not this replacement.
