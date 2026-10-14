# Persistent multi-peer service verification

Date: 2026-10-14. Both native-language listeners pass the persistent-engine experiment locally on
macOS 27.0.1 arm64. The new Ubuntu 24.04 Linux CI step awaits a pushed run. This is networking
correctness and finite resource evidence, not a benchmark or a language selection.

## Scope and protocol

The [workload and ownership contract](../docs/quic-service.md) use JAMNP-S v1 at
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`: Encryption and handshake, Protocols and streams /
Messages, and CE 143. Pinned LSQUIC/BoringSSL, Nim 2.2.12 ARC and Odin
`dev-2026-10:84bc3fc21` remain unchanged. No dependency source patches or new dependencies.

Each language now retains one listener engine, TLS context, UDP socket and event loop across the
entire experiment. The bridge retains bounded connection handles and exposes copied counters;
JAM certificate/framing policy and application buffer ownership remain independent in Nim/Odin.

## Observed results

The final default service run passed:

- 32 waves: sixteen on each persistent listener, with fresh Nim and Odin client connections.
- 132 authenticated connections promoted and retired: 66 per listener, including four killed peers.
- Up to four authenticated connections retained simultaneously on each listener.
- 128 completed client exchanges, each settling eight streams: 832 exact healthy replies,
  64 intentional cancellations and 128 expected protocol rejections.
- 32 additional TLS/SAN/ALPN rejection attempts, without poisoning the listener or healthy peers.
- Every wave observed healthy completion while a stream on a different connection had a blocked
  large write. Native owner comparison excludes same-connection sibling progress from this marker.
- Reconnects reuse the same public identities after an idle barrier, with no listener restart.
- Every sampled idle barrier had zero retained authenticated connections and zero live application
  stream slots. Killed peers retired through the experiment's two-second transport idle deadline.
- Normal final shutdown completed native close callbacks and language/I/O ownership cleanup.

The final run's listener observations were:

| Observation | Nim | Odin |
| --- | ---: | ---: |
| Sampled peak RSS, bytes | 16,400,384 | 16,941,056 |
| Sampled OS threads | 1 | 1 |
| Sampled peak descriptors | 6 | 5 |
| Idle RSS range after four warmup waves, bytes | 81,920 | 2,244,608 |
| Idle descriptor variation | 0 | 0 |
| Idle language allocation variation, bytes | 0 | 0 |
| Verified cross-connection progress markers | 289 | 288 |

All finite budgets passed: peak RSS below 256 MiB, post-warmup idle RSS variation below 16 MiB,
descriptor variation at most two, and language allocation variation below 64 KiB.
Nim's final occupied-memory count was 48 bytes against a 32-byte pre-service baseline.
Odin ended with zero tracked application bytes and zero pending nbio operations; while listening
idle it retained exactly one receive and one timer.

Allocation totals and descriptor counts are not rankings: Nim's live selector storage is counted,
whereas Odin's application tracker excludes the already acquired process-lived dispatcher.
Nim's macOS selector reserves a descriptor table sized from the OS limit. Neither language counter
attributes C/TLS allocations; RSS is the shared aggregate observation. These are sampled finite
bounds, not exhaustive high-water measurements or proof of leak freedom.

## Commands and regression coverage

Both adapters were rebuilt from the pinned submodules with the shared
`test_quic.build_peers(test_quic.dependencies(False))` runner: C bridge `clang -O2 -Wall -Wextra
-Werror`, Nim ARC with the pinned compiler and generated-C ABI checks, Odin with `-vet
-strict-style`. Language binaries retain the existing correctness-build flags, not benchmark flags.

Executed verification:

```sh
python3 interoperability/test_quic_service.py --skip-build
python3 interoperability/test_quic.py --skip-build
python3 interoperability/test_quic_soak_harness.py
python3 interoperability/test_quic_soak.py --skip-build
python3 tools/format.py --check
git diff --check
```

The original matrix passed all 64 cases: four valid pairs with eight CE exchanges each,
36 TLS/identity rejections and 24 authenticated protocol rejections. Both native parser selftests
passed 10,000 malformed DER/frame inputs; both I/O selftests passed 256 cancellation/retirement
cases. All five existing soak-harness regressions passed. The original 160-session lifecycle soak
passed, preserving its five healthy and three adversarial streams per session.

After strengthening Odin's progress marker to compare distinct connection owners, both adapters
were rebuilt and the complete 32-wave service workload passed again. Final formatting passed
across 82 source files, and the whitespace diff check passed. Codec/crypto source was unchanged;
those suites were not rerun for this networking-only increment.

Full service JSON, resource samples and peer logs remain in ignored `build/quic/service/`.
Linux CI runs the same service workload after the original lifecycle soak and retains these
explicit diagnostics without TLS private keys. Linux success for this increment remains pending.

## Implication for the language decision

The specific persistent inbound-service uncertainty has evidence in both candidates: concurrent
peers share one event loop/engine, rejected or killed peers retire independently, and healthy
connections progress despite another peer's backpressure. Neither requires a connection thread.

This remains bounded IPv4 loopback CE 143 work. Clients intentionally recreate their engines;
persistent outgoing reconnect, a bidirectional validator mesh, IPv6, loss/reordering, independent
JAM peers, admission-ceiling/fairness stress and native allocation attribution remain unproven.
No full M3 or production-validator claim follows from the passing local run.

The next proposed decision slice combines networking, owned codec decoding and crypto. The later
measurement round explicitly includes optimized M1 encode/decode speed for scalar, bounded and
nested structures, borrowed versus owned APIs, allocation costs and latency on identical Linux
hardware/corpora. Those rounds await the maintainer's next go-ahead.
