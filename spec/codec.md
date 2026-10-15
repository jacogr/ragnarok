# Primitive codec baseline

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

## API and validation

See [the Nim codec guide](../docs/codec.md) and source modules under `src/`.
Independent references, official vectors, boundary/fuzz and failure-atomicity checks live under `tests/`.
