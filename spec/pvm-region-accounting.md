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
the review checkout's `build/pvm-region-quotient-audit`. The change does not explain the earlier Sieve/Pinky regression in the macro PR.

## Linux ARM qualification

Runtime head: `674a6b56a4b1443f1ee38a9eb2e1d9dded214fe2`, baseline unchanged.
[Focused ARM run](https://github.com/jacogr/ragnarok/actions/runs/41420132650) and
[Smoke](https://github.com/jacogr/ragnarok/actions/runs/41420081574) passed. Artifact
`13130541508` ZIP SHA-256:
`e842b6442bb407e70a7d762bfa4906a5aa901cfec242cfa764bf2229bc253db7`.

Independent audits verified 2,575 role-source hashes, 519 native-source hashes,
84 primary processes, 60 scheduled replays, 138 controls, all 12 native
qualification rows and seven unchanged macro receipts, 18 image equalities and
317 raw-log/embedded-output matches. Native work, code sizes and publication
counts match the baseline. No broad CI matrix or x86 run was requested.

All warm statistics use calls 3 through 12, with no exclusions. Changes below
use ratios of group medians of per-process warm CPU medians. The paired median
is a separate estimator. Ranges are the full ranges of process medians.

| Six native replay pairs | Group-median change | Median paired change | Faster / slower | Process ranges overlap |
| --- | ---: | ---: | ---: | --- |
| tick | +0.180371% | +0.208739% | 1 / 5 | yes |
| init | +0.271523% | +0.147320% | 3 / 3 | yes |
| sieve | -1.418889% | -0.826991% | 6 / 0 | yes |
| pinky | +0.024941% | +0.058736% | 3 / 3 | yes |
| minimal | +0.020554% | -0.133060% | 3 / 3 | yes |

Sieve is a modest consistent improvement: all six pairs are faster, with
overlapping process ranges. Its median paired change is about -0.83%; the
ratio of group medians is about -1.42%. DOOM tick, init, Pinky and Minimal are
effectively flat at this scope. The high Minimal baseline process remains
included: its ratio-of-means change is -1.473229%, while its group-median
change is +0.020554%. No outlier was removed.

The complete two-order primary comparison retains costs as well as gains:

| Primary workload | Policy | Group-median change | Faster / slower | Process ranges overlap |
| --- | --- | ---: | ---: | --- |
| init:0 | jit | -0.439275% | 2 / 0 | no |
| init:0 | interpreter | +0.693865% | 0 / 2 | no |
| memset:100000 | jit | +0.472312% | 0 / 2 | no |
| memset:100000 | interpreter | -0.278013% | 2 / 0 | yes |
| minimal:100000 | jit | +0.516316% | 1 / 1 | yes |
| minimal:100000 | interpreter | -1.660148% | 2 / 0 | no |
| pinky:1 | jit | -0.211679% | 2 / 0 | no |
| pinky:1 | interpreter | +0.302688% | 0 / 2 | no |
| sieve:100000 | jit | +0.397280% | 1 / 1 | yes |
| sieve:100000 | interpreter | +0.615683% | 0 / 2 | no |
| sieve:10000000 | jit | -1.334183% | 2 / 0 | no |
| sieve:10000000 | interpreter | +0.121983% | 1 / 1 | yes |
| tick:0 | jit | -0.079796% | 1 / 1 | yes |
| tick:0 | interpreter | -0.527236% | 1 / 1 | yes |

In particular, native memset is +0.472312% in both primary orders without range
overlap. Interpreter init is +0.693865%, Pinky +0.302688% and Sieve 100K
+0.615683%, each slower in both orders without range overlap. These small
primary costs are retained; the record does not claim all-workload improvement.

Matched raw public-call CPU ratios against **interpreted PolkaVM**, not its JIT:

| Workload | Ragnarök JIT / PolkaVM interpreted | Ragnarök interpreted / PolkaVM interpreted |
| --- | ---: | ---: |
| tick | 0.409667 | 0.678487 |
| init | 0.225298 | 0.506229 |
| sieve | 0.809836 | 0.963175 |
| pinky | 0.909645 | 0.991153 |
| minimal | 0.951810 | 0.984074 |

Cold and construction CPU are separate from reused-call medians. Entries below
are medians with full minima/maxima over the six processes, in milliseconds.
Compiler/publication CPU is a cumulative diagnostic already included in the
public calls; it is not wall time, is not necessarily all in the first call,
and must not be added again.

| Workload / role | Owner constructor | First public call | Cumulative compiler/publication |
| --- | ---: | ---: | ---: |
| tick / baseline | 8.666456 [8.590232, 8.955400] | 27.838028 [27.654440, 28.166368] | 2.458512 [2.363432, 2.571352] |
| tick / jit | 8.661296 [8.579688, 8.692544] | 27.754680 [27.507816, 27.952008] | 2.429224 [2.392704, 2.471456] |
| init / baseline | 8.635624 [8.560144, 8.733960] | 162.819096 [162.493088, 163.773432] | 7.823328 [7.705200, 7.933648] |
| init / jit | 8.595500 [8.525256, 8.944760] | 163.167680 [162.605488, 163.229944] | 7.854960 [7.696400, 7.892368] |
| sieve / baseline | 3.011960 [2.894032, 3.031696] | 279.789484 [278.097728, 281.686376] | 3.062296 [3.032944, 3.169832] |
| sieve / jit | 2.979676 [2.841704, 3.004592] | 276.082416 [275.809856, 279.578216] | 3.050352 [2.989352, 3.096440] |
| pinky / baseline | 0.742324 [0.700896, 0.751392] | 84.191136 [84.008672, 84.427352] | 1.898908 [1.862816, 1.913600] |
| pinky / jit | 0.739196 [0.723096, 0.752424] | 84.316724 [83.989888, 84.742664] | 1.901776 [1.876704, 1.936568] |
| minimal / baseline | 0.020308 [0.019184, 0.021344] | 5.483948 [5.433752, 5.802832] | 0.099080 [0.095016, 0.101784] |
| minimal / jit | 0.019436 [0.018984, 0.020848] | 5.465496 [5.428000, 5.524640] | 0.097600 [0.095936, 0.103856] |

Full local audit records: `build/pvm-region-quotient-ci/audit.json` and
`distributions.json`; raw evidence remains in the digest-verified CI artifact.
These are bounded application/microbenchmark measurements, not full blockchain
or block-throughput claims.
