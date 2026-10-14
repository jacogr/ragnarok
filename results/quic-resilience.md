# IPv6 disruption and overload verification

Observed locally on 2026-10-14, macOS Apple Silicon. Linux CI includes the new step; its pushed
verification remains pending. Compiler, protocol, LSQUIC/TLS pins and upstream sources are unchanged.
No dependencies, dependency patches or source optimizations were introduced.

[The workload and explicit profiles](../docs/quic-resilience.md) pass in both native implementations:

- **48 forced peer losses and 48 restarts**, twelve per Nim/Nim, Nim/Odin, Odin/Nim and Odin/Odin pairing.
- **384 pending operations settled exactly once**, with final native close releasing their buffers.
- **416 healthy bidirectional CE 143 queries** on the keeper's retained engines, including a final
  healthy reconnect after the last kill in every pairing. Restarted partners retain the same public
  identity/certificate and listener port; the keeper's two engines, TLS contexts and sockets stay alive.
- Maximum observed post-kill retirement: **1.958 seconds**, against a ten-second gate and the
  explicitly selected two-second idle-expiry experiment.
- **24 saturation/recovery waves**, twelve per retained Nim/Odin listener, with mixed native load sources.
- Both listeners reach **16 promoted connections and 64 native stream owners**, refuse excess
  admission, and complete healthy CE work after eight slots retire while seven loaded peers remain.
- **24 connection-capacity rejections and 24 stream-capacity rejections**, exactly one at each boundary
  per wave; **24 healthy probes** succeed after release. Every probe checks the exact response and FIN.
- **624 admitted connections retire** across the two listener lifetimes, with accepted/closed equality
  and no live application stream slots before each next wave.

Every measured retained process uses **one OS thread**. After four warmup cycles, eight fully retired
samples per process show zero descriptor and live application allocation variation. Sampled resources:

| Retained process | Peak sampled RSS | Idle RSS range | Descriptor range | Allocation range |
| --- | ---: | ---: | ---: | ---: |
| Recovery nim-nim | 8.83 MiB | 128 KiB | 0 | 0 |
| Recovery nim-odin | 8.83 MiB | 160 KiB | 0 | 0 |
| Recovery odin-nim | 10.28 MiB | 96 KiB | 0 | 0 |
| Recovery odin-odin | 10.31 MiB | 112 KiB | 0 | 0 |
| Saturation nim | 9.23 MiB | 16 KiB | 0 | 0 |
| Saturation odin | 10.52 MiB | 16 KiB | 0 | 0 |

Limits remain active RSS below 256 MiB, idle RSS range at most 16 MiB, descriptor range at most two,
and live application allocation range at most 64 KiB. These are finite observations, not leak-freedom
or production DoS claims. Killed partners/load sources are explicitly reaped and are excluded from
claims of graceful language-level cleanup.

All Odin keepers, final partners and listeners report zero tracked application bytes and zero
pending I/O operations after graceful shutdown. Nim keeper/final-partner cleanup returns to its
16-byte ARC baseline; the load listener reports only the permitted fixed runtime bookkeeping delta.

The final healthy generation ensures every forced loss is followed by successful reconnect/work.
Healthy and incomplete-request phases have an explicit two-peer barrier: an early sender cannot
place pending work into the other's healthy stream-retirement check. Short expiry, liveness probes
and the thirty-second saturation hold window are named experiment settings. Ordinary mesh/service
profiles retain their earlier settings and incomplete-request deadlines.

Affected regressions also pass:

| Check | Observed result |
| --- | --- |
| Native malformed DER/frame fuzzing | 10,000 cases per language |
| Native I/O retirement selftests | 256 cases per language |
| Authentication/protocol rejection matrix | All 64 pairs |
| Ordinary retained IPv6 peers | All 512 queries and two wrong-key cases |
| Soak harness regressions | All five tests |
| Lifecycle soak | All 160 sessions |
| Persistent inbound service | All 32 multi-peer waves |
| Integrated codec/crypto/QUIC | All 576 streams and 10,000 capture fuzz cases per language |
| Formatting | All 88 source files |
| Patch whitespace | `git diff --check` passes |

Commands run:

```sh
python3 interoperability/test_quic_resilience.py
python3 interoperability/test_quic.py --skip-build
python3 interoperability/test_quic_mesh.py --skip-build
python3 interoperability/test_quic_soak_harness.py
python3 interoperability/test_quic_soak.py --skip-build
python3 interoperability/test_quic_service.py --skip-build
python3 interoperability/test_integration.py --reuse-native
python3 tools/format.py
python3 tools/format.py --check
git diff --check
```

Raw logs, idle samples and complete/incomplete summaries live in ignored `build/quic/resilience`.
The Linux workflow adds this proof after the ordinary mesh step and uploads only explicit diagnostics;
certificate/private-key fixtures are excluded. Prior tests are repeated after shared adapter changes;
the ordinary mesh path is also rechecked after the final healthy-generation addition.

This advances controlled peer-loss and authenticated admission evidence for M3. Packet loss/reordering,
interface changes, unauthenticated handshake floods, connection migration, general multi-target dialing,
validator-set integration and independent-stack interoperability remain open. Bounded Bandersnatch
offload remains the next separate proposed increment, awaiting the maintainer's go-ahead.
