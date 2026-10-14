# Codec result safety

Codec results now separate completed data from failure reasons. This is an API
change; the pinned Gray Paper wire formats, official fixtures, allocation-free
implementation and destination atomicity are unchanged.

## Nim

Natural and fixed-width results keep their existing `ok` variant discriminator.
Bounded, composite and digest results use an `error` discriminator: `None`
selects the success branch, while other statuses contain no payload/metadata.
`Uninitialized` is the default for those new variants. For example:

```nim
let outcome = decodeDigest(wire, ByteLimit(64))
if outcome.error == CompositeError.None:
  # The digest and consumed prefix exist only in this branch.
  useDigest(outcome.value, outcome.consumed)
else:
  # No decoded digest can be read from the failed variant.
  handleError(outcome.error)
```

Reading an inactive field raises `FieldDefect`, including with the pinned
compiler's ordinary release build. It is a caller misuse error; malformed wire
input returns a typed failure normally. A statically known failure cannot be
constructed with a payload. This does not mean Nim statically proves every
caller checked a dynamically returned result.

## Odin

Public and internal fallible codec operations use the allocation-free
`Codec_Result(T, E)` tagged union. Success has a named struct type such as
`Digest_Success`; failure contains only its typed error enum. The union has no
nil alternative and defaults to `Uninitialized`. A decoded work-error variant
is a valid `Work_Success`, distinct from failure to decode its frame.

```odin
switch outcome in codec.decode_digest(wire, codec.Byte_Limit(64)) {
case codec.Digest_Success:
    // This alternative carries the completed digest and consumed prefix.
    use_digest(outcome.value, outcome.consumed)
case codec.Composite_Error:
    // Failure has no value, span or consumed fields.
    handle_error(outcome)
}
```

Alternatively, check `codec.error_of(result) == .None` and then extract the
completed struct with `codec.success_of(result)`. `success_of` uses a checked
union assertion, which traps on caller misuse rather than returning default
data. The union itself has no `.value`, `.consumed`, `.written` or span fields;
direct access is a compilation error. An error-enum `None` placed in the failure
alternative is treated as `Uninitialized`, never as success.

The successful structs are `Decode_Success`, `Fixed_Encode_Success`,
`Fixed_Decode_Success`, `Write_Success`, `Blob_Success`, `Sequence_Success`,
`Composite_Write_Success`, `Optional_Success`, `Work_Success`,
`Preimage_Success`, and `Digest_Success`. Field names within them are unchanged.

## Failure and ownership contracts

Failure results have no count/consumption/written metadata. The caller's cursor
is therefore advanced only after selecting success. All destination buffers
remain unchanged on failed writes or caller-storage decodes. Legitimate zero
values, width-zero consumption, absent optionals and empty sequences are still
successes; tests explicitly distinguish them from failures.

Keep variant field/union assertion checks enabled in caller builds. Both APIs
still allow deliberate construction of success values and explicit unsafe casts;
these result types do not establish provenance or input ownership.

Blob spans still refer to caller-owned buffers by coordinates. This round does
not enforce original-buffer identity, lifetime or immutability. That remains the
next separate ownership round.

## Verification

`python3 interoperability/test_codec.py` runs native checks, official vectors,
cross-language conformance, two new compilation rejection checks, and Nim
inactive-field misuse checks in debug and release modes. The Odin native tests
switch directly on success and failure alternatives, including default results.
See [the result-safety report](../results/result-safety.md) for executed results.
