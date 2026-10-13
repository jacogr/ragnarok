# Fixed-width unsigned integer increment — 2026-10-13

Implemented independent, documented encoders and prefix decoders for every
width from zero through eight in Nim and Odin. The Gray Paper **v0.7.1 C.1.7**
definition and checked API behavior are documented in
[the specification notes](../spec/fixed-unsigned.md). All existing version pins
remain unchanged. No language packages or runtime dependencies were added.

## Executed verification

Host: Apple Silicon arm64, macOS 27.0.1, Apple clang 21.0.0.
Nim 2.2.12 with ARC; Odin dev-2026-10:84bc3fc21 and LLVM/LLD 22.1.8.
Formatting used odinfmt 2026-08 and nimpretty 0.2 with existing project settings.

Executed from the Ragnarok directory:

```sh
python3 tools/format.py
python3 tools/format.py --check
python3 interoperability/test_codec.py
```

The shared runner prints exact build/test commands and temporary output paths.
It runs `nim check --mm:arc` for both production modules, both native Nim test
programs with ARC, and `odin check odin/codec -no-entry-point -vet -strict-style`.
`odin test odin/tests` now runs the natural and fixed-width tests with memory
tracking enabled. The runner also builds both sets of native batch adapters,
verifies all pinned official fixture hashes, and requires all eight negative
compilation fixtures (two existing, six new) to fail for encoder type mismatch.

Observed final results:

```text
Formatting check passed (20 source files).
PASS fixed unsigned: 73278 shared requests per implementation; 24 official field checks; 47 boundary fixtures; 6 negative compilation checks
PASS: 45215 shared requests per implementation; 20 official prefix checks; 29 boundary fixtures; native tests and negative compilation checks
```

Coverage includes:

- Every one-byte and two-byte unsigned value in each native implementation.
- Widths 0..8, minima/maxima, internal power-of-two boundaries and byte order.
- Rejection of every first overflowing value for widths 0..7; uint64 max at
  width eight; rejection of decimal values above uint64 max in adapters.
- Every truncated prefix of the tested values, sampled complete byte patterns,
  required high zero bytes, exact consumption and preservation of trailing
  bytes, including width zero.
- Negative and oversized width counts, including host-int min/max; InvalidWidth
  takes precedence over Truncated when both conditions are present.
- 10,000 deterministic arbitrary-byte/width cases per native suite and 10,000
  additional shared random decoder requests, plus 1,000 random in-domain values
  per supported width with round-trip, trailing-byte and all truncation checks.
- 24 checks of official one-byte ticket indices and four-byte preimage service
  indices; complete surrounding fixture bytes/offsets were verified by the
  test-only extractor. No full composite conformance claim is made.
- Compile-time rejection of raw uint64 values, raw int widths and general-natural
  values where the fixed-width encoder requires its distinct domain types.

Both implementations agreed with each other and the independent little-endian
reference. All existing natural-number regression checks still passed.
No input-derived allocations or unsafe width conversions were introduced in
the production APIs. This is correctness validation, not a benchmark.

## Remaining work and handoff

Linux execution/CI, full composite official vectors, and sustained coverage-guided
fuzz campaigns remain unverified. Wider-than-uint64 and signed values are outside
this unsigned primitive's current API scope.

The fixed-width round is complete. **Wait for the maintainer's go-ahead before
implementing bounded byte strings/sequences.** That round should also report
completion and wait before a subsequent codec round.
