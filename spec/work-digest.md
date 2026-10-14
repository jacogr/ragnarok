# Complete work-digest codec

Normative basis: Gray Paper **v0.7.1**, commit
`1c979cb59bb800f92ffff083a2701004dfc6cd33`, Appendix **C.2**, equation
`encode(wd in workdigest)` in
[text/serialization.tex](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/serialization.tex),
and the `workdigest` tuple in
[text/reporting_assurance.tex](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/reporting_assurance.tex).
Gas is a uint64 domain; canonical general-natural encoding is defined over
uint64 by C.1.1. The existing compiler/spec/vector pins remain unchanged.

## Layout and types

| Field | Wire format | Nominal API type (Nim / Odin) |
| --- | --- | --- |
| Service ID | Four-byte little endian | `ServiceIndex` / `Service_Index` |
| Code hash | 32 bytes, identity | `CodeHash` / `Code_Hash` |
| Payload hash | 32 bytes, identity | `PayloadHash` / `Payload_Hash` |
| Accumulation gas limit | Eight-byte little endian | `Gas` |
| Work output | C.2 operator O | Existing `WorkOutput` / `Work_Output` |
| Refinement gas used | Canonical natural | `Gas` |
| Imported segment count | Canonical natural | `ImportCount` / `Import_Count` |
| Extrinsic count | Canonical natural | `ExtrinsicCount` / `Extrinsic_Count` |
| Aggregate extrinsic size | Canonical natural | `ExtrinsicBytes` / `Extrinsic_Bytes` |
| Exported segment count | Canonical natural | `ExportCount` / `Export_Count` |

The fixed prefix is 76 bytes. Hashes have no length discriminator or byte
reversal. Accumulation gas is always fixed width; refinement gas and the other
four metrics are variable-width naturals. These counters use the complete
uint64 range supported by the pinned general-natural encoder. The codec does
not check state-dependent limits, code availability or hash validity.

Public functions are `encodeDigestBorrowed` / `encode_digest_borrowed` and `decodeDigestBorrowed` /
`decode_digest_borrowed`, in `nim/src/work_digest.nim` and `odin/codec/work_digest.odin`.
`RefineLoad` / `Refine_Load` groups the five typed metrics. The full tuple is
`WorkDigest` / `Work_Digest`.

## Ownership and failure

Production functions allocate no heap memory. Nim declares `raises: []` and
uses ARC; all fixed fields are plain values with no reference cycles. Odin
uses no allocator. Encoders copy fixed fields into a local value snapshot and
accept a borrowed blob pool, caller-owned destination and explicit `ByteLimit`.
The work output and all metrics are measured before the first destination write;
checked sums reject an unrepresentable host extent. Failed encodes write no bytes and leave the entire destination unchanged, including a failure caused
by the final metric not fitting.

Success blobs protect the entire borrowed pool against any overlap with the
written tuple, including pool bytes outside the selected span. Payload-free
errors ignore unused pool data. The new nonmutating `measureWork` /
`measure_work` helper validates and measures the nested work variant against a
pool size and blob limit; it neither accesses bytes nor checks output aliasing.
The complete encoder then performs its own capacity and whole-frame alias checks.

Decoders return `DigestResult` / `Digest_Result`. Select the success alternative before using `value` or `consumed`; failure
alternatives contain neither field. Fixed hashes
are owned copies. Successful output spans refer to **the original full input**,
not to its work-output subframe. Keep that input alive and stable while using
the span. Every suffix metric must be complete and canonical before a result is
returned. No caller-owned typed destination is mutated by this decoder.

Decoding consumes exactly one full tuple prefix and leaves trailing data with
the caller. Require `consumed == input.length` when expecting a standalone frame.
Unknown work tags, noncanonical naturals, truncation and blob-policy violations
retain their existing typed errors. These APIs reuse `CompositeError` /
`Composite_Error` and `CompositeWrite` / `Composite_Write`.

## Trusted batch adapters

`nim/tests/digest_driver.nim` and `odin/digest_driver` accept:

```text
E <blob limit> <byte capacity> <service> <code hash hex> <payload hash hex> <accumulation gas> <work tag> <blob hex> <gas used> <imports> <extrinsic count> <extrinsic size> <exports>
D <blob limit> <wire hex>
```

A dash represents an empty blob/wire token. Hash tokens must contain exactly
32 bytes. Encode output is the complete wire hex. Decode output lists service,
two hashes, accumulation gas, work tag, blob, five metrics and consumed length.
Failures print lowercase error names without underscores; invalid trusted text
prints `inputerror`. Actual utility buffers are limited to 32 KiB; production
blob limits are caller-selected. Adapters assert whole-destination sentinels on
failure and exact re-encoding of every successful consumed prefix.

All four existing unmodified tiny/full `work_result_0` and `work_result_1`
JSON/binary fixture pairs are now verified **as complete work digests** in both
directions. Their hashes remain in `pins.json`. No fixture or protocol revision
was changed. See [the verification report](../results/work-digest.md).

The current [result API and migration examples](../docs/codec-results.md)
separate success data from failure reasons and preserve the borrowed-buffer
contract. This changes API access, not the normative wire formats above.

The allocation-free contract above applies to explicitly borrowed APIs. For
retained decoded data, use the [owned snapshot layer](../docs/codec-ownership.md),
which preserves these wire definitions and policies while adding private copies.
