# Bounded byte strings and fixed-width unsigned sequences

## Specification and scope

Gray Paper **v0.8.0**, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix **C.1.2** (Sequence
Encoding) and **C.1.3** (Discriminator Encoding) define concatenated element
encodings prefixed by the natural count for variable-length terms.
[Exact source](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/serialization.tex).
Natural counts use C.1.1; scalar elements use C.1.7. All revisions remain those
in [pins.json](pins.json).

The [container codec](../src/codec/bounded.nim) owns the count prefix, width and
resource bounds for byte strings and homogeneous fixed-width sequences.

## API and validation

See [the Nim codec guide](../docs/codec.md) and source modules under `src/codec/`.
Independent references, official vectors, boundary/fuzz and failure-atomicity checks live under `tests/`.

### Nimony result safety

On the `nimony` branch, `WriteResult`, `BlobResult` and `SequenceResult` keep their tagged
representation, but both their discriminator and payload fields are private. Only this module
constructs successes; callers read the reason through `error`. The existing property spellings
`written`, `offset`, `length`, `consumed` and `count` call read-only accessors whose Nimony
`.requires` precondition is success. A caller cannot retag a failure, forge a successful result or
read raw storage through safe code. This is necessary because Nimony does not guard raw variant
field reads. Default construction remains `Uninitialized` with no readable success data.

Proven preconditions need no runtime guard; unknown calls retain the supported runtime contract
check. Checked release/LTO tests reject all six success-only properties on both default and failed
results, plus six private-state/forgery attempts. Existing wire encodings, borrowed lifetimes,
atomic output behavior and caller-owned storage are unchanged. Contract misuse is a programmer
error; malformed wire input still returns the typed error before any output write.

Nimony's arithmetic intentionally wraps. Count/size preflight still uses uint64 comparisons,
subtraction and division before host-int conversion or multiplication. Native cases at
`high(int)-1`, `high(int)`, `high(int)+1` and `high(uint64)` reject oversized byte/element claims
without allocating their advertised payloads or changing the output sentinel.
