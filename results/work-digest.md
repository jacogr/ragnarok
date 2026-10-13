# Complete work-digest increment — 2026-10-13

Completed the full Gray Paper **v0.7.1 C.2 work-digest** tuple independently in
Nim and Odin, extending the previously verified work-output variant. Includes
nominal service/hash/gas/metric fields, owned fixed hashes, input-relative blob
spans, canonical suffix metrics and atomic caller-owned encoding. See
[API, wire format and storage notes](../spec/work-digest.md).

Production APIs allocate no heap memory. A nonmutating work-output size helper
enables complete tuple preflight before any writes. There are no new packages,
toolchains or specification/vector revisions. Existing official work-result
fixtures are now tested as entire tuples. Structures, functions and control-flow
blocks have explanatory comments.

## Executed verification

Apple Silicon arm64, macOS 27.0.1; Nim 2.2.12 with ARC;
Odin dev-2026-10:84bc3fc21, LLVM/LLD 22.1.8. Executed from Ragnarok:

```sh
python3 tools/format.py
python3 tools/format.py --check
python3 interoperability/test_codec.py
```

The runner prints exact commands and temporary build paths. It runs all five
Nim native test programs under ARC with relevant static checks, checks Odin's
codec package with `-vet -strict-style`, runs all five Odin tests with memory
tracking, builds ten batch adapters and checks all fixture hashes. It also
verifies 26 negative compilation fixtures: six new tests reject swapped hash
domains, raw accumulation gas and import/export counter confusion.

Observed results:

```text
Formatting check passed (56 source files).
PASS fixed unsigned: 73278 shared requests per implementation; 24 official field checks; 47 boundary fixtures; 6 negative compilation checks
PASS bounded: 26712 shared requests per implementation; 12 official blob checks; 13 project fixtures; 6 negative compilation checks
PASS composite: 25890 shared requests per implementation; 4 complete official preimage checks; 8 official work-output checks; 6 negative compilation checks
PASS work digest: 14278 shared requests per implementation; 8 complete official work-digest checks; 6 negative compilation checks
PASS: 45215 shared requests per implementation; 20 official prefix checks; 29 boundary fixtures; native tests and negative compilation checks
```

Both languages matched every independently decoded field and every independently
encoded byte. Four original tiny/full official success/panic fixtures are checked
in both directions (eight complete checks per implementation); tiny/full share
some fixture contents, so this count does not imply eight distinct samples.
All previous suites pass, including the work-output encoder affected by size
preflight factoring.

New coverage includes differing hash patterns, uint32-max service IDs, uint64-max
gas and every metric, natural-size transitions, all six work-error tags, real
blob lengths through 16,384 bytes, each truncation point of boundary tuples,
unknown/overlong tags, overlong naturals in all five metric positions, blob
policy failures, a destination missing its final suffix byte, invalid source
spans and whole borrowed-pool overlap. Native arbitrary-input entry points run
10,000 deterministic cases per language; the shared suite adds 5,000 arbitrary
buffers and mutations after valid fixed prefixes. Adapters check failed-write
sentinels and exact native reconstruction of successful consumed prefixes.

## Handoff

This completes work digests, without implementing surrounding work reports,
other extrinsics or full blocks. Linux execution/CI, optimized benchmarks and
sustained coverage-guided fuzzing remain unverified. Semantic work-report and
state-transition validation remain outside this serialization slice.

The round is complete. **Wait for the maintainer's next go-ahead before the next
codec increment.**
