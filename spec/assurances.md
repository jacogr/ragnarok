# Assurances extrinsic codec

Target source: Gray Paper `fad0ded4a433052397bf7234352a57fe491883f7`, Appendix C.1/C.2
and `text/reporting_assurance.tex`. Source-pin adoption is the final stack layer; see
[qualification](graypaper-current-qualification.md). Historical vector hashes stay pinned.

One extrinsic is a canonical natural record count followed by records in strictly increasing
validator-index order. Each record contains a fixed bitstring (`ceil(cores/8)` bytes, LSB first,
without a length prefix), validator index E2 and64 signature bytes. There is no embedded parent.
Tiny and Full strides are67 and109 bytes. The verifier obtains the actual parent externally.
The final partial bitstring octet and all unused43-byte native bitset storage must be zero.

Configuration is explicit: 2..341 configured cores; validator counts are multiples of three
from 6 through three times the configured core count (GP 0.8.0 `valcount`). Named tiny/full test
profiles use the pinned parameters above; intermediate widths exercise byte boundaries and smaller
active sets under the configured chain ceiling. The bitfield always retains one bit per configured core; reducing the validator population does not shorten it. Invalid configuration fails
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

Cryptographic validity, active validator selection and availability transitions require external
chain context. The signature binds the actual parent even though that parent is absent on wire.
Pinned old JSON/bin pairs are verified byte-for-byte as historical evidence; current structural
corpora explicitly derive the new tuple from their named fields. No old-format decoder exists.

Acceptance covers independently authored current bytes, historical binary provenance, zero/full
counts, every bit and width transition, all truncations, noncanonical counts, duplicate/descending
indices, invalid validators, padding, atomic destinations, source lifetime, real alias probes and
malformed fuzz. A prefix codec may leave trailing input; standalone frame consumers must require
complete consumption, including when handed an old embedded-parent record.

## Compiler-port evidence

The numerical/compiler observations below record the original migration increment; see
[testing](../docs/testing.md) for current cumulative coverage and revision-specific CI results.

The pinned nightly uses private result discriminators/payloads with read-only `error`, guarded
`written`, and guarded `count`/`consumed` accessors. Default results remain Uninitialized. Explicit
record initialization retains zero bitset storage outside the configured wire width. All original
allocation-free validation, failure precedence and atomic destination guarantees are preserved.

`tools/test_runtime.py` checks all 20,706 independent encoding/decoding/overlap requests and 18,831
additional direct inspection requests. Inspection expectations use the independent decoder with
capacity 1,024 (above the largest valid 1,023-record profile), then select count/consumed or error;
there is no production record allocation. Thus late semantic errors are checked even when the
corresponding ordinary decode request intentionally supplies insufficient typed capacity.

`tests/unit/codec/test_assurances.nim` checks successful/default metadata, empty prefixes,
configuration
extremes, escaped-source ownership, independent record copies and zero extension. Ten runtime
misuse checks reject failed/default progress reads across encoding, decoding and inspection.
Twelve compilation checks reject private-state access/forgery and public-property mutation;
three existing nominal checks reject identity, index and configuration swaps. Full commands,
source/corpus hashes and diagnostics are recorded in ignored
`build/tests/runtime/results.json` and adjacent logs.

This verifies local macOS ARM64 checked ARC/Clang LTO codec behavior. Linux and contextual
signature verification remain separate migration work; see [the compiler
record](../docs/nimony-trial.md).
