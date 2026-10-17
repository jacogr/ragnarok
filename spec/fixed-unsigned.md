# Fixed-width unsigned integer codec

## Normative definition and scope

This increment implements Gray Paper **v0.8.0**, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix **C.1.7**, Fixed-length
Integer Encoding. [Pinned source](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/serialization.tex).
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

## API and validation

See [the Nim codec guide](../docs/codec.md) and source modules under `src/codec/`.
Independent references, official vectors, boundary/fuzz and failure-atomicity checks live under `tests/`.

### Nimony fixed-result safety

On the `nimony` branch, `FixedEncodeResult` and `FixedDecodeResult` keep their private Boolean
success/failure alternatives. Only the defining module constructs successes. Read-only `ok`
selects the outcome; `encoded`, `value` and `consumed` have success preconditions, and each
`error` accessor has a failure precondition. Callers cannot retag defaults or read raw payloads
through safe code. Encoded bytes are returned by value, with no borrowed backing storage.

Defaults still fail with `InvalidWidth`. Zero-width encode/decode of zero remains a complete
success with no bytes. Existing value-range, invalid-width, truncation and canonical byte behavior
is unchanged. The cumulative runtime verifier adds negative runtime and private-state compilation
checks
without substituting different protocol encodings or weakening the original boundary/fuzz suite.
