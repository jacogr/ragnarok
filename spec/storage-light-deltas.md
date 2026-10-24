# Authenticated local light update frames

This standalone storage format records proof-cache edits at one independently selected chain
and complete state root. It changes no Gray Paper encoding, consensus root selection, application
startup or full-state interface. Caller-selected proof, image and transport policies remain
external. A checksum detects corruption; it never supplies root trust.

`prepareLightDelta` authenticates an atomic `update(proofs, forgotten)` against an initialized
prepared light image. Its opaque result retains the successor image and exact canonical frame,
without retaining a predecessor chain. `decodeLightDelta` verifies one exact frame against a
caller-supplied predecessor and positive expected sequence. `takeLightDelta` performs the same
verification and consumes its owned transport only on success. All failures preserve the input
image; consuming failures also preserve the caller buffer. Retained readers remain immutable.

## Canonical representation

All integers are fixed-width little endian. The 24-byte magic is
`RAGNAROK-LIGHT-DELTA-V1\n`, with one final newline. A frame has a 176-byte header, canonical edit
body, and 32-byte Blake2b-256 checksum of every preceding byte.

| Offset | Width | Field |
| --- | --- | --- |
| 0 | 24 | Magic |
| 24 | 32 | Independently selected chain identity |
| 56 | 32 | Independently selected complete state root |
| 88 | 32 | Exact predecessor light snapshot checksum |
| 120 | 32 | Exact successor light snapshot checksum |
| 152 | 8 | Positive expected local sequence |
| 160 | 8 | Edit count |
| 168 | 8 | Body byte length |
| 176 | variable | Edits |
| end minus 32 | 32 | Frame checksum |

Each edit contains a 31-byte state key, one-byte tag, two-byte proof-node count and eight-byte
raw-value length, followed by 64-byte nodes and raw value bytes. Tag zero forgets evidence and
requires both reserved counts to be zero; tag one admits an inclusion or exclusion proof.
All keys must be strictly increasing across both tags. Duplicate admissions, forgets and
cross-list conflicts have no representation. Encoding sorts private key descriptors without
modifying caller proofs. An empty update is a valid 208-byte frame and still carries a positive
sequence. Zero is reserved for a checkpoint baseline. Sequence exhaustion policy belongs to the
journal owner; decoding requires the exact positive sequence explicitly supplied by its caller.

The complete root is unchanged by evidence edits. An unknown key, authenticated absence and a
present empty value retain their distinct cache meanings. The successor checksum covers the
complete canonical light evidence image, so equal roots do not allow replay against another
predecessor cache.

## Bounds, verification and ownership

Frame byte and edit-count limits are independent of retained-image quotas. Source image limits
also bound writes, individual proof nodes and values, and the final cache. The hard proof depth
remains 249. Native descriptor counts, extents and arithmetic are checked before narrowing,
allocation or hashing. Decoding checks the complete body shape, strict key order, tags, reserved
fields and payload extents before checksum work or input-derived proof allocation. Only then
are proofs authenticated through the existing atomic light-image update. A valid frame checksum
with invalid evidence fails; a valid proof transition with the wrong declared successor fails.
Provider refusal never publishes a candidate.

`lightDeltaExtent` locates only the first complete bounded frame in a transport. It does not
verify its checksum, proofs or identity. Decoding requires exactly that one frame with no trailing
bytes. Available identity, predecessor and expected-sequence bytes are compared even for partial
input. `IncompleteFrame` grants neither an authenticated prefix nor repair authority: an
incomplete body can still contain malformed edits. Durable replay and any explicit partial-tail
repair must define and validate their own complete journal context.

Success and proof-error payloads have guarded getters; failed and default results expose no
completed transition. Default opaque handles safely report `initialized == false`; all other
getters require initialization. `encodedBytes` borrows read-only storage for the owner's lifetime.
`.bytes` returns independent mutable transport. Copies retain immutable authority; no API exports
mutable backing or an unchecked adoption path.

## Scoped evidence and remaining work

The checked ARC release native suite includes an independent Python `struct`/`hashlib` golden
empty frame, an independently rooted two-key inclusion/absence transition, every proper prefix,
trailing bytes, malformed metadata/body/lengths, exact limits, duplicate conflicts, stale replay,
valid-checksum invalid-proof and wrong-successor cases. It checks every observed hash-provider
refusal boundary, successful/failing consuming ownership, detached bytes and retained readers.
One thousand scoped success, late-refusal and retry cycles return occupied ARC bytes to baseline.
The existing atomic-batch suite also passes on the unchanged proof-image implementation.

Eleven runtime guard probes, nine positive controls, four strict private-field compiler
rejections and two actual native ownership-build rejections cover default/failed results,
reason selection, opaque storage, mutation and escaping a local borrowed owner. Format and
inventory checks pass. These are local macOS arm64 results with the repository-pinned compiler
and crypto sources, not exact-head Linux CI evidence.

This layer supplies a bounded authenticated transition codec. It performs no file I/O and does
not yet provide a journal selection format, replay owner, append durability, recovery, compaction
or application integration. Those are separate substantial storage review units. Existing M1
framing evidence remains distinct from complete state serialization.
