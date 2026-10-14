# Owned codec, crypto and QUIC integration

This bounded decision slice composes the existing native-language M1/M2/M3 APIs. A CE 143 query
names a test preimage containing a complete serialized work digest. The server captures that digest
with the owned codec, checks its Blake2b-256 content key, and returns bytes serialized from its
immutable owner. The client captures the actual received digest and checks it against its retained
query key. Both peers overwrite borrowed receive/scratch bytes before serialization and hashing.

No new JAM protocol or signature domain is introduced. CE 143 permits arbitrary preimages;
**the digest schema is a fixture/application choice**, not a normative restriction on CE 143.
A digest's code/payload hashes are serialized fields, not assertions that its work output hashes to
those fields. The checked content key covers the entire serialized preimage. A decoded work-error
variant is a valid digest value and can be a healthy response.

## Specification and provenance

- Gray Paper v0.7.1, commit `1c979cb59bb800f92ffff083a2701004dfc6cd33`: C.1.1 canonical naturals,
  C.2 work-digest serialization and Cryptography's Blake2b-256 primitive. See
  [the existing digest interpretation](../spec/work-digest.md) and [crypto contract](../spec/crypto.md).
- JAMNP-S v1, commit `439c45aad135dc654b3de6f56d7d694fd02b7aa8`: Encryption and handshake,
  Protocols and streams / Messages, and CE 143. E4 message length and FIN remain network framing;
  the C.2 tuple uses its own canonical internal codec.
- Official tiny/full `codec/work_result_{0,1}` binary/JSON pairs remain immutable in the pinned
  `vendor/jamtestvectors` submodule. The harness checks all four with the separate Python codec
  oracle. Tiny/full bytes coincide, so authored service-ID variants distinguish two fault cases.
- A project-authored one-MiB successful digest exercises blocked writes and cancellation; another
  uses full-width gas/natural boundaries and a healthy reply after previous failures.

Compiler, native dependency and vector revisions are unchanged. No new dependency, source patch,
common C codec, or common C application policy is added. Nim uses its existing maintained crypto
ABI; Odin uses its existing core Blake2b adapter. Shared C remains transport/TLS machinery.

## Run and workload

```sh
python3 interoperability/test_integration.py --fetch
# CI, after the existing crypto/QUIC builds have passed:
python3 interoperability/test_integration.py --reuse-native
# Only after compiling current integrated peers:
python3 interoperability/test_integration.py --skip-build
```

The runner compiles separately labelled checked binaries in `build/integration`: Nim ARC with
`-d:integration` and Odin with `-define:INTEGRATION=true`, vet and strict style. Ordinary QUIC
binaries reject integration modes. Native libraries and builders are shared with the established
crypto/QUIC runners. Each integrated peer also runs a 10,000-input composition selftest without
sockets; successful random captures must re-serialize pre-mutation input, and failures contain
only typed reasons. Odin's tracker verifies no retained application allocation per selftest input.

Each persistent listener processes twelve waves of three simultaneous clients, crossing both
language boundaries and using different public identities. Each client settles eight streams:

| Slot | Preimage/query | Expected client outcome |
| --- | --- | --- |
| 0 | Official successful digest | Healthy owned decode and hash match |
| 1 | Official work-error digest | Healthy owned decode and hash match |
| 2 | Truncated digest | Server codec rejection |
| 3 | Valid digest with trailing bytes | Server standalone-frame rejection |
| 4 | Absent content key | Server lookup rejection |
| 5 | Codec-valid response with altered code-hash bytes | Client content-hash rejection |
| 6 | One-MiB digest; client withholds read credit then cancels | Pending owned snapshot released at native close |
| 7 | Healthy digest after earlier failures | Healthy owned decode and hash match |

The wrong-hash response is explicit test-only fault injection in integration mode. It never
mutates the immutable codec snapshot. The first five requests start together; the last three follow
on the same connection. Three clients share the listener, with one OS thread and one long-lived
engine. No worker or connection thread is introduced by composition.

## Ownership and error composition

`nim/quic/integration.nim` and `odin/quic/integration.odin` return checked alternatives: failures
contain only an integration error, and success contains an immutable owner plus its independent
serialization. The wrapper explicitly requires the codec's consumed count to equal the received
body length; prefix-decoder success alone cannot accept trailing data.

Fixture bank entries are bounded trusted harness inputs, loaded before callbacks. Network bytes
select only exact 32-byte keys; they never choose a path or allocation extent. The bounded owned
codec validates all fields before retaining data. Each stream holds its successfully captured
snapshot until native close, including when a write is parked behind 64 KiB transport credit.
Nim retains handles through ARC. Odin transfers exactly one release owner to the stream, deletes
serialization scratch after copying it, and destroys the snapshot at final close. Late capture
failures destroy temporary owners. Banks survive engine destruction and are released afterward.
Nim additionally retains the checked serialization with its stream owner; allocation totals are
observations of these implementations, not equalized allocation counts.

The harness checks exact healthy/rejected/cancelled counts and error categories, not just TLS
success. It requires a retained owned snapshot to reach the cancellation-close marker and observes
real backpressure. After each wave it requires zero authenticated connections and live stream
slots before sampling resources. The live listener keeps its I/O owner and fixture bank.

The same finite budgets as the service round apply: one OS thread, sampled RSS below 256 MiB,
post-warmup idle RSS range below 16 MiB, descriptor variation at most two and language allocation
variation below 64 KiB. Odin retains exactly one receive/timer while idle and ends with zero tracked
application bytes and I/O operations. Nim ends within 64 KiB of its pre-service memory baseline.
These counters do not attribute C/TLS storage, and allocator failures are not a claim of universal
recovery from process-wide memory exhaustion.

## Decision relevance and limits

This provides a concrete comparison of checked failure propagation, immutable snapshots, crypto
calls, callback ownership, cancellation and teardown in a composed native application. It is
IPv4 loopback CE 143 with a fixture database; it is not work-report import or state validation.
Blake2b is synchronous bounded work on the I/O thread. This round does not evaluate scheduling
expensive Bandersnatch operations or resolve the existing Ed25519 verifier-policy difference.

Outgoing engine reuse, IPv6, independent JAM implementations, loss/reordering and deeper native
allocation instrumentation remain open as previously recorded. Linux CI includes the integrated
workload and explicit diagnostic uploads; this increment awaits a pushed Linux run.

The next proposed bounded round is the optimized Linux comparison, explicitly including M1
encode/decode throughput, borrowed/owned allocation costs and latency on the same corpus and host,
plus maintainer ergonomics. No benchmarks or next increment start before the next go-ahead.
