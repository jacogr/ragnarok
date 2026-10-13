# Optional blobs, work outputs and preimage extrinsics

Normative basis: Gray Paper **v0.7.1**, commit
`1c979cb59bb800f92ffff083a2701004dfc6cd33`, Appendix **C.1.3**
(discriminators) and **C.2** (block serialization), specifically `maybe`,
`encodepreimages` and the work-output operator `O` in
[text/serialization.tex](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/serialization.tex).
Official fixtures retain vector commit
`1dc503af37ae8ecc7b6e24a393f6102801c0c80c`; hashes are in `pins.json`.

## Wire formats

Here `E` is canonical general-natural encoding, `E4` is four-byte unsigned
little-endian encoding, and `blob` bytes have identity encoding.

| Schema | Encoded form |
| --- | --- |
| Absent optional blob | `E(0)` |
| Present optional variable blob | `E(1) + E(blob.length) + blob` |
| Successful work output | `E(0) + E(blob.length) + blob` |
| Work error | `E(tag)` only |
| Preimage extrinsic | `E(recordCount) + (E4(service) + E(blob.length) + blob)*` |

Work-error tags are 1 out-of-gas, 2 panic, 3 bad exports, 4 oversize, 5 BAD,
and 6 BIG, exactly as C.2 specifies. Unknown discriminators are rejected before
constructing enum/union values. Overlong natural discriminators are rejected,
including optional absence encoded as `80 00`.

The optional API explicitly chooses a **variable blob** as its payload schema;
other optional types require their own payload codecs. Preimages preserve wire
order. These functions implement serialization, without imposing state-transition
rules such as preimage ordering/uniqueness or protocol resource constants.

## API, storage and failure

Implementations live in `nim/src/composite.nim` and `odin/codec/composite.odin`.
Both expose optional, work-output and preimage encode/decode functions. Nim
uses `OptionalBlob` and `WorkOutput` variant objects; Odin uses `Optional_Blob`
and the native `Work_Output` union of `Blob_Span` and `Work_Error`. A nil union
or an explicitly cast error outside tags 1..6 is invalid. `ServiceIndex` /
`Service_Index` is nominally distinct from raw uint32.

Encoders receive descriptors, a borrowed byte pool, explicit typed limits and
caller-owned output. `BlobSpan` / `Blob_Span` contains an offset and length,
not a retained pointer. Negative/overflowing/out-of-pool spans fail before
indexing. Absent optionals and work errors ignore unused blob storage.

Decoders borrow input. Optional/work success views refer to that original input;
preimage decoding initializes a caller-provided record array with input-relative
spans. Keep the corresponding input/pool alive and unchanged while using these
spans. Never reuse a span against a different pool without validating its meaning.
Successful prefix decoding returns `consumed`; trailing fields are left to the
caller. Require `consumed == input.length` when decoding a standalone frame.

`PreimageLimits` / `Preimage_Limits` independently bounds record count,
per-record blob bytes and aggregate blob payload bytes. The aggregate budget
excludes tags, length headers and service fields. Caller-selected policies are
not asserted to be normative JAM limits. Blob-only APIs require a `ByteLimit`.
Claimed counts are checked before host conversion and memory-size multiplication;
the minimum five-byte preimage record proves a count cannot exceed input extent.
Blob sizes use subtraction checks and remaining aggregate budgets.

Check `error == None` before using any result. Errors include truncation,
noncanonical prefixes, unknown tags, invalid source spans, policy violations,
insufficient output, aliasing and unrepresentable typed memory sizes. Failures
report zero consumed/count/written and preserve **all** destination contents.
Preimage decode performs complete validation before its second, committing pass;
source input must remain stable throughout the call.

Output writes must not overlap any borrowed byte pool, record descriptors or
input, including unused/trailing source bytes. Empty written record spans do not
alias. Payload-free variants borrow no payload and need only one output byte.
The overlap checks compare address differences without adding pointer endpoints.

Production functions allocate no heap memory. Nim uses ARC and declares
`raises: []`; no references/cycles are retained. Odin uses no allocator. Trusted
local batch adapters allocate utility storage and cap actual buffers at 32 KiB
and record destinations at 256; production limits remain caller-selected.

## Adapter requests and verification

`nim/tests/composite_driver.nim` and `odin/composite_driver` accept:

```text
OE <presence 0/1> <blob limit> <byte capacity> <payload hex>
WE <tag 0..6> <blob limit> <byte capacity> <payload hex>
OD <blob limit> <wire hex>
WD <blob limit> <wire hex>
PE <items limit> <per-blob limit> <aggregate limit> <byte capacity> <service:hex;service:hex>
PD <items limit> <per-blob limit> <aggregate limit> <record capacity> <wire hex>
```

A dash denotes empty hex or an empty record list. Encoder output is hex;
decoder output includes typed values and consumed length. Failed operations
print lowercase error names with underscores removed. Adapters additionally
assert exact successful re-encoding and unchanged failed destinations.

The shared runner uses an independent Python reference and unmodified official
fixtures. Tiny/full preimage frames are encoded and decoded **in full**. Official
work-result fixtures validate only the `O` field; surrounding fields establish
its exact offset/extent. Full work digests are now implemented in the [next slice](work-digest.md);
its suite verifies these fixtures as complete tuples.
See [the executed verification report](../results/composite.md).
