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

See the [natural codec](../src/codec/natural.nim) for the header and tail layout.
The decoder interprets deserialization as the inverse of serialization. It rejects
overlong forms, including ff followed by a value below 2^56.

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
