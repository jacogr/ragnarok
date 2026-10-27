# Trace-selected combined register workers

2026-10-26, Apple M1 Max; checked pinned Nimony/ARC/Clang ThinLTO. Local only, no CI/PR/commit/merge/default change.

Retained locally for a consistent DOOM gameplay benefit: all six call pairs improve, median -2.60%; lifecycle -1.68% with all six improving. Small full lifecycles remain broadly flat. Minimal kernel +1.36% is an explicit tradeoff, not a gain; initialization/cold results are mixed and no startup benefit is claimed. Local ARM64 evidence only.

Accepted parent is batched-root-publication. Only adjacent genuine register pairs151/152,200/139,149/149 execute two shared semantic workers directly in one handler. A check before the second operation preserves a partial source-budget barrier. The second original node stays independently addressable; source sites, register alias ordering, gas, PC exits, memory, host and publication remain unchanged. Separate untimed DOOM trace selected these pairs; its clocks are excluded. New5184-case native/ASan witness covers aliases, decoder saturation, folded gaps, second-node entry, paid state and full uint64 gas/budgets. Linked code preserved in arm64-handlers-*.txt; static code is not CPU-counter evidence.

Across 6 gameplay pairs: call -2.60% (range -3.35% to -1.64%); lifecycle -1.68% (range -2.88% to -0.19%). Lower is faster; every qualified sample included.

## DOOM comparison

Each cell forward / reverse CPU ms. Reused medians calls4–13 of13 complete checked calls. Native cold init one call; reference cold first of13. Outer call includes guest + host/resume; reset and final publication separately measured. Reference constructors/reset unavailable, so ratios are call comparisons only. Frozen master controls are the existing qualified images, not a rebuild of current remote master.

| Scope | Accepted parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
|---|---|---|---|---|---|
| cold | 741.972 / 758.318 | 762.209 / 742.820 | 1359.652 / 1364.945 | 687.620 / 692.019 | 1.108x / 1.073x |
| reused_init | 794.125 / 746.409 | 754.250 / 741.880 | 1353.075 / 1355.408 | 684.846 / 682.764 | 1.101x / 1.087x |
| ticks | 30.172 / 30.209 | 29.449 / 29.447 | 87.805 / 87.016 | 35.768 / 35.382 | 0.823x / 0.832x |

## All gameplay pairs

Lifecycle is median(reset + call + final publication) per sample; constructors separate.

| Order | Parent call | Candidate call | Reference call | Parent lifecycle | Candidate lifecycle | Call change | Lifecycle change |
|---|---|---|---|---|---|---|---|
| 0 | 30.172 | 29.449 | 35.768 | 50.787 | 49.974 | -2.40% | -1.60% |
| 1 | 30.209 | 29.447 | 35.382 | 50.512 | 49.627 | -2.52% | -1.75% |
| 2 | 30.376 | 29.460 | 35.373 | 51.329 | 49.850 | -3.02% | -2.88% |
| 3 | 30.224 | 29.413 | 35.197 | 50.475 | 49.831 | -2.68% | -1.28% |
| 4 | 29.928 | 29.438 | 35.255 | 50.042 | 49.945 | -1.64% | -0.19% |
| 5 | 30.309 | 29.294 | 35.325 | 50.709 | 49.467 | -3.35% | -2.45% |

## Preparation and phases, CPU ms

Raw phases: index/reset/guest/host-observation/resume/final-publication/callbacks/attempts/nodes. Clock overhead means phases do not exactly partition outer call.

| Scope/role/order | Plan | Frame | Reset | Guest | Host/observation | Resume | Publication | Lifecycle |
|---|---|---|---|---|---|---|---|---|
| cold/baseline/0 | 38.944 | 30.370 | 26.866 | 641.584 | 57.124 | 34.498 | 0.008 | 768.846 |
| cold/resident/0 | 38.526 | 30.044 | 29.762 | 651.450 | 63.268 | 37.962 | 0.007 | 791.978 |
| cold/resident/1 | 39.266 | 28.463 | 26.320 | 640.401 | 57.838 | 35.632 | 0.007 | 769.147 |
| cold/baseline/1 | 39.709 | 31.411 | 28.206 | 653.844 | 58.777 | 36.473 | 0.006 | 786.530 |
| reused_init/baseline/0 | 38.717 | 29.767 | 21.689 | 691.481 | 57.325 | 35.473 | 0.007 | 815.666 |
| reused_init/resident/0 | 39.411 | 29.030 | 20.983 | 650.434 | 58.061 | 35.824 | 0.007 | 775.980 |
| reused_init/resident/1 | 40.645 | 35.326 | 20.552 | 640.784 | 56.758 | 35.228 | 0.007 | 762.361 |
| reused_init/baseline/1 | 38.769 | 29.546 | 21.218 | 645.740 | 56.509 | 35.107 | 0.007 | 767.419 |
| ticks/baseline/0 | 39.575 | 29.440 | 20.343 | 29.631 | 0.424 | 0.107 | 0.007 | 50.787 |
| ticks/resident/0 | 39.055 | 30.030 | 20.608 | 28.915 | 0.428 | 0.104 | 0.007 | 49.974 |
| ticks/resident/1 | 39.157 | 30.899 | 20.238 | 28.923 | 0.417 | 0.102 | 0.007 | 49.627 |
| ticks/baseline/1 | 39.266 | 29.634 | 20.280 | 29.648 | 0.425 | 0.103 | 0.007 | 50.512 |

## First use

Local total includes plan/frame construction, reset, first call and publication; excludes fixture I/O/decoding/validation. Reference equivalent unavailable.

| Role | Order | Cold lifecycle | Plan+frame | First-use total |
|---|---|---|---|---|
| baseline | 0 | 768.846 | 69.314 | 838.160 |
| resident | 0 | 791.978 | 68.570 | 860.548 |
| resident | 1 | 769.147 | 67.729 | 836.876 |
| baseline | 1 | 786.530 | 71.120 | 857.650 |

## Six-pair small workloads

| Guest | Kernel change | Lifecycle change | All kernel pairs (%) | All lifecycle pairs (%) |
|---|---|---|---|---|
| pinky | -0.19% | +0.42% | +0.14, -1.76, +2.87, -0.51, +0.57, -1.60 | +0.87, -0.47, -0.04, +0.87, -0.60, +0.97 |
| sieve | +0.14% | -0.29% | +2.84, +0.27, -0.59, +0.29, -0.32, +0.00 | -0.42, +1.78, -0.48, +0.49, -1.54, -0.16 |
| minimal | +1.36% | -0.15% | +1.90, +1.53, +1.19, -0.11, +0.75, +2.35 | +0.87, -0.92, +0.72, -0.69, +0.38, -2.59 |
| memset | -0.76% | -0.31% | -0.28, +0.60, -1.25, -1.25, -1.59, +0.05 | -0.21, +2.51, -0.42, -2.41, -1.58, +1.03 |

## Small comparison matrix

Each cell cold; reused ms, forward / reverse. Historical faithful control is measurement provenance; production prepared tier is frozen control.

| Guest | Production prepared | Historical faithful | Accepted parent | Candidate | PolkaVM interpreted | Candidate/reference reused |
|---|---|---|---|---|---|---|
| pinky | 124.966; 123.921 / 124.082; 122.493 | 99.289; 96.701 / 96.508; 96.109 | 102.380; 89.686 / 89.829; 89.728 | 89.598; 89.630 / 90.845; 89.667 | 96.166; 94.937 / 96.728; 94.392 | 0.944x / 0.950x |
| sieve | 8.030; 3.585 / 7.838; 3.607 | 3.565; 3.593 / 3.757; 3.452 | 3.542; 3.330 / 3.487; 3.518 | 3.499; 3.369 / 3.525; 3.335 | 6.269; 3.559 / 6.161; 3.523 | 0.946x / 0.946x |
| minimal | 7.598; 7.814 / 7.554; 7.439 | 6.551; 6.471 / 6.543; 6.397 | 5.398; 5.316 / 5.348; 5.252 | 5.510; 5.473 / 5.334; 5.261 | 6.068; 6.038 / 6.030; 6.065 | 0.906x / 0.868x |
| memset | 3.699; 3.510 / 3.836; 3.517 | 3.723; 3.698 / 3.776; 3.746 | 3.910; 3.777 / 3.800; 3.797 | 3.842; 3.790 / 3.798; 3.777 | 4.050; 3.857 / 3.973; 3.905 | 0.982x / 0.967x |

## Small constructors and lifecycle, CPU ms

| Guest | Role | Order | Plan | Frame | Cold lifecycle | Reset | Publication | Reused lifecycle |
|---|---|---|---|---|---|---|---|---|
| sieve | baseline | 0 | 11.067 | 1.515 | 3.636 | 0.054 | 0.018 | 3.484 |
| sieve | resident | 0 | 10.995 | 1.498 | 3.712 | 0.069 | 0.019 | 3.557 |
| sieve | resident | 1 | 11.291 | 1.568 | 3.654 | 0.071 | 0.021 | 3.621 |
| sieve | baseline | 1 | 11.953 | 1.865 | 4.079 | 0.061 | 0.021 | 3.533 |
| minimal | baseline | 0 | 0.035 | 0.041 | 5.557 | 0.003 | 0.009 | 5.430 |
| minimal | resident | 0 | 0.036 | 0.050 | 5.380 | 0.003 | 0.009 | 5.402 |
| minimal | resident | 1 | 0.035 | 0.040 | 5.432 | 0.004 | 0.009 | 5.410 |
| minimal | baseline | 1 | 0.032 | 0.042 | 5.291 | 0.003 | 0.004 | 5.347 |
| memset | baseline | 0 | 0.215 | 6.192 | 4.028 | 0.272 | 0.052 | 4.132 |
| memset | resident | 0 | 0.224 | 6.124 | 4.266 | 0.253 | 0.054 | 4.145 |
| memset | resident | 1 | 0.216 | 6.021 | 4.063 | 0.228 | 0.054 | 4.074 |
| memset | baseline | 1 | 0.216 | 6.108 | 4.046 | 0.238 | 0.052 | 4.085 |
| pinky | baseline | 0 | 2.469 | 0.807 | 90.852 | 0.036 | 0.089 | 90.107 |
| pinky | resident | 0 | 2.525 | 0.909 | 90.275 | 0.034 | 0.091 | 90.628 |
| pinky | resident | 1 | 2.452 | 0.986 | 93.381 | 0.029 | 0.084 | 93.751 |
| pinky | baseline | 1 | 2.558 | 0.920 | 93.371 | 0.033 | 0.089 | 90.600 |

## Qualification and measurement limits

All139 opcodes, full CPU/gas/paid-state/register/exit-PC/checked-memory/permissions/source snapshots, ARC1000, memory pairs, host reply/budget matrix, real prefix, immutable publication, sparse boundary, direct-entry and independent stepOnce source-attempt accounting pass checked native and AddressSanitizer runs. The batch-memory witness is reused only after proving its complete test import closure byte-identical to the accepted parent; batch-witness-reuse.json is explicit about reuse. Experiment-specific witnesses are in qualification.log and supporting native logs.21 negative controls reject. Each valid timed call performs full reference checks, including DOOM output events. Golden frame1320 admission remains passed.

254 timing processes:70 small matrix,72 kernel confirmation,76 lifecycle,36 DOOM.13 calls/process, first3 warmups and median last10, except explicit cold one-call cases. Both process orders and six main/gameplay matched pairs. Fresh private-cache images are byte-equal for all six role/driver pairs. Complete source/fixture/image hashes remain stable throughout timings. Qualification is sealed before guarded timings, not rebuilt during admission.

The2-second competing-load guard excludes our full process tree and aborts the whole cohort upon observed project compiler/executable/sustained Python/virtualization compute. No other process is stopped. Desktop/indexer/language-server activity remains background. No competing project compute observed during accepted cohort; discrete observations cannot rule out sub-sample contention. Statistical ARM64 same-machine CPU evidence, not hardware counters or simulated branch misses. Source attempts are not native instructions. Do not infer CPU causes from static instruction counts alone.

DOOM init203,298,231 source attempts/1,621callbacks/36,204retained nodes; gameplay12,180,040attempts/one callback/10,759nodes. Memory permissions, checked access, host protocols/publication, unsigned gas and observable exits retained. Cache remains monotone/unbounded with input-sized maps; a production admission/total-byte policy remains a gate. No engine-only RSS claim.

Pinned Nimony4724f66c2e01b17810c844f26575b2317995fda2; pinned PolkaVM interpreted69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa. Ten older accepted controls and tracked checkout unchanged.


Excluded in full before the accepted timing cohort: discarded-overlap-01/EXCLUDED.json. No completed results from these cohorts contribute above.



Proceed to the separately qualified specialized-entry-worker experiment from this accepted local implementation.

No commit needed.
