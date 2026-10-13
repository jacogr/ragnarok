# First codec increment — 2026-10-13

Scope: independent general-natural encoders/decoders in Nim and Odin.
Specification and official vector revisions: [codec baseline](../spec/codec.md).
No crypto/networking changes and no new third-party language dependencies.

## Validation

Host: Apple Silicon arm64, macOS 27.0.1, Apple clang 21.0.0.
Nim 2.2.12 with ARC; Odin dev-2026-10:84bc3fc21, Homebrew LLVM/LLD 22.1.8.

Executed:

```sh
nimpretty nim/src/natural.nim nim/tests/test_natural.nim nim/tests/driver.nim
python3 interoperability/test_codec.py
```

The Python runner prints the exact static-check, native-test and driver-build
commands, including temporary build paths and the active macOS SDK. Its relevant
checks include `nim check --mm:arc`, `nim c --mm:arc ... -r`,
`odin check odin/codec -no-entry-point -vet -strict-style`, and
`odin test odin/tests ...`. The negative compilation fixtures are required to
fail with a type mismatch involving the encoder argument.

Observed final result:

```text
PASS: 45215 shared requests per implementation; 20 official prefix checks; 29 boundary fixtures; native tests and negative compilation checks
```

- Each native suite round-tripped 0..65535, values below/at/above every power of
  two through bit 63, and uint64 max. It tested all proper truncations of these
  encodings, trailing-byte prefix handling, all 256 headers with zero payloads,
  and 10,000 deterministic arbitrary-byte cases.
- Shared checks included 10,002 large-value encode/decode/trailing-byte cases,
  every header with zero/max payload and every truncated prefix, values just
  below every length threshold encoded overlong, 10,000 random byte sequences,
  and decimal uint64 overflow/negative adapter inputs.
- Both distinct-type negative compilation fixtures were rejected as expected.
- Native outputs agreed byte-for-byte and matched the test-only mathematical
  oracle. All official fixture SHA-256 checks and 20 applicable prefix checks
  passed. These fixtures exercise single-octet prefixes; project boundary
  fixtures and shared cases cover longer forms.
- Odin's native test runner reported success with memory tracking enabled.
  The codec uses no heap allocation in either language.

An adapter test exposed that Odin's standard decimal parser did not reject
18446744073709551616 at this compiler revision. The test adapter now uses an
explicit pre-multiply overflow check. This does not affect the native decoder,
whose wire representation is bounded to 64 bits by construction.

## Limits and next work

This completes the first general-natural codec slice, not all of M0 or M1.
Linux builds/CI and a reproducible Linux compiler installation remain unverified.
Official composite vectors are pinned but only their applicable natural length
prefixes are tested here. No sustained coverage-guided fuzz campaign or benchmark
was run. Next: fixed-width integer APIs and bounded byte-string/sequence decoding,
then progressively complete the composite official codec vectors. Keep length
conversions checked and allocations bounded.
