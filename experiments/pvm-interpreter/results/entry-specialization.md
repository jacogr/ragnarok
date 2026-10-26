# Specialized block-entry register workers

2026-10-26, Apple M1 Max; checked pinned Nimony/ARC/Clang ThinLTO. Local only, no CI/PR/commit/merge/default change.

Rejected and restored the retained combined-handler parent. Median gameplay call -1.57%, lifecycle -0.72%, with two of six pairs flat/worse and mixed initialization. Minimal full lifecycle +1.42% across all six pairs; remaining small workloads broadly flat. This does not establish sufficient useful benefit beyond local timing variation to retain six extra entry variants. Raw complete timings retained; no observed competing-task samples in the completed cohort.

Only successful entry handoff specialized for first opcodes131/151/198/200. Pricing/reservation body copied unchanged; original error headers retain precedence; entry directly executes the existing register-pair or accepted combined worker. Fused pairs and separately addressable second nodes preserved. Generated linked image +368bytes, and scoped ARM64 listings confirm direct first-worker handoff. Earlier auto-interrupted cohorts are excluded and archived. The final cohort followed the revised observe-and-complete policy.

Across 6 gameplay pairs: call -1.57% (range -2.12% to +0.61%); lifecycle -0.72% (range -2.10% to +1.36%). Lower is faster; every qualified sample included.

## DOOM comparison

Each cell forward / reverse CPU ms. Reused medians calls4–13 of13 complete checked calls. Native cold init one call; reference cold first of13. Outer call includes guest + host/resume; reset and final publication separately measured. Reference constructors/reset unavailable, so ratios are call comparisons only. Frozen master controls are the existing qualified images, not a rebuild of current remote master.

| Scope | Accepted parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
|---|---|---|---|---|---|
| cold | 746.902 / 740.739 | 734.111 / 731.657 | 1351.587 / 1343.364 | 682.026 / 676.325 | 1.076x / 1.082x |
| reused_init | 738.894 / 740.533 | 732.835 / 748.722 | 1350.298 / 1351.010 | 678.582 / 676.888 | 1.080x / 1.106x |
| ticks | 29.394 / 29.142 | 28.871 / 28.738 | 86.541 / 88.536 | 36.090 / 34.945 | 0.800x / 0.822x |

## All gameplay pairs

Lifecycle is median(reset + call + final publication) per sample; constructors separate.

| Order | Parent call | Candidate call | Reference call | Parent lifecycle | Candidate lifecycle | Call change | Lifecycle change |
|---|---|---|---|---|---|---|---|
| 0 | 29.394 | 28.871 | 36.090 | 49.966 | 48.918 | -1.78% | -2.10% |
| 1 | 29.142 | 28.738 | 34.945 | 49.381 | 49.019 | -1.38% | -0.73% |
| 2 | 29.130 | 28.620 | 34.984 | 48.975 | 48.623 | -1.75% | -0.72% |
| 3 | 29.151 | 28.532 | 34.997 | 49.480 | 48.475 | -2.12% | -2.03% |
| 4 | 29.117 | 29.130 | 35.495 | 49.328 | 49.380 | +0.04% | +0.11% |
| 5 | 29.188 | 29.365 | 35.586 | 49.346 | 50.016 | +0.61% | +1.36% |

## Preparation and phases, CPU ms

Raw phases: index/reset/guest/host-observation/resume/final-publication/callbacks/attempts/nodes. Clock overhead means phases do not exactly partition outer call.

| Scope/role/order | Plan | Frame | Reset | Guest | Host/observation | Resume | Publication | Lifecycle |
|---|---|---|---|---|---|---|---|---|
| cold/baseline/0 | 40.393 | 30.775 | 28.967 | 643.010 | 59.378 | 35.552 | 0.007 | 775.876 |
| cold/resident/0 | 39.738 | 31.797 | 26.677 | 634.267 | 56.687 | 34.423 | 0.006 | 760.794 |
| cold/resident/1 | 38.671 | 28.295 | 26.773 | 630.209 | 57.769 | 34.833 | 0.008 | 758.438 |
| cold/baseline/1 | 38.806 | 29.471 | 25.907 | 638.023 | 57.829 | 35.864 | 0.007 | 766.653 |
| reused_init/baseline/0 | 38.893 | 29.517 | 20.651 | 638.079 | 56.108 | 34.718 | 0.007 | 759.505 |
| reused_init/resident/0 | 39.060 | 30.594 | 21.073 | 632.837 | 56.304 | 34.868 | 0.007 | 754.835 |
| reused_init/resident/1 | 39.164 | 31.300 | 21.463 | 644.763 | 58.698 | 36.087 | 0.007 | 769.936 |
| reused_init/baseline/1 | 39.524 | 31.161 | 20.640 | 641.192 | 56.011 | 34.913 | 0.007 | 761.682 |
| ticks/baseline/0 | 38.981 | 28.055 | 20.596 | 28.834 | 0.414 | 0.105 | 0.007 | 49.966 |
| ticks/resident/0 | 39.415 | 30.484 | 20.084 | 28.265 | 0.425 | 0.105 | 0.007 | 48.918 |
| ticks/resident/1 | 38.802 | 28.502 | 20.104 | 28.213 | 0.426 | 0.105 | 0.007 | 49.019 |
| ticks/baseline/1 | 40.322 | 31.171 | 20.144 | 28.613 | 0.407 | 0.103 | 0.007 | 49.381 |

## First use

Local total includes plan/frame construction, reset, first call and publication; excludes fixture I/O/decoding/validation. Reference equivalent unavailable.

| Role | Order | Cold lifecycle | Plan+frame | First-use total |
|---|---|---|---|---|
| baseline | 0 | 775.876 | 71.168 | 847.044 |
| resident | 0 | 760.794 | 71.535 | 832.329 |
| resident | 1 | 758.438 | 66.966 | 825.404 |
| baseline | 1 | 766.653 | 68.277 | 834.930 |

## Six-pair small workloads

| Guest | Kernel change | Lifecycle change | All kernel pairs (%) | All lifecycle pairs (%) |
|---|---|---|---|---|
| pinky | +0.46% | +0.31% | +0.10, +0.11, +0.60, +0.88, +0.51, +0.42 | -0.10, +0.55, +0.04, +0.15, +0.48, +0.67 |
| sieve | -0.29% | -0.56% | -1.47, -0.91, +0.91, -0.02, +0.06, -0.56 | -0.54, -0.58, +1.90, -0.68, -0.32, -1.17 |
| minimal | -0.60% | +1.42% | -0.60, +3.12, -0.61, -0.74, +1.16, -1.52 | +1.20, +1.46, +1.69, +1.17, +1.38, +1.91 |
| memset | -0.19% | -0.92% | -0.22, +0.05, -0.28, +0.89, -0.16, -0.66 | -0.94, -1.81, -0.34, +2.41, -0.90, -1.03 |

## Small comparison matrix

Each cell cold; reused ms, forward / reverse. Historical faithful control is measurement provenance; production prepared tier is frozen control.

| Guest | Production prepared | Historical faithful | Accepted parent | Candidate | PolkaVM interpreted | Candidate/reference reused |
|---|---|---|---|---|---|---|
| pinky | 124.741; 122.904 / 126.235; 122.986 | 97.511; 96.135 / 96.489; 96.040 | 90.721; 88.918 / 90.621; 88.937 | 89.027; 88.691 / 88.967; 89.552 | 94.974; 97.026 / 95.043; 93.722 | 0.914x / 0.956x |
| sieve | 7.689; 3.562 / 7.714; 3.536 | 3.676; 3.462 / 3.556; 3.436 | 3.536; 3.402 / 3.548; 3.308 | 3.594; 3.319 / 3.493; 3.316 | 6.283; 3.513 / 6.093; 3.525 | 0.945x / 0.941x |
| minimal | 7.530; 7.413 / 7.385; 7.439 | 6.289; 6.324 / 6.447; 6.347 | 5.227; 5.245 / 5.407; 5.290 | 5.243; 5.239 / 5.290; 5.224 | 6.061; 6.027 / 6.110; 6.022 | 0.869x / 0.867x |
| memset | 3.581; 3.490 / 3.663; 3.529 | 3.664; 3.731 / 3.645; 3.693 | 3.839; 3.806 / 3.803; 3.747 | 4.592; 3.782 / 3.731; 3.774 | 3.940; 3.837 / 3.989; 3.933 | 0.986x / 0.960x |

## Small constructors and lifecycle, CPU ms

| Guest | Role | Order | Plan | Frame | Cold lifecycle | Reset | Publication | Reused lifecycle |
|---|---|---|---|---|---|---|---|---|
| sieve | baseline | 0 | 10.650 | 1.412 | 3.501 | 0.067 | 0.013 | 3.385 |
| sieve | resident | 0 | 10.553 | 1.391 | 3.520 | 0.059 | 0.011 | 3.346 |
| sieve | resident | 1 | 11.375 | 1.452 | 3.542 | 0.054 | 0.015 | 3.383 |
| sieve | baseline | 1 | 10.507 | 1.414 | 3.641 | 0.064 | 0.010 | 3.339 |
| minimal | baseline | 0 | 0.034 | 0.041 | 5.336 | 0.003 | 0.005 | 5.298 |
| minimal | resident | 0 | 0.035 | 0.044 | 5.415 | 0.003 | 0.006 | 5.425 |
| minimal | resident | 1 | 0.032 | 0.037 | 5.382 | 0.004 | 0.004 | 5.330 |
| minimal | baseline | 1 | 0.033 | 0.037 | 5.309 | 0.002 | 0.004 | 5.244 |
| memset | baseline | 0 | 0.212 | 5.851 | 4.005 | 0.240 | 0.051 | 4.013 |
| memset | resident | 0 | 0.213 | 5.949 | 4.050 | 0.228 | 0.051 | 4.027 |
| memset | resident | 1 | 0.213 | 5.900 | 4.054 | 0.217 | 0.050 | 3.991 |
| memset | baseline | 1 | 0.213 | 5.939 | 4.014 | 0.234 | 0.053 | 4.014 |
| pinky | baseline | 0 | 2.414 | 0.828 | 88.616 | 0.032 | 0.078 | 89.139 |
| pinky | resident | 0 | 2.443 | 0.807 | 89.833 | 0.030 | 0.081 | 89.087 |
| pinky | resident | 1 | 2.456 | 0.917 | 90.241 | 0.037 | 0.080 | 88.915 |
| pinky | baseline | 1 | 2.544 | 0.815 | 89.619 | 0.038 | 0.085 | 89.558 |

## Qualification and measurement limits

All139 opcodes, full CPU/gas/paid-state/register/exit-PC/checked-memory/permissions/source snapshots, ARC1000, memory pairs, host reply/budget matrix, real prefix, immutable publication, sparse boundary, direct-entry and independent stepOnce source-attempt accounting pass checked native and AddressSanitizer runs. The batch-memory witness is reused only after proving its complete test import closure byte-identical to the accepted parent; batch-witness-reuse.json is explicit about reuse. Experiment-specific witnesses are in qualification.log and supporting native logs.21 negative controls reject. Each valid timed call performs full reference checks, including DOOM output events. Golden frame1320 admission remains passed.

254 timing processes:70 small matrix,72 kernel confirmation,76 lifecycle,36 DOOM.13 calls/process, first3 warmups and median last10, except explicit cold one-call cases. Both process orders and six main/gameplay matched pairs. Fresh private-cache images are byte-equal for all six role/driver pairs. Complete source/fixture/image hashes remain stable throughout timings. Qualification is sealed before guarded timings, not rebuilt during admission.

The2-second monitor excludes our full process tree and records project compiler/executable/sustained Python/virtualization compute. Per the revised user instruction, the current cohort completes before load is assessed; no automatic exclusion or other-process stop. Earlier interrupted cohorts are preserved and excluded separately. Desktop/indexer/language-server activity remains background. No competing project compute observed during accepted cohort; discrete observations cannot rule out sub-sample contention. Statistical ARM64 same-machine CPU evidence, not hardware counters or simulated branch misses. Source attempts are not native instructions. Do not infer CPU causes from static instruction counts alone.

DOOM init203,298,231 source attempts/1,621callbacks/36,204retained nodes; gameplay12,180,040attempts/one callback/10,759nodes. Memory permissions, checked access, host protocols/publication, unsigned gas and observable exits retained. Cache remains monotone/unbounded with input-sized maps; a production admission/total-byte policy remains a gate. No engine-only RSS claim.

Pinned Nimony4724f66c2e01b17810c844f26575b2317995fda2; pinned PolkaVM interpreted69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa. Ten older accepted controls and tracked checkout unchanged.


Excluded in full before the accepted timing cohort: discarded-overlap-01/EXCLUDED.json, discarded-overlap-02/EXCLUDED.json. No completed results from these cohorts contribute above.


Load observation: passed-no-observed-competing-task; 0 competing-process samples. Raw timings retained in full; observed overlap limits attribution.



Proceed with lazy containing-block pricing from the retained combined-handler parent. No entry specialization remains active.

No commit needed.
