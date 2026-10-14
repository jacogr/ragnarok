# Integrated codec, crypto and QUIC verification

Date: 2026-10-14. The composed slice passes locally on macOS 27.0.1 arm64 in both languages.
Linux CI includes the new step; this increment awaits a pushed Linux run.

The [contract and workload](../docs/integration.md) use the unchanged Gray Paper v0.7.1 C.2
work-digest codec and Blake2b-256 primitive, plus pinned JAMNP-S v1 CE 143. Serialized digests are
test preimages, not a new CE protocol schema. No crypto signature/domain or work-output hash
relationship is invented. All source/compiler/dependency pins remain unchanged.

## Final integrated results

Both separately compiled checked native peers passed 10,000 arbitrary-input composition cases
before networking, including default failure and source-buffer overwrite/serialization checks.
Odin's tracker returned to zero per case. The native fuzz entry points need no UDP or fixtures.

The default persistent workload passed:

- Two long-lived listener engines, twelve waves each, three simultaneous peer identities per wave.
- 72 authenticated client connections and 576 settled streams across Nim/Nim, Odin/Odin and both
  cross-language directions.
- 216 healthy, hash-bound owned digest replies, including valid work-error variants.
- 288 expected rejections: 72 each for malformed codec, trailing bytes, missing key and wrong-hash
  response. All failures preserved healthy siblings and the shared listener.
- 72 cancelled one-MiB replies, each reaching a validated owned snapshot and real backpressure
  before its final native close released that snapshot.
- Every idle barrier had zero authenticated connections and zero live application stream slots.
- Source scratch/receive bytes were overwritten before owner serialization and crypto verification.
  Successful responses therefore did not depend on retained mutable buffers or detached spans.

The fixture harness independently checked all four official tiny/full work-result JSON/binary pairs
against the Python mathematical codec oracle. The served corpus uses two unmodified official
frames, two authored service-ID variants, truncated/trailing derivatives and two authored digests.
Python's Blake2b-256 computes every corpus key. A wrong-hash response is explicit integration-only
fault injection after successful owner serialization, leaving its immutable snapshot unchanged.

Final listener resource observations:

| Observation | Nim | Odin |
| --- | ---: | ---: |
| Sampled peak RSS, bytes | 24,084,480 | 28,999,680 |
| Sampled OS threads | 1 | 1 |
| Sampled peak descriptors | 6 | 5 |
| Idle RSS range after four warmup waves, bytes | 131,072 | 65,536 |
| Idle descriptor variation | 0 | 0 |
| Idle language allocation variation, bytes | 0 | 0 |

All existing finite service budgets passed. Nim ended at 80 occupied bytes against a 64-byte
pre-service baseline. Odin ended with zero tracked application bytes and zero pending nbio
operations, retaining just one receive and timer while listening idle. Fixture banks were released
after native destruction and final stream closes.

These sampled totals are not performance rankings or proof of leak freedom. Nim's count includes
live selector storage and retains its checked serialization with each stream; Odin's tracker
excludes process-lived dispatcher storage and deletes serialization scratch after copying it.
Neither counter attributes C/TLS allocations. Both use synchronous bounded hashing on the I/O thread.

## Regression verification

Executed from the repository, using the existing native builders and pinned toolchains:

```sh
python3 interoperability/test_codec.py
python3 interoperability/test_crypto.py
python3 interoperability/test_quic.py
python3 interoperability/test_quic_soak_harness.py
python3 interoperability/test_quic_soak.py --skip-build
python3 interoperability/test_quic_service.py --skip-build
python3 interoperability/test_integration.py --reuse-native
python3 tools/format.py --check
git diff --check
```

All commands passed on the final source:

- Codec: 185,373 shared requests per implementation across the five existing suites, native
  owned/borrowed tests, official vectors and negative compilation checks. The full digest suite
  included 14,278 shared requests and eight complete official checks.
- Crypto: all four debug/release native suites, five RFC 8032 cases, 151 Wycheproof cases,
  56 independent hash messages per algorithm, ownership/concurrency tests, six negative type
  probes and 32 cross-provider signed messages. The known Ed25519 acceptance difference remains.
- Ordinary QUIC: all 64 authentication/protocol pairs, native 10,000-input parser selftests and
  256-operation I/O retirement/cancellation selftests per language.
- Lifecycle: all five soak-harness regressions and all 160 same-process sessions.
- Persistent service: all 32 multi-peer waves, 132 promoted/retired connections and resource checks.
- Integration: 20,000 composition cases and all 576 stream outcomes after the final rebuild.
- Formatting: 84 source files; whitespace diff checks passed.

Local regression logs and integrated build/results/peer/resource diagnostics remain in ignored
`build/integration`. The Linux workflow reuses its already verified native crypto/QUIC builds,
recompiles the integrated peers and uploads only explicit logs/JSON. TLS private keys and fixture
files are excluded. Bandersnatch sources/APIs were unchanged and its suite was not rerun here.

## Implication and remaining scope

Both languages now have concrete evidence for composing checked codec/crypto results with async
transport, immutable buffer ownership, per-stream rejection, blocked-write cancellation and orderly
cleanup. The native application glue differs, but neither requires a connection thread or upstream
source patch. This strengthens viability evidence without selecting a winner.

The slice remains IPv4 loopback with fresh client engines and a fixture database. It does not
validate JAM state, demonstrate independent-validator interoperability, exercise outgoing-engine
reuse, resolve the Ed25519 policy gate, or evaluate expensive Bandersnatch scheduling.

The next proposed bounded round is optimized measurements on the same Linux host and corpus,
including M1 encode/decode speed, borrowed/owned allocation costs, latency and maintainer
maintainability review. It awaits the next go-ahead; no benchmark conclusions are drawn here.
