# Natural-number codec baseline

## Normative references

- Gray Paper **v0.7.1**, commit
  `1c979cb59bb800f92ffff083a2701004dfc6cd33`:
  [Appendix C source](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/serialization.tex).
  C.1.1 (Trivial Encodings, general natural-number definition),
  C.1.3 (Discriminator Encoding), C.1.7 (Fixed-length Integer Encoding),
  and C.2 (Block Serialization, ticket/preimage extrinsics).
- [Official vectors](https://github.com/w3f/jamtestvectors/tree/1dc503af37ae8ecc7b6e24a393f6102801c0c80c/codec),
  commit `1dc503af37ae8ecc7b6e24a393f6102801c0c80c`, advertised protocol 0.7.1.
- Machine-readable revisions, compiler versions and fixture SHA-256 digests:
  [pins.json](pins.json).

The current Gray Paper master was 0.8.0 when inspected. Version 0.7.1 was
selected to match the official vector suite. Upgrading is a separate change;
this baseline does not claim conformance to newer protocol versions.

## Implemented behavior

The domain is 0 through 2^64 - 1 (the paper's N_(2^64) is exclusive at its upper
bound). These are JAM general naturals, used for length discriminators; they
are not SCALE compact integers, LEB128 or fixed-width integers.

For x = 0, emit 00. Otherwise, for 0 <= l < 8 and
2^(7l) <= x < 2^(7(l+1)), emit a header
256 - 2^(8-l) + floor(x / 2^(8l)), then l little-endian payload octets.
For x >= 2^56, emit ff followed by eight little-endian octets.
No arithmetic or shift needs a width larger than 64 bits.

A decoder counts leading one bits in the header to find the payload length.
It validates the available bytes before accessing them and reconstructs at
most 64 bits. Every possible header is assigned; there is no unused tag.

The paper defines deserialization as the inverse of serialization. We interpret
this as accepting only the image of the piecewise encoder: a representation
using l payload octets must encode x >= 2^(7l), for l > 0. Overlong forms,
including ff followed by a value below 2^56, therefore return NonCanonical.
This interpretation follows the normative definition; no permissive decoder
mode or protocol deviation has been introduced. There is no open ambiguity
for this primitive at the pinned revision.

## API and ownership

- Nim: `JamNatural` is distinct from uint64. `encode` returns an
  `EncodedNatural` containing nine bytes and a length in 1..9. `decode` accepts
  a borrowed openArray and returns a tagged `DecodeResult`: success has a
  value and consumed count; failure has `truncated` or `nonCanonical`.
  Both functions declare `raises: []` and allocate no heap memory. Compile
  with `--mm:arc`. There are no references or reference cycles in this codec.
- Odin: `Natural` is distinct from u64. `encode` returns a value struct
  containing nine bytes and a length. `decode` accepts a borrowed slice and
  returns `Decode_Result`. Error `.None` means success; `.Truncated` and
  `.Non_Canonical` return zero value/consumed count. No allocator is used,
  input never escapes, and returned storage belongs to the caller.

Decoding consumes one canonical prefix and leaves trailing bytes to the caller.
It does not cast a decoded natural to a host int or allocate a claimed sequence
length. Future sequence decoders must check their own length/resource limits
before such conversions or allocations. A natural's header/payload cannot
express more than 64 bits, so there is no additional decode-overflow case.
Raw integer variables require an explicit conversion to the domain type;
negative compilation fixtures verify this in both languages.

Only the general-natural API is public in this increment. Fixed-width integers,
byte strings, sequence cursors and composite structures remain subsequent work.

## Test fixtures

`vectors/natural-boundaries.json` contains project fixtures derived from the
normative formula, with decimal values stored as strings to preserve all 64
bits. They cover the transitions between all nine encoded sizes and uint64 max.
They are not official vectors.

`vectors/official` contains unmodified tiny/full ticket and preimage extrinsic
JSON/binary files from the pinned official repository, plus its CC0 license.
The runner checks file hashes, tests outer sequence lengths and all preimage
blob length prefixes, and verifies the JSON/binary offsets used to locate
those prefixes. This is **20 primitive prefix checks**, not a complete decode
of any composite structure. No standalone general-natural vectors exist in
that revision's codec directory; full composite vector conformance remains open.

The Python reference is a test-only evaluation of the paper's piecewise formula.
Neither native implementation delegates codec behavior to it or to C.
