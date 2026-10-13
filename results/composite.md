# Composite codec increment — 2026-10-13

Completed optional variable blobs, C.2 work-output variants, and full nested
preimage extrinsics independently in Nim and Odin. Uses unchanged Gray Paper
**v0.7.1 C.1.3/C.2** and the existing primitive codecs. See
[API, wire formats and ownership](../spec/composite.md).

Production codecs allocate no heap memory. Callers provide buffers, validated
span coordinates and explicit count/per-blob/aggregate policies. Complete
preflight precedes mutation; failed operations preserve destination storage.
Structures, functions and control-flow branches have explanatory comments.
Compiler, specification, vector and formatter revisions remain unchanged;
eight additional unmodified official fixture files have pinned hashes.

## Executed checks

Apple Silicon arm64, macOS 27.0.1; Nim 2.2.12 with ARC;
Odin dev-2026-10:84bc3fc21, LLVM/LLD 22.1.8. Existing native formatter settings.
Executed from Ragnarok:

```sh
python3 tools/format.py
python3 tools/format.py --check
python3 interoperability/test_codec.py
```

The shared runner prints exact commands, performs Nim static checks, runs all
four Nim test programs under ARC, and runs Odin package checking with
`-vet -strict-style` plus all four native tests with memory tracking. It builds
eight adapters, verifies all fixture hashes and checks 20 negative compilation
fixtures, including six new cases for nominal service IDs, typed work outputs
and preimage count policies.

Observed results:

```text
Formatting check passed (44 source files).
PASS fixed unsigned: 73278 shared requests per implementation; 24 official field checks; 47 boundary fixtures; 6 negative compilation checks
PASS bounded: 26712 shared requests per implementation; 12 official blob checks; 13 project fixtures; 6 negative compilation checks
PASS composite: 25890 shared requests per implementation; 4 complete official preimage checks; 8 official work-output checks; 6 negative compilation checks
PASS: 45215 shared requests per implementation; 20 official prefix checks; 29 boundary fixtures; native tests and negative compilation checks
```

Coverage includes empty/present optional blobs; all six exact work-error tags;
unknown and overlong tags; blob prefix transitions through 16,384 bytes;
0/1/127/128-record frames; all truncation cuts of nested record frames; random
service IDs and uint32 max; short byte/record destinations; late-record span,
canonicality and aggregate-budget failures; negative/overflowing source spans;
and typed output overlapping trailing input. Native arbitrary-byte entry points
run 10,000 reproducible cases per implementation. Shared hostile inputs include
all 256 headers and 5,000 arbitrary buffers, without claimed-size allocation.
Failed operations check destination sentinels, while successful decode results
re-encode exactly their consumed prefix.

The two original tiny/full preimage fixtures are each fully decoded and encoded
(four checks per implementation). Four original tiny/full work-result fixtures
check success/panic fields in both directions (eight field checks). Their entire
binary layout is independently verified to locate those fields; these checks do
not constitute a full work-digest codec. All previous regressions pass.

## Limits and handoff

This round covers three explicit schemas. Generic nested schemas, complete work
digests, other extrinsics and full blocks remain subsequent M1 work. Linux/CI,
performance benchmarks and sustained coverage-guided fuzzing remain unverified.
No additional client, crypto or networking scaffolding was introduced.

The round is complete. **Wait for the maintainer's next go-ahead before the next
codec increment.**
