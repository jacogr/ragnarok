# Bounded byte strings and fixed-width unsigned sequences

## Specification and scope

Gray Paper **v0.8.0**, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix **C.1.2** (Sequence
Encoding) and **C.1.3** (Discriminator Encoding) define concatenated element
encodings prefixed by the natural count for variable-length terms.
[Exact source](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/serialization.tex).
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

## API and validation

See [the Nim codec guide](../docs/codec.md) and source modules under `src/`.
Independent references, official vectors, boundary/fuzz and failure-atomicity checks live under `tests/`.
