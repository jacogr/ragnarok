# ARM native region accounting

This increment preserves the existing GP 0.8.0 charging, attempt and checked-return
contracts. It changes only the post-return multiplication guard for connected native
regions; admission, emitted native code and invocation ownership stay unchanged.

## Arithmetic contract

Each region has a nonzero `uint32` source span and an operation count no greater
than that span. For visits no greater than `high(uint32)`, their product fits
`uint64`: even `(2^32 - 1)^2` is below `2^64`. The existing aggregate check still
requires each product to fit the unaccounted consumed attempts, then requires the
final sum to equal all consumed attempts. This implies the original quotient bound.
Larger visit counts retain that quotient check before multiplication. Operation
products remain bounded by the corresponding attempt products. No assertion,
overflow refusal, guest gas or attempt boundary is disabled.

## Local evidence

Baseline: `cdf5f43ca5320c5448784b4f8a0fd4f39708ec81`. Pinned compiler binary SHA-256:
`bf61bfc2c5953de2d3236ddd99be61fce551809a57ce32ca6d34bbc6b1f8bd70`.
Both images use checked release ARC/Clang ThinLTO on macOS ARM64, identical
canonical source/driver/output paths and flags, with two fresh builds per role.
Each duplicate build produced an identical binary. Native lowering replaces the
common dynamic quotient with a high-word branch; large counts still use `UDIV`.

The private screen ran six alternating baseline/candidate process pairs per
workload, thirteen fully checked calls per process. An independent audit verified
513 runtime/native source files (one changed), eight images, 36 raw process logs
and all 468 CPU records. Using the standard warm window of calls 3 through 12:

| Workload | Median paired candidate/baseline CPU ratio | Interpretation |
| --- | ---: | --- |
| DOOM tick | 0.998209 | Effectively flat; no speedup claimed |
| Sieve 10M | 0.992542 | Small local signal; all six pairs faster |
| Pinky | 0.997448 | Effectively flat; no speedup claimed |

These are medians of paired ratios, not ratios of group medians. The original
local screen used calls 1 through 12 and found a similar roughly 0.8% Sieve signal.
Duplicate binary equality is a build control; no separate timed A/A control is
claimed. Local timings are not Linux qualification or full-block throughput.

Before timing, the candidate passed the existing native region/quota witnesses:
`ARM_REGION_CASES=3546`, `ARM_TWO_BLOCK_CONTROL_CASES=6486` and
`ARM_CONTROL_CASES=10560`, plus host, macro and source-state controls. All timed
processes compared full CPU, mapped memory and DOOM host events; native work and
publication counters matched each baseline/candidate pair. A private independent
integer oracle also checked 8,775 arithmetic boundary/refusal cases.

Evidence is retained under the speed checkout's `build/pvm-region-quotient` and
the review checkout's `build/pvm-region-quotient-audit`. Exact-head Linux ARM
qualification, matched interpreted-reference ratios and Smoke remain pending.
The change does not explain the earlier Sieve/Pinky regression in the macro PR.
