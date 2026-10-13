# Fixed-width unsigned integer codec

## Normative definition and scope

This increment implements Gray Paper **v0.7.1**, commit
`1c979cb59bb800f92ffff083a2701004dfc6cd33`, Appendix **C.1.7**, Fixed-length
Integer Encoding. [Pinned source](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/serialization.tex).
The revision and official vector snapshot remain those in [pins.json](pins.json).

For a requested width l, the normative encoder maps integers
0 <= x < 2^(8l) to exactly l octets. It emits x modulo 256 first, followed by
the encoding of floor(x/256) in l-1 octets: ordinary little-endian order.
For example, x = 4660 (0x1234) at width two produces `34 12`.

The native API supports **every width 0..8**, using a uint64 value domain.
The paper defines larger widths mathematically; requested widths above eight
are outside this increment and return InvalidWidth. Larger-than-uint64 values
are outside the native value type and require checked conversion by callers.
Signed integer encoding is not inferred from this unsigned definition.
No specification, compiler, formatter or dependency revisions changed.

Width zero has domain N_1 = {0}. Thus encoding zero emits the empty sequence,
encoding any nonzero value fails, and decoding consumes zero bytes and yields
zero. This holds even when the input contains bytes for subsequent fields.

## Checked APIs

| Concept | Nim | Odin |
|---|---|---|
| Value | `FixedUnsigned`, distinct uint64 | `Fixed_Unsigned`, distinct u64 |
| Requested byte count | `ByteWidth`, distinct int | `Byte_Width`, distinct int |
| Encoder | `encodeFixed(value, width)` | `encode_fixed(value, width)` |
| Decoder | `decodeFixed(input, width)` | `decode_fixed(input, width)` |

Value types distinguish fixed-width encoding from the existing general-natural
codec, as well as from ordinary machine integers. A raw value, raw width or
general-natural value cannot be passed implicitly to the fixed encoder;
negative compilation fixtures check all three distinctions in both languages.
The signed width wrapper allows callers to report invalid external counts
through typed errors, rather than risking a range-conversion exception.

Both APIs validate width **before** shifts, array indexing or buffer-length
checks. Valid widths below eight must satisfy x < 2^(8l) before encoding,
so significant bits are never silently discarded. Width eight skips that
comparison to avoid a shift by 64 and accepts all uint64 values.
Decoding requires the full requested width before accessing input. It never
pads missing bytes or treats a short prefix as a valid smaller integer.

| Error | Meaning |
|---|---|
| InvalidWidth / Invalid_Width | The requested count is negative or exceeds eight. |
| ValueOutOfRange / Value_Out_Of_Range | A valid requested width cannot represent the encoder's value. |
| Truncated | A valid decoder width exceeds the available input bytes. |

There is no canonicality error for fixed-width integers: high zero octets are
required when the field width calls for them. Every complete byte pattern is a
valid value for its width. There is no decode-overflow case for widths 0..8;
eight octets reconstruct at most uint64 max.

Nim results are tagged objects: check `ok` before reading the encoded output
or decoded value/consumed count. Failure exposes only the typed error.
Both functions declare `raises: []`. Odin results have an error field; `.None`
means success, while failures return zeroed output/value/consumed fields.
No decoder modifies a cursor: callers advance only after success, by exactly
`consumed`. Trailing bytes remain with the caller.

The encoder returns owned, fixed-size eight-byte value storage and a used-byte
count. The decoder borrows its input only during the call and never retains it.
Neither implementation allocates, uses FFI, or contains reference cycles.
Nim continues to build with ARC. There are no allocator lifetime requirements
beyond keeping the borrowed input alive for the call.

## Verification and fixtures

Project fixtures in `vectors/fixed-unsigned-boundaries.json` record decimal
values as strings and cover widths 0..8, minima/maxima, internal zero bytes,
and a recognizable ascending-byte pattern to expose byte-order mistakes.
These are specification-derived project fixtures, not official vectors.

The existing unmodified, hash-checked official tiny/full ticket and preimage
fixtures provide fixed-width fields under Appendix C.2:

- Ticket attempt/entry index: E_1, one octet.
- Preimage requester/service index: E_4, four octets.

The harness locates those fields using corresponding JSON data and verifies
all surrounding bytes and offsets. It performs 24 native encode/decode field
checks across the two chain variants. These are primitive field checks;
full composite vector decoding is not claimed. There are no standalone
fixed-integer vectors in the pinned official codec directory.

The shared reference uses Python `int.to_bytes`/`int.from_bytes` with explicit
little-endian order and checked bounds, separately from either native loop.
The production code remains independent in each language.

Native `fuzzFixed` / `fuzz_fixed` entry points verify error precedence and exact
re-encoding of every accepted prefix. For externally generated cases, the
fixed adapters accept `FE <signed width> <uint64 value>` or
`FD <signed width> <hex bytes>`, with up to 64 input bytes per request.
They load trusted local batch files into memory, use checked textual number
parsing, and print hex, `value consumed`, `invalidwidth`, `outofrange`,
`truncated` or `inputerror`. Empty hex and empty encoded output are valid.

Byte strings, sequences, composite types and new domain-specific indices
remain outside this increment. The next bounded byte-string/sequence round
requires the maintainer's go-ahead.
