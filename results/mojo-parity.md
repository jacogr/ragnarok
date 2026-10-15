# Mojo M1/M2/M3 parity

Local verification: Apple M1 Max, macOS arm64, 2026-10-14.
Stable Mojo 1.1.0 (8189361e). **Linux verification awaits the pushed CI run.**

The existing bounded POC now has a third native implementation. No maintenance blocker was
found, and no speed optimization or language-selection decision is part of this increment.

| Gate | Observed shared verification |
| --- | --- |
| M1 codec | 185,373 requests in each Mojo optimization mode; all five families, official vectors, atomic failures and owner-bound payload byte checks |
| Static contracts | 13 Mojo compile-failure probes; wrong variant access also fails in optimized crypto builds |
| M2 primitives | 5 RFC8032, 151 Wycheproof and 56 hash messages per build; native four-worker ownership/concurrency checks |
| M2 Bandersnatch | 7 contextual, 7 ring and 7 official JAM ticket fixtures per build; native four-worker checks |
| Cross-language crypto | 32 deterministic Ed25519 messages; 16 contextual messages; all 6 directed ring-proof pairings |
| QUIC authentication/framing | 144 cases across all 9 directed peer pairings |
| Native fuzz/readiness | 10,000 DER/frame cases; 10,000 owned codec/hash cases; 256 idle/readable UDP retirements |
| Retained lifecycle soak | 9 pairings × 16 sessions; five healthy, two rejected and one cancelled stream per session |
| Multi-peer service | 3 retained listeners × 12 reconnect/adversarial waves, rotating all three client languages |
| IPv6 peers | 864 bidirectional queries; preferred/fallback arbitration, reconnect and 6 wrong-pin pairings |
| Peer loss | 108 peer deaths with pending owners; recovery on retained engines; 9 closed-before-request pairings |
| Admission | 3 listeners × 12 saturation/recovery waves; 16 connections and 64 streams |
| Integrated composition | 864 streams across 3 listeners and all three clients; raw preimage hashing, input reuse and cancellation release |
| Proof offload | 3 listeners × 10 waves; 2 workers, 4 owned slots, 128 RingVRF verifications/job; every client/job role rotates across languages |
| Baseline | All 69 common codec/hash case-operation pairs; 3 fresh timing processes/candidate/case, 45 batch and 384 individual latency samples |

The offload checks include capacity/wrong-domain rejection, queued/held/actual-crypto cancellation,
healthy networking during real verification, four pending jobs at shutdown and both workers joined.
The full shared Nim/Odin crypto suites also passed; source/toolchain/dependency pins were retained.

## Resource and maintenance differences

The local SDK has nine fixed startup threads; the optional proof pool adds two. Raw counts are
retained, never normalized to one. The harness measures the platform baseline and rejects extra
threads after native readiness. A bounded pre-endpoint quiescent window avoids comparing an
incomplete SDK startup heap count with shutdown. Those runs used 64 KiB shutdown/idle-growth limits.
The subsequent Linux service failure exposed a counter-scope mismatch; the
[CI investigation](mojo-service-ci.md) records the correction and its sensitivity limitations.

Mojo allocator call/free counts are unavailable in this adapter. Its public process malloc live
deltas include SDK and native libraries; JSON marks call/free/requested-byte counts null. Separate
process RSS and bounded lifecycle growth remain available. This is a measurement limitation, not
evidence of zero allocations. See the [full baseline table](mojo-benchmark-macos.md). Mac timing
is exploratory and has no enforced CPU affinity; CI measures candidates on one allowed Linux CPU.

Snapshot, seed and Rust handles have one explicit release owner and copied aliases, matching the
Odin lifetime convention. They do not claim compiler-enforced unique foreign ownership. Native
Mojo owns codec/identity/framing/queue policy; the narrow helper supplies public OS/ABI observations.
Executables require the pinned SDK shared runtime and native libraries, with no Python runtime.
There are no private task/compiler hooks, injected compiler IR or dependency source patches.

One local rebuild encountered a transient crash in the unchanged Odin compiler. Its isolated and
complete reruns passed without flags, patches or source changes; no workaround was introduced.

General multi-target validator networking, independent JAM-stack interoperability, full-ring
production sizing and crypto/backend security review remain common future work. This report
establishes bounded POC parity, not production readiness or a language winner.

## Reproduce and inspect

The [Mojo guide](../docs/mojo.md) lists every shared command. Linux CI runs all with `--mojo`.
The [machine-readable local record](mojo-parity-macos.json) retains source/evidence hashes,
resource observations, crypto counts and complete benchmark distributions/provenance. Raw logs
and individual samples remain under `build/mojo-gate`, `build/quic`, `build/integration`,
`build/offload` and `build/bench`; CI retains their diagnostic artifacts.
