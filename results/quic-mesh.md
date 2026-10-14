# Persistent IPv6 peer verification

Observed locally on 2026-10-14, macOS Apple Silicon. Linux CI includes the new proof; its pushed
verification remains pending. The maintainer confirmed the preceding benchmark CI fix passes.

The [bounded workload and policy](../docs/quic-mesh.md) pass in all four pairings. Each logical
peer retains one LSQUIC client engine and one server engine, their TLS contexts, IPv6 sockets and
one native dispatcher for the entire run. Source/compiler/library pins and upstream sources are
unchanged. Duplicate arbitration is documented project policy, not an additional JAMNP-S rule.

- **64 reconnect rounds**, sixteen per pairing, with the same processes/engines throughout.
- **512 successful CE 143 queries**, four initiated by each peer per round on the same connection.
- **60 authenticated duplicate connections retired**; the preferred direction survives each race.
- **Four five-second fallback dials**, one per pairing, carrying queries in both directions.
- **Two mixed-language wrong-key cases rejected** before any CE exchange.
- Both native preferred-initiator selftests pass, including ordering symmetry and the high-bit boundary.
- Every active/idle observation reports **one OS thread per peer**.
- Every idle accepted/closed count agrees before reconnect; no application stream slot remains live.
- Odin final cleanup reports **zero tracked bytes and zero pending I/O operations** in every positive run.
- Nim final cleanup reports **16 bytes before and after** the complete peer owner scope in every positive run.

Post-warmup resources use twelve fully retired samples per peer. Limits are active RSS below
256 MiB, idle RSS range at most 16 MiB, descriptor range at most two, and live application
allocation range at most 64 KiB. These finite observations do not establish leak freedom.

| Pairing | Peak sampled RSS | Largest idle RSS range | Idle descriptor range | Idle allocation range |
| --- | ---: | ---: | ---: | ---: |
| nim-nim | 8.78 MiB | 240 KiB | 0 | 0 |
| nim-odin | 10.31 MiB | 256 KiB | 0 | 0 |
| odin-nim | 10.34 MiB | 272 KiB | 0 | 0 |
| odin-odin | 10.28 MiB | 224 KiB | 0 | 0 |

The retained-engine test exposed and fixed two ownership/lifecycle details: LSQUIC requires an
explicit application read-half release after validated FIN, and duplicate closure can erase a
current authentication status before the other peer's selection loop observes it. The bridge
now retains successful handshake generations across close; the native selector uses that evidence
and waits for full duplicate retirement before opening application work. Its process-global TLS
initialization also spans both live role engines, with cleanup after the last engine is destroyed.

The affected regressions also pass:

| Check | Observed result |
| --- | --- |
| Native malformed DER/frame selftests | 10,000 cases per language |
| Native idle/ready I/O retirement | 256 cases per language |
| Authentication and CE rejection matrix | All 64 peer pairs |
| Soak harness regressions | All five tests |
| Lifecycle soak | All 160 sessions |
| Persistent inbound service | All 32 multi-peer waves |
| Integrated codec/crypto/QUIC | All 576 streams and 10,000 capture fuzz cases per language |
| Formatting | All 88 source files |
| Patch whitespace | `git diff --check` passes |

Commands run:

```sh
python3 interoperability/test_quic.py
python3 interoperability/test_quic_mesh.py --skip-build
python3 interoperability/test_quic_soak_harness.py
python3 interoperability/test_quic_soak.py --skip-build
python3 interoperability/test_quic_service.py --skip-build
python3 interoperability/test_integration.py --reuse-native
# Final rebuild/rerun after the receive-teardown guard:
python3 interoperability/test_quic_mesh.py
python3 tools/format.py
python3 tools/format.py --check
git diff --check
```

Raw peer logs, idle samples and summary JSON are in ignored `build/quic/mesh`. The Linux workflow
adds this proof and explicit diagnostic uploads, excluding certificate/private-key fixtures.

This advances M3's IPv6, dual-role and retained outgoing lifecycle evidence. A general multi-target
outgoing engine, arbitrary IPv6 routing, validator metadata/epoch integration, live fallback
replacement, durable streams, independent-stack interoperability, disruption/overload and bounded
Bandersnatch offload remain open. No production or language-selection claim is made. The next
increment requires the maintainer's go-ahead.
