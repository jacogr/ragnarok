# Fixed-width unsigned integer codec

## Normative definition and scope

This increment implements Gray Paper **v0.8.0**, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix **C.1.7**, Fixed-length
Integer Encoding. [Pinned source](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/serialization.tex).
The revision and official vector snapshot remain those in [pins.json](pins.json).

The [fixed unsigned codec](../src/codec/fixed_unsigned.nim) owns the native width and
zero-width behavior. The paper defines larger widths mathematically.

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
