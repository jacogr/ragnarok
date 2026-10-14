# Bounded byte strings and fixed-width unsigned sequences

## Specification and scope

Gray Paper **v0.7.1**, commit
`1c979cb59bb800f92ffff083a2701004dfc6cd33`, Appendix **C.1.2** (Sequence
Encoding) and **C.1.3** (Discriminator Encoding) define concatenated element
encodings prefixed by the natural count for variable-length terms.
[Exact source](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/serialization.tex).
Natural counts use C.1.1; scalar elements use C.1.7. All revisions remain those
in [pins.json](pins.json).

This round adds variable byte strings and homogeneous sequences of
fixed-width unsigned integers. It does not claim a generic codec for arbitrary
nested element types, bit sequences, options, unions, or composite JAM types.

A byte string emits E(byte count) followed by its raw octets. A scalar sequence
emits E(element count), then each E_width(value) in order. The width is supplied
by the type's schema/caller and is **not encoded** in this sequence. Empty
containers emit `00`; they are different from empty input, which is truncated.
The sequence count is elements, not payload bytes. No length denotes capacity.

Width 0..8 is supported, matching the existing scalar primitive. Zero-width
sequences still carry a bounded element count. Each value must be zero and
consumes no payload octets; decoding initializes that many output zeros and
consumes only the count prefix.

## API and resource policy

| Operation | Nim | Odin |
|---|---|---|
| Byte encode | `encodeBytes(value, ByteLimit, output)` | `encode_bytes(value, Byte_Limit, output)` |
| Byte decode | `decodeBytes(input, ByteLimit)` | `decode_bytes(input, Byte_Limit)` |
| Scalar-sequence encode | `encodeSequence(values, ByteWidth, ElementLimit, output)` | `encode_sequence(values, Byte_Width, Element_Limit, output)` |
| Scalar-sequence decode | `decodeSequence(input, ByteWidth, ElementLimit, output)` | `decode_sequence(input, Byte_Width, Element_Limit, output)` |

Byte and element limits are distinct unsigned 64-bit types. Callers must
explicitly choose the application/schema limit. The codec introduces no
arbitrary consensus size constant. A limit of zero permits only an empty
container. Passing a raw uint64 limit, an element limit to the byte API, or raw
uint64 sequence elements is rejected by the compiler in both languages.

All operations return a typed `ContainerError` / `Container_Error`; `None`
means success. Failed operations have no metadata fields and leave destination storage
unchanged. Successful encoders report `written`. The byte decoder
reports `offset`, `length` and `consumed` into the original input. The sequence
decoder reports initialized output `count` and wire `consumed`.

| Error | Condition |
|---|---|
| Truncated | Missing count-prefix octets or incomplete declared payload. |
| NonCanonical / Non_Canonical | Overlong natural count prefix. |
| LimitExceeded / Limit_Exceeded | Declared/actual byte or element count exceeds caller policy. |
| OutputTooSmall / Output_Too_Small | Caller-owned destination cannot hold the completed result. |
| InvalidWidth / Invalid_Width | Sequence stride is outside 0..8. |
| ValueOutOfRange / Value_Out_Of_Range | Some encoder element cannot fit its fixed-width domain. |
| AliasedBuffers / Aliased_Buffers | Input and written output storage overlap. |
| LengthOverflow / Length_Overflow | Typed storage's byte-span size exceeds host-int representation. |

Sequence width validation precedes any wire interpretation or size arithmetic.
Decoders then check canonical count, caller limit and complete payload, followed
by output capacity/storage size and aliasing for sequences. Encoders check
width where applicable, policy, destination capacity, typed storage size and
aliasing, then preflight **all** sequence values before committing anything.
Thus a late out-of-range element cannot leave an earlier element or header
behind in output.

## Integer and memory safety

Untrusted counts stay uint64 until actual available input/output proves a
host-index conversion safe. Payload checks compare count to
`remaining_bytes / element_width` before multiplication; destination checks use
available capacity after the header. These proofs avoid overflowing length
products and additions. Zero stride skips division but still requires a bounded
count fitting the supplied typed destination before any loop or conversion.
Host-int extremes and canonical counts of 2^63 and uint64 max are tested.

The production APIs allocate no heap memory, retain no pointer, and use no FFI
or tracing GC. Nim keeps ARC and declares `raises: []`. Odin uses no allocator.
The byte decoder returns numeric indices instead of allocating a copy or
retaining a borrowed slice; callers use them with the same original input.
Sequence values are copied into supplied typed storage. The caller owns all
input/output buffers and keeps them alive during each call.

Input/output overlap is rejected rather than implicitly supporting in-place
transforms. Sequence decode protects the **entire** borrowed input, including
trailing fields, against its written typed output span. Address-range checks
use differences rather than unchecked pointer-plus-length arithmetic. Empty
spans do not overlap. Trailing bytes are otherwise unread and unchanged.
No cursor is mutated; callers advance only after success, by `consumed`.

## Fixtures and verification

The 13 inspectable project fixtures in `vectors/bounded-containers.json` cover
empty byte strings, natural-count transitions and all sequence widths. Numeric
values use decimal strings so JSON preserves uint64 max exactly. These are
project fixtures, not official vectors.

The pinned tiny/full official preimage fixtures contain six complete blob
spans. The runner verifies every surrounding service-index byte and offset,
then passes the original count-plus-payload bytes to each native blob decoder
and tests byte-exact re-encoding: **12 official blob checks**. Full preimage
extrinsic decoding is still outside this round. No standalone homogeneous
unsigned-sequence vector occurs in the copied official fixture subset; scalar
sequences are tested with independent mathematical references and project
fixtures, not presented as official composite conformance.

Native `fuzzBounded` / `fuzz_bounded` entry points validate byte-span/count-prefix
invariants, exact successful sequence re-encoding, and unchanged output on
failed decoding. Each native test suite runs 10,000 deterministic cases. Shared
adapters also assert failure atomicity for every failed encode/decode request.
The shared Python reference uses arbitrary-width arithmetic, a separate
natural-codec reference, and `int.to_bytes/from_bytes`; neither production
implementation delegates any codec logic to it.

The trusted-file adapters use these request forms:

```text
BE <byte limit> <byte output capacity> <payload hex>
BD <byte limit> <wire hex>
SE <width> <element limit> <byte output capacity> <comma-separated values>
SD <width> <element limit> <element output capacity> <wire hex>
```

A dash denotes empty hex or no values. Adapter input/output byte storage is
capped at 32 KiB and typed element storage at 512 entries. These are test-tool
bounds, not protocol limits. They allocate/load only actual trusted request
text and use checked textual numeric parsing. Production decoders never
allocate according to a wire claim. Responses are wire hex, payload/value
lists with consumed counts, or stable lowercase error labels.

See [the verification report](../results/bounded-containers.md). The next round
requires the maintainer's go-ahead before any nested or composite codec work.

The current [result API and migration examples](../docs/codec-results.md)
separate success data from failure reasons and preserve the borrowed-buffer
contract. This changes API access, not the normative wire formats above.
