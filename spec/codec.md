# Primitive codec baseline

The primitive equations below remain implemented. Current source/vector identities and broader
codec/state coverage are summarized in [the serialization status](jam-serialization-status.md).
The release-vector references below are historical fixture provenance, not current dependency pins.

## Normative references

- Current unreleased Gray Paper **0.8.0**, commit
  `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`:
  [Appendix C source](https://github.com/gavofyork/graypaper/blob/1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d/text/serialization.tex).
  C.1.1 (Trivial Encodings, general natural-number definition),
  C.1.3 (Discriminator Encoding), C.1.7 (Fixed-length Integer Encoding),
  and C.2 (Block Serialization, ticket/preimage extrinsics).
- [Official vectors](https://github.com/jam-conformance/jam-test-vectors/tree/d3c089c9a1d5352ad353626d7a2db8589f137b2a/codec),
  commit `d3c089c9a1d5352ad353626d7a2db8589f137b2a`, release v0.8.0.
- Machine-readable revisions, compiler versions and fixture SHA-256 digests:
  [pins.json](pins.json).

Production follows the unreleased source commit above and the gp-next vector revision
in `pins.json`. The release-vector links retain the exact origin of the unchanged
primitive fixtures, rather than identifying the active gitlink. The
[coordinated upgrade](graypaper-unreleased-upgrade.md) records current adoption;
[the release migration audit](graypaper-0.8.0.md) remains historical evidence.

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

See [the Nim codec guide](../docs/codec.md) and source modules under `src/codec/`.
Independent references, official vectors, boundary/fuzz and failure-atomicity checks live under `tests/`.

### Nimony natural-result safety

On the `nimony` branch, `DecodeResult` keeps its Boolean-tagged representation but hides the
success discriminator, decoded natural, consumed extent and failure reason. `ok` is read-only;
`value` and `consumed` require success through Nimony `.requires`, while `error` requires failure.
A failed/default result cannot masquerade as zero or publish cursor progress, and successful
results cannot expose a default error reason. Default failure remains `truncated`.

The source module alone constructs successful results. Invalid public payload access is a
programmer contract error, rejected statically when proven or by a runtime guard otherwise.
Malformed wire data still returns its typed reason. No wire, canonicality, byte-limit or ownership
rule changes. The cumulative runtime verifier verifies failure/default accesses, success-side error
accesses and attempts to bypass private storage, alongside the existing boundary and fuzz checks.
