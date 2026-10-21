# Remote ancestor context

Scope: bounded CE 128 descending-inclusive responses supply immutable sealed parent
headers for existing report admission. Authority is pinned JAMNP-S revision
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`, `simple.md` CE 128, and the existing
GP 0.8.0 block/header codecs. Pins and protocol behavior do not change.

A request binds the exact known child's parent hash, its slot and an explicit
positive E4-sized maximum. Response payload is an uncounted sequence of complete
GP blocks. Empty and shorter-than-maximum responses are valid protocol outcomes;
empty exposes no headers. Every sealed header must hash to the previously expected
parent and have a strictly older slot. Decode the complete extrinsic to determine
block boundaries; header identity alone does not validate historical execution,
signatures, extrinsic commitments or finality. Existing report admission keeps its
own complete linkage, profile, lookup-child and state-root checks.

Response bytes, per-block codec resources, retained header bytes and header count
have independent explicit limits. Check arithmetic and descriptor bounds before
allocation/access. Failures expose no captured prefix and retain exact nested
block codec reasons. Returned sequence storage is independent of the immutable
response owner. No StateStore, storage, Services, finality or canonical history is
modified by acquisition.

Completion witnesses: independent literal request bytes, genuine descending
chains, exact/short limits, shorter responses, empty/truncated/suffixed bodies,
wrong first identity, reordered/duplicate/unrelated parents, strict slots, default
owners/results, late failure atomicity, detached ownership and repeated ARC release.
Streaming FIN, transport retirement, command wiring and actual network operation
remain separate layers. M1 framing is complete; full serialization/JAM parity remain open.

## Response evidence

The focused native `application_ancestor_response` suite passes, including literal
E4 request bytes at the full u32 maximum, genuine composed three-parent responses,
shorter valid replies, duplicate parents, late block truncation and an extra
message/body suffix. Independent copies cannot replace retained header owners.
Its final 1,000-cycle success/late-refusal ARC observation retains 358,512 occupied
bytes before/after. Four strict runtime extraction failures with genuine positive
controls, six private-field rejections and verification inventory pass locally.
Evidence: `build/remote-ancestors-{unit,guards,inventory}.log`. This is local
macOS/ARC evidence, without a Linux CI or complete JAM parity claim.

## Fragmented receiver

`AncestorReceiver` owns one E4-framed payload and monotonically increasing local
generation. It checks the complete u32 claim against the explicit host-sized
response ceiling before allocating. Callbacks copy only the declared body;
truncated framing, trailing bytes and oversized claims release the entire buffer.
Both request FIN and actual response FIN are required before explicit producer
decoding. Late/foreign generations cannot append, finish or cancel a reused owner.
Native consumers must retire their stream callback binding before decoding/reuse.

`application_ancestor_receiver` passes every split, byte-at-a-time reception,
both FIN orders, all early EOF offsets, empty reply, extra bytes, quota refusal,
stale/cancelled generations and detached response ownership. Five runtime
extraction failures/positive controls, three privacy checks, actual `=dup`
lowering rejection and inventory pass. Its 1,000-cycle ARC observation holds
276,576 occupied bytes before/after (`build/ancestor-receiver-*.log`).

## Native stream binding

`AncestorStream` binds one receiver address/generation to one native stream,
checks all callback identities and uses explicit per-callback read/write bounds.
Partial request writes retain their exact offset; only actual native EOF supplies
response FIN. Reset, deadline and cancellation stop I/O but retain the native
handle until its final close callback. The exclusive binding's destructor checks
that this retirement occurred; actual duplication lowering rejects copies.

The focused `application_ancestor_stream` suite passes real TLS healthy/empty,
oversized, premature-close, no-FIN, deadline and reset scenarios. An independent
finite responder validates every literal descending request byte and request FIN.
One-byte input/output fragmentation and foreign/replayed callback checks pass.
The independent primitive observer reports zero hash calls during reception;
producer decoding occurs only after native teardown. Ownership rejection and
inventory pass (`build/ancestor-stream-*.log`). Peer pin selection and command
integration remain subsequent layers; no remote CI was requested.

## Pinned outgoing peer

`AncestorPeer` owns one outgoing endpoint, receiver and stable callback aggregate.
It checks the actual TLS certificate against the selected Ed25519 pin before
opening one local stream. A host-supplied monotonic total deadline covers handshake,
transfer and final stream retirement. Backward ticks reject without changing the
captured deadline. An unsolicited/late open cannot replace a live binding. Ready
requires both FINs and actual native close; only then may the host decode headers.
Explicit close retires callbacks before buffer release/reuse or aggregate destruction.

`application_ancestor_peer` passes actual pinned TLS healthy/empty replies, wrong-key
zero-request refusal, oversized/premature responses, no-FIN timeout, backward time,
invalid policy/endpoint/request, partial startup and explicit idempotent retirement.
Captured immutable headers survive full endpoint/receiver cleanup. Four privacy
checks, actual composite duplication lowering rejection and inventory pass locally
(`build/ancestor-peer-{unit,guards,inventory}.log`). Command acquisition and existing
report-admission integration remain subsequent work.
