# Complete work-digest codec

Normative basis: Gray Paper **v0.8.0**, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix **C.2**, equation
`encode(wd in workdigest)` in
[text/serialization.tex](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/serialization.tex),
and the `workdigest` tuple in
[text/reporting_assurance.tex](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/reporting_assurance.tex).
Gas is a uint64 domain; canonical general-natural encoding is defined over
uint64 by C.1.1. The existing compiler/spec/vector pins remain unchanged.

## Layout and types

| Field | Wire format | Nominal API type (Nim) |
| --- | --- | --- |
| Service ID | Four-byte little endian | `ServiceIndex` |
| Code hash | 32 bytes, identity | `CodeHash` |
| Payload hash | 32 bytes, identity | `PayloadHash` |
| Accumulation gas limit | Eight-byte little endian | `Gas` |
| Work output | C.2 operator O | Existing `WorkOutput` |
| Refinement gas used | Canonical natural | `Gas` |
| Imported segment count | Canonical natural | `ImportCount` |
| Extrinsic count | Canonical natural | `ExtrinsicCount` |
| Aggregate extrinsic size | Canonical natural | `ExtrinsicBytes` |
| Exported segment count | Canonical natural | `ExportCount` |

The fixed prefix is 76 bytes. Hashes have no length discriminator or byte
reversal. Accumulation gas is always fixed width; refinement gas and the other
four metrics are variable-width naturals. These counters use the complete
uint64 range supported by the pinned general-natural encoder. The codec does
not check state-dependent limits, code availability or hash validity.

Public functions are `encodeDigestBorrowed` and `decodeDigestBorrowed` /
`decode_digest_borrowed`, in `src/work_digest.nim`.
`RefineLoad` groups the five typed metrics. The full tuple is
`WorkDigest`.

## API and validation

See [the Nim codec guide](../docs/codec.md) and source modules under `src/`.
Independent references, official vectors, boundary/fuzz and failure-atomicity checks live under `tests/`.
