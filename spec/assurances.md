# Assurances extrinsic codec

Normative source: GP v0.7.1 `1c979cb59bb800f92ffff083a2701004dfc6cd33`, Appendix C.1
(bit sequence, natural and fixed integer encoding), C.2 `encodeassurances`, and reporting/assurance
`xtassurances`. Exact source/vector/profile hashes are retained in `spec/pins.json`.
The official vector README defines tiny as 2 cores / 6 validators and full as 341 / 1023.

One extrinsic is a canonical natural record count followed by records in strictly increasing
validator-index order. Each record has an anchor hash (32 identity bytes), a fixed bitstring
(`ceil(cores/8)` bytes, least-significant bit first, no length prefix), validator index E2 and
signature (64 identity bytes). Strides are 99 bytes for tiny and 141 for full.
Unused high bits in the last serialized bitstring octet must be zero. Native bitset storage has
43 bytes; an encoder also rejects nonzero unused storage octets instead of silently discarding
caller data. Signatures are nominal byte encodings here, not cryptographic validity claims.

Configuration is explicit: 1..341 cores and 1..1023 validators. Named tiny/full test profiles use
the pinned parameters above; intermediate widths exercise byte boundaries and future compatible
parameterization within this implementation's resource envelope. Invalid configuration fails
before input access. No count may exceed the configured validator count.

Encode accepts a stable borrowed array of fully owned fixed-field records and caller byte output.
Decode copies fully owned values into caller typed storage. No record retains a source span,
pointer, heap allocation or reference cycle, so opaque retained owners are unnecessary here.
Both directions are allocation-free in production code and preserve the entire caller destination
on failure. Decoders consume exactly one prefix; standalone consumers require full consumption.

Failure precedence: configuration; canonical count; count ceiling; complete fixed-stride input
proof (decoder) / whole output extent (encoder); typed destination capacity (decoder); checked
host storage arithmetic; overlap; then every record's index range, strict ordering and padding.
No commit occurs until the final record validates. Decode protects the entire input, including
trailing bytes, against overlap with the written typed prefix; encode protects all source records.
Unused typed destination elements are unchanged on success. Zero records are valid.

Errors are failure-only tagged alternatives: uninitialized, invalidconfig, truncated,
noncanonical, limitexceeded, outputtoosmall, aliasedbuffers, lengthoverflow, invalidvalidator.
Count, consumed/written and data exist only on success. Default results are failures.

This codec does not enforce anchor equality to a block parent, signature validity, validator
membership/assignments or availability state transitions. Those require external chain context;
the official structural fixtures themselves have different anchors. The unresolved Ed25519
backend-policy gate remains separate. This round adds no crypto primitive or networking behavior.

Acceptance: exact official tiny/full JSON and binary vectors; independent source construction
and named-field decoding; zero/full count bounds; all bit positions and width transitions;
noncanonical count, ordering, duplicate, invalid index and padding attacks; every truncation of
representative records; late failure/unused-output sentinels; source lifetime independence;
encoder/decoder aliases manufactured explicitly in trusted tests; deterministic malformed fuzz;
and compiler rejection of nominal anchor/signature/index swaps. Official formatters are required.
