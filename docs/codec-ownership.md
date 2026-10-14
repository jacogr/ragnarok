# Codec buffer ownership

Use the owned snapshot API for decoded data that will outlive its input or be
used after the input might change. It copies the validated consumed prefix into
private storage and keeps every nested blob associated with that storage.
Callers receive copied metadata and explicit copy-out operations, never a
mutable source slice or a detached span. No extraction or re-encoding operation
accepts a second source buffer.

The wire definitions remain pinned to Gray Paper v0.7.1
`1c979cb59bb800f92ffff083a2701004dfc6cd33`, C.1.2/C.1.3/C.2, using the existing
C.1.1/C.1.7 primitives. No fixture, compiler or dependency pin changes.

## APIs

Nim's implementation is `nim/src/owned.nim`; Odin's is `odin/codec/owned.odin`.
Both return checked success/failure results as described in
[the result guide](codec-results.md). An opaque frame has one validated schema;
metadata operations reject a different schema with `WrongSchema` /
`Wrong_Schema`, rather than returning default fields.

| Operation | Nim | Odin |
| --- | --- | --- |
| Decode byte string | `decodeOwnedBytes` | `decode_owned_bytes` |
| Decode optional blob | `decodeOwnedOptional` | `decode_owned_optional` |
| Decode work output | `decodeOwnedWork` | `decode_owned_work` |
| Decode preimages | `decodeOwnedPreimages` | `decode_owned_preimages` |
| Decode complete digest | `decodeOwnedDigest` | `decode_owned_digest` |
| Schema, consumed bytes, payload count | `ownedInfo` | `owned_info` |
| Optional presence/length | `ownedOptionalInfo` | `owned_optional_info` |
| Work tag/success length | `ownedWorkInfo` | `owned_work_info` |
| Copied digest fixed fields and metrics | `ownedDigestInfo` | `owned_digest_info` |
| Preimage service at index | `ownedService` | `owned_service` |
| Payload length at index | `ownedBlobLength` | `owned_blob_length` |
| Copy payload at index to caller output | `copyOwnedBlob` | `copy_owned_blob` |
| Emit validated canonical frame | `encodeOwned` | `encode_owned` |
| Release owner | ARC, automatically | `destroy_owned` |

A byte string, present optional, successful work output or successful digest
output has payload index zero, even if that payload is empty. Absent optionals
and work-error values have no payload indices. Preimages have one payload per
record. Negative or out-of-range indices return a typed error. Default/cleared
owners return `InvalidOwner` / `Invalid_Owner`.

Length, service, hash, gas and refinement metadata are copied values. Changing
those copies cannot change the frame. Optional absence and work errors carry
no successful payload length. Blob copies and frame emission require complete
output capacity before writing and leave the entire destination unchanged on
failure. Re-emission copies the frozen canonical prefix; it is not an API for
editing decoded fields.

## Nim example and lifetime

```nim
import src/[bounded, owned]

let parsed = decodeOwnedBytes(wire, ByteLimit(4096))
if parsed.error == OwnershipError.None:
  # This handle retains its private snapshot independently of wire.
  let frame = parsed.value
  let length = ownedBlobLength(frame, 0)
  if length.error == OwnershipError.None:
    # Extraction copies from the owner, with no second source pool.
    var payload = newSeq[byte](length.value)
    let copied = copyOwnedBlob(frame, 0, payload)
    doAssert copied.error == OwnershipError.None
else:
  # Failed results have no frame or payload metadata.
  handleError(parsed.error)
```

`OwnedFrame` contains a private reference to acyclic immutable storage. Copying
a handle retains that storage through ARC; it survives the original input's
scope. Snapshot sequences are newly allocated and populated byte by byte,
rather than sharing an input sequence. No tracing GC or reference cycle is
introduced. Nim allocation exhaustion follows its ordinary allocation-defect
behavior; it is not reported as a recoverable `AllocationFailure` here.

## Odin example and lifetime

```odin
parsed := codec.decode_owned_bytes(wire, codec.Byte_Limit(4096), context.allocator)
if codec.error_of(parsed) == .None {
    // One owner releases the snapshot; other handle copies only borrow it.
    frame := codec.success_of(parsed)
    defer codec.destroy_owned(&frame)
    length := codec.owned_blob_length(frame, 0)
    if codec.error_of(length) == .None {
        // The returned payload is caller-owned and can be modified independently.
        payload := make([]u8, codec.success_of(length))
        defer delete(payload)
        copied := codec.copy_owned_blob(frame, 0, payload)
        assert(codec.error_of(copied) == .None)
    }
} else {
    // Failure contains no snapshot to release.
    handle_error(codec.error_of(parsed))
}
```

`Owned_Frame` is an opaque nominal handle. Its internal storage type and helper
functions are private to the implementation file, using Odin's
[private declaration attribute](https://odin-lang.org/docs/attributes/).
Mutable bytes are not exported through public operations. Circumventing this
boundary requires explicit pointer casts or other unsafe access.

The decoder accepts an allocator (defaulting to `context.allocator`) and stores
it with the owner. It must support the required allocations and remain valid,
with its allocations intact, until release. `destroy_owned` releases through
that original allocator and clears the passed handle. Releasing a cleared
handle again is harmless. **Copied handles are aliases:** one owner releases
exactly once, and all aliases must stop being used at release. Odin does not
statically enforce this ownership/lifetime rule. Do not reset a backing arena
while a frame is live, or let its allocator state go out of scope first.

Allocation refusal, including nil storage returned without an allocator error,
is a typed `Allocation_Failure`. Failed decodes and failures at record, wire
or owner-header allocation clean up every temporary allocation.

## Cost and borrowed migration

Owned decoding deliberately adds copying and allocation to remove the original
buffer relationship from application calls. It retains only the consumed prefix,
not trailing frames. Preimage record allocation is checked against count policy,
minimum wire extent and representable typed storage size before allocating;
per-blob and aggregate policies still apply. This is not a benchmark or a claim
that snapshots are free. Applications still need an aggregate budget for all
live frames.

Input must remain alive and stable **during** decoding. After an owned decode
returns, mutating, freeing or reusing the original input cannot change the
snapshot. Concurrent writes during decoding are not supported.

Allocation-free low-level decoders are retained under explicit borrowed names:
`decodeBytesBorrowed`, `decodeOptionalBorrowed`, `decodeWorkBorrowed`,
`decodePreimagesBorrowed`, `decodeDigestBorrowed`, and the corresponding
`decode_*_borrowed` Odin names. Composite encoders taking detached spans and a
pool are likewise `encode*Borrowed` / `encode_*_borrowed`. Scalar codecs and
byte/sequence encoders are unchanged because they have no detached blob spans.

Those low-level functions still cannot enforce buffer identity, immutability or
lifetime. Using them opts into keeping the matching buffer alive and stable,
including throughout validation and commit passes. They are available for
controlled synchronous code and conformance tests; prefer owned snapshots at
application boundaries. Existing borrowed callers must migrate their names;
there are no ambiguous compatibility aliases.

See [the ownership verification report](../results/codec-ownership.md).
