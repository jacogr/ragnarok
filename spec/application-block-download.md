# Application block download

## Authority and scope

Use pinned JAMNP-S `439c45aad135dc654b3de6f56d7d694fd02b7aa8`, `simple.md`
Streams, Messages, Notation and CE 128. Request bytes are stream kind 128,
E4(37), the selected sealed-header hash, direction 0 and E4(1). This bounded
producer requests one ascending exclusive child.
[Separate bounded ancestor acquisition](application-remote-ancestors.md) uses
descending responses for immutable report context. This producer does not adopt
backwards or request multiple canonical children in a single response. Responses contain one E4-framed sequence of GP
blocks, without a compact element-count prefix. GP 0.8.0 and vector pins remain
those in the existing block-input/candidate contracts.

## Contract and completion tests

One non-copyable download owner captures the exact selected application context
and explicitly bounded ancestor handles before emitting a request. No caller can
substitute the starting hash or request more than one block. A local monotonically
increasing generation protects fragmented response/cancellation callbacks.

Receive the four E4 header bytes incrementally, checking the complete claim against
explicit block/codec/host limits before allocation. Feed only the declared body to
BlockInput. Short framing, extra bytes and a second message retire partial input
with typed reasons. A zero-length message is a valid empty sequence and yields
Empty after both directions finish, without allocating a candidate. Both the
request's queued FIN and response's actual FIN are required for Ready/Empty;
complete bytes alone authorize no producer work. Reset/cancellation retires only
the identified generation. The caller retains native stream owners through close
and enforces its transport deadlines; the download owns no native handle/thread.

Reception performs no decoding, hashing, execution or publication. Explicit enqueue
outside callbacks delegates complete single-block decoding/preparation/adoption
policy to Services. Its existing handoff backpressure preserves Ready input before
any expensive work. Terminal preparation failure retains only its actual failed
child; successful enqueue releases raw reception and still waits for a later
service tick. Empty/failure results require explicit cancellation/acknowledgement
before receiver reuse. A changed selected history cannot authorize stale work.

Check independent literal request bytes, every frame split, byte-at-a-time header,
early/exact/no FIN, empty response, oversized/trailing/second-message/multiple-block
payloads, wrong generation, cancellation and reuse, source mutation and typed child
failures. Exercise a real pinned LSQUIC stream with an independently framed signed
block response, then real guest preparation and later canonical adoption. Verify
premature close/cancellation without hashing, malformed-response teardown and fresh retry.
Native reset callbacks use generation-checked cancellation; the real transport
fixture distinguishes its close API from a wire-level RESET_STREAM observation.
Retain privacy, nominal, composite-copy and selected-result runtime guards, repeated
ARC release, affected input regressions, inventory, tooling and pinned formatting.

## Observed verification

Checked optimized native `application_block_download` passes independent request
bytes, defensive request-array copying, every two-fragment split with caller-byte
mutation and genuine guest execution, both FIN orderings, empty/truncated/oversized/
trailing frames, multiple-block refusal, stale generations and selected-history
refusal. Real authenticated LSQUIC streams pass oversized response, premature close,
complete-body-without-FIN cancellation and healthy signed-block transfer. Preparation
occurs after native callback teardown; canonical adoption waits for the later service
tick. All reception/native callbacks perform zero observed Blake2b calls. Handoff
backpressure retains Ready bytes without decoding/hashing.

The 1,000 alternating complete/partial framing cancellation cycles retain 8,806,720
occupied bytes before and after. Three privacy probes, one nominal generation
probe, the composite copy rejection and six strict runtime extraction probes pass;
the latter includes genuine successful admission refusing failure extraction.

Fresh certificate/report fixture selection and exact multi-library profile checks
pass with 99 affected Python harness tests. Inventory passes with 207 native suites,
142 failure families and 1,896 declared probes. Pinned Nim/Rust formatting and
whitespace checks pass. Existing raw-input/producer/handoff implementation trees
are unchanged; their prior regression results remain applicable and the new suite
exercises their request-adapter integration. Results are local macOS evidence;
full/Linux verification remains separately requested CI evidence.

## Remaining work

The [native stream controller](application-download-stream.md) now supplies bounded
read/write routing, callback identity checks and total transfer deadlines. The
development proof-peer commands retain their existing workloads. Live block
selection/retry scheduling, production command wiring and execution workers remain
open. No consensus finalizability decision, block-serving policy, durable restart
or full/light database mode is introduced. M1 framing is complete; full state
serialization and JAM/STF parity remain open.
