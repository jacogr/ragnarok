# Bounded container increment — 2026-10-13

Completed bounded variable byte strings and homogeneous fixed-width unsigned
sequences independently in Nim and Odin. Uses the unchanged Gray Paper
**v0.7.1 C.1.2/C.1.3** and existing natural/scalar primitives; see
[API and safety notes](../spec/bounded-containers.md).

Production APIs require explicit limits, use caller-owned storage or validated
input indices, and allocate no heap memory. Length proofs precede conversions,
indexing and multiplication. Failed operations preserve all destination bytes
or values. Aliasing is rejected, including output inside trailing input fields.
All structures, functions and control-flow blocks have explanatory comments.
No dependency or compiler/spec/vector/formatter revision changed.

## Executed checks

Apple Silicon arm64, macOS 27.0.1, Apple clang 21.0.0; Nim 2.2.12 with ARC;
Odin dev-2026-10:84bc3fc21, LLVM/LLD 22.1.8. Existing odinfmt/nimpretty settings.

Executed from Ragnarok:

```sh
python3 tools/format.py
python3 tools/format.py --check
python3 interoperability/test_codec.py
```

The runner prints exact build and check commands with temporary output paths.
It runs Nim static checks and all three native test programs under ARC, Odin's
`-vet -strict-style` package check, and all three Odin tests with memory tracking.
It builds all six native adapters, verifies the official fixture hashes, and
checks all 14 negative compilation fixtures (eight existing and six new).

Observed results:

```text
Formatting check passed (32 source files).
PASS fixed unsigned: 73278 shared requests per implementation; 24 official field checks; 47 boundary fixtures; 6 negative compilation checks
PASS bounded: 26712 shared requests per implementation; 12 official blob checks; 13 project fixtures; 6 negative compilation checks
PASS: 45215 shared requests per implementation; 20 official prefix checks; 29 boundary fixtures; native tests and negative compilation checks
```

Coverage includes:

- Byte lengths 0, 1, 127, 128, 255, 256, 16383 and 16384, exercising count
  prefix-size transitions; every incomplete prefix of these native cases.
- Empty and 1/127/128-element scalar sequences at all widths 0..8; every
  incomplete native/shared frame; fixed-width high zeros and uint64 max.
- Exact policy limits and limit-minus-one rejection, zero-capacity and short
  destinations, complete payloads with unrelated trailing bytes.
- Canonical hostile counts of 2^63 and uint64 max, overlong counts, all 256
  possible prefix headers at truncation cuts, and invalid signed widths.
- Width-zero sequences: count limits, missing typed output capacity, valid zero
  elements, and rejection of nonzero elements rather than silently dropping them.
- Late overflowing encoder values, overlapping buffers, and output aliasing
  only later input fields; every failed operation must leave output unchanged.
- 10,000 reproducible arbitrary-byte/width/limit cases per native suite; 5,000
  additional shared random input buffers plus structured valid/malformed cases.
- Six complete, unmodified official preimage blob spans across tiny/full
  variants, decoded and re-encoded exactly (12 official checks). Surrounding
  service indices, offsets and fixture hashes were verified too.
- Compile-time rejection of raw byte limits, wrong-domain element limits in
  byte APIs, and raw uint64 scalar-sequence values in both languages.

Both implementations matched each other and the independent test reference.
All previous natural-number and fixed-width regressions remain green. This
is correctness validation, not performance benchmarking or sustained
coverage-guided fuzzing.

## Limits and handoff

This is a bounded byte-string and fixed-unsigned-sequence slice, not a generic
codec for arbitrary nested element types or full composite official vectors.
Linux execution/CI and sustained coverage-guided fuzz campaigns remain open.
The test adapters have explicit utility-size caps; production limits are
caller-selected and schema-specific.

The round is complete. **Wait for the maintainer's next go-ahead before
implementing nested/composite codecs.**
