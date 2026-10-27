# First-touch containing-block pricing

2026-10-26, Apple M1 Max; checked pinned Nimony/ARC/Clang ThinLTO. Local only, no CI/PR/commit/merge/default change.

Retained locally as a cold-start/preparation improvement, not a steady-state speed win. Across all six predeclared first-use pairs, measured plan+frame+reset+cold-call+publication improves2.12–3.98%, median3.72%. Plan construction drops roughly39ms to8ms. Gameplay median call +0.71%, lifecycle +0.51%; reused initialization mixed, small lifecycles broadly flat. These warm differences and desktop measurement limits remain explicit. No observed competing samples in either completed timing group; observe-only policy was followed.

Exact parent is retained fused-register-sequences. The immutable plan records containing-block source addresses and captured cycle policy instead of pricing every block. flatResolve computes the same authoritative blockGas once for each newly emitted executable header and seals its existing charge/error handler. Existing code-cache links reuse that header. Interior suffix headers may each compute the same containing-block price once. No separate price map, mutable shared plan, changed gas/budget/exit ordering or new cache policy. Price input remains the genuine containing-block start, including paid reentry and refused prices. Frame, checked memory, host bridge, publication and fused semantics unchanged. Untimed full-state probe observes6209first-call price computations in init and1872in gameplay, then zero in each of twelve reused calls. Eager parent computes34317prices; unique visited containing blocks were6204/1871, explaining repeated price inputs for five/one suffix headers. Actual GasResult16bytes versus CodeAddress8bytes reduces logical plan price payload by274536bytes before the captured8-byte policy and allocator/capacity differences (net logical274528bytes); this is not an RSS claim.

Across 6 gameplay pairs: call +0.71% (range -0.30% to +1.49%); lifecycle +0.51% (range -0.32% to +2.41%). Lower is faster; every qualified sample included.

## DOOM comparison

Each cell forward / reverse CPU ms. Reused medians calls4–13 of13 complete checked calls. Native cold init one call; reference cold first of13. Outer call includes guest + host/resume; reset and final publication separately measured. Reference constructors/reset unavailable, so ratios are call comparisons only. Frozen master controls are the existing qualified images, not a rebuild of current remote master.

| Scope | Accepted parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
|---|---|---|---|---|---|
| cold | 742.870 / 746.609 | 760.809 / 750.461 | 1342.803 / 1352.788 | 710.551 / 675.999 | 1.071x / 1.110x |
| reused_init | 741.159 / 745.589 | 753.236 / 739.498 | 1357.614 / 1350.460 | 679.618 / 681.236 | 1.108x / 1.086x |
| ticks | 29.158 / 29.187 | 29.465 / 29.295 | 86.289 / 87.227 | 35.019 / 35.092 | 0.841x / 0.835x |

## All gameplay pairs

Lifecycle is median(reset + call + final publication) per sample; constructors separate.

| Order | Parent call | Candidate call | Reference call | Parent lifecycle | Candidate lifecycle | Call change | Lifecycle change |
|---|---|---|---|---|---|---|---|
| 0 | 29.158 | 29.465 | 35.019 | 49.286 | 49.609 | +1.05% | +0.66% |
| 1 | 29.187 | 29.295 | 35.092 | 49.239 | 49.284 | +0.37% | +0.09% |
| 2 | 29.110 | 29.543 | 35.404 | 49.271 | 50.460 | +1.49% | +2.41% |
| 3 | 29.395 | 29.306 | 35.044 | 49.869 | 49.710 | -0.30% | -0.32% |
| 4 | 29.368 | 29.370 | 35.281 | 49.467 | 49.651 | +0.01% | +0.37% |
| 5 | 29.110 | 29.529 | 35.118 | 49.597 | 49.962 | +1.44% | +0.74% |

## Preparation and phases, CPU ms

Raw phases: index/reset/guest/host-observation/resume/final-publication/callbacks/attempts/nodes. Clock overhead means phases do not exactly partition outer call.

| Scope/role/order | Plan | Frame | Reset | Guest | Host/observation | Resume | Publication | Lifecycle |
|---|---|---|---|---|---|---|---|---|
| cold/baseline/0 | 38.937 | 29.764 | 26.720 | 639.081 | 58.838 | 35.749 | 0.006 | 769.596 |
| cold/resident/0 | 7.556 | 28.088 | 24.073 | 659.153 | 57.238 | 35.390 | 0.008 | 784.890 |
| cold/resident/1 | 7.880 | 35.551 | 27.461 | 650.281 | 56.541 | 34.733 | 0.008 | 777.930 |
| cold/baseline/1 | 39.717 | 29.294 | 26.927 | 643.510 | 58.426 | 35.528 | 0.007 | 773.543 |
| reused_init/baseline/0 | 39.172 | 29.851 | 21.395 | 639.568 | 56.101 | 35.018 | 0.007 | 763.093 |
| reused_init/resident/0 | 8.143 | 32.931 | 21.867 | 646.511 | 57.889 | 35.733 | 0.007 | 774.964 |
| reused_init/resident/1 | 7.803 | 28.698 | 21.215 | 639.595 | 56.272 | 34.967 | 0.007 | 761.073 |
| reused_init/baseline/1 | 39.315 | 29.241 | 21.329 | 643.193 | 56.709 | 34.922 | 0.007 | 766.408 |
| ticks/baseline/0 | 38.887 | 26.464 | 20.095 | 28.608 | 0.418 | 0.106 | 0.007 | 49.286 |
| ticks/resident/0 | 7.338 | 27.236 | 20.194 | 28.915 | 0.416 | 0.107 | 0.007 | 49.609 |
| ticks/resident/1 | 8.304 | 30.997 | 19.956 | 28.768 | 0.408 | 0.106 | 0.007 | 49.284 |
| ticks/baseline/1 | 39.076 | 30.077 | 20.071 | 28.652 | 0.424 | 0.106 | 0.007 | 49.239 |

## First use

Local total includes plan/frame construction, reset, first call and publication; excludes fixture I/O/decoding/validation. Reference equivalent unavailable.

| Role | Order | Cold lifecycle | Plan+frame | First-use total |
|---|---|---|---|---|
| baseline | 0 | 769.596 | 68.701 | 838.297 |
| resident | 0 | 784.890 | 35.644 | 820.534 |
| resident | 1 | 777.930 | 43.431 | 821.361 |
| baseline | 1 | 773.543 | 69.011 | 842.554 |

## Six-pair small workloads

| Guest | Kernel change | Lifecycle change | All kernel pairs (%) | All lifecycle pairs (%) |
|---|---|---|---|---|
| pinky | +0.25% | -0.15% | +0.51, +0.17, -0.27, +0.84, +0.23, +0.27 | +0.20, +0.12, -0.29, -0.41, -0.23, -0.08 |
| sieve | +0.00% | +0.30% | +0.39, -2.42, +2.37, +0.69, -0.39, -0.70 | +0.31, -1.10, +0.72, +0.28, +0.64, -0.49 |
| minimal | +0.09% | -0.43% | +1.42, +0.69, +0.84, -2.02, -0.52, -2.22 | +0.19, -0.52, -0.41, +0.57, -0.83, -0.45 |
| memset | +0.57% | -0.01% | +1.48, +1.84, -1.66, +0.87, +0.24, +0.28 | +0.17, -0.20, +0.78, -0.90, +0.17, -0.82 |

## Small comparison matrix

Each cell cold; reused ms, forward / reverse. Historical faithful control is measurement provenance; production prepared tier is frozen control.

| Guest | Production prepared | Historical faithful | Accepted parent | Candidate | PolkaVM interpreted | Candidate/reference reused |
|---|---|---|---|---|---|---|
| pinky | 124.516; 122.783 / 125.242; 122.884 | 97.389; 96.896 / 95.684; 95.527 | 88.328; 88.603 / 88.853; 88.222 | 92.651; 88.749 / 91.229; 88.608 | 95.594; 93.886 / 95.936; 93.672 | 0.945x / 0.946x |
| sieve | 7.481; 3.476 / 7.610; 3.418 | 3.569; 3.403 / 3.742; 3.413 | 3.481; 3.287 / 3.540; 3.282 | 7.471; 3.371 / 7.065; 3.284 | 6.758; 3.645 / 6.410; 3.631 | 0.925x / 0.904x |
| minimal | 7.727; 7.687 / 7.887; 8.169 | 6.527; 6.494 / 6.693; 6.461 | 5.363; 5.416 / 5.425; 5.405 | 5.325; 5.406 / 5.370; 5.348 | 6.467; 6.421 / 6.400; 6.290 | 0.842x / 0.850x |
| memset | 3.900; 3.733 / 3.683; 3.501 | 4.912; 3.692 / 3.746; 3.654 | 3.858; 3.817 / 3.877; 3.753 | 3.860; 3.769 / 3.862; 3.755 | 4.098; 3.939 / 3.979; 3.923 | 0.957x / 0.957x |

## Small constructors and lifecycle, CPU ms

| Guest | Role | Order | Plan | Frame | Cold lifecycle | Reset | Publication | Reused lifecycle |
|---|---|---|---|---|---|---|---|---|
| sieve | baseline | 0 | 10.704 | 1.783 | 3.635 | 0.054 | 0.016 | 3.398 |
| sieve | resident | 0 | 1.558 | 1.430 | 7.099 | 0.062 | 0.013 | 3.419 |
| sieve | resident | 1 | 1.522 | 1.425 | 7.287 | 0.050 | 0.013 | 3.405 |
| sieve | baseline | 1 | 10.613 | 1.649 | 3.688 | 0.053 | 0.015 | 3.383 |
| minimal | baseline | 0 | 0.032 | 0.046 | 5.270 | 0.003 | 0.005 | 5.282 |
| minimal | resident | 0 | 0.011 | 0.038 | 5.345 | 0.003 | 0.004 | 5.324 |
| minimal | resident | 1 | 0.013 | 0.036 | 5.421 | 0.003 | 0.004 | 5.388 |
| minimal | baseline | 1 | 0.033 | 0.042 | 5.218 | 0.003 | 0.005 | 5.284 |
| memset | baseline | 0 | 0.220 | 7.935 | 4.518 | 0.237 | 0.053 | 4.085 |
| memset | resident | 0 | 0.048 | 6.105 | 4.320 | 0.229 | 0.054 | 4.069 |
| memset | resident | 1 | 0.058 | 6.017 | 4.105 | 0.205 | 0.044 | 3.965 |
| memset | baseline | 1 | 0.225 | 6.154 | 4.349 | 0.239 | 0.050 | 4.034 |
| pinky | baseline | 0 | 2.594 | 0.877 | 89.423 | 0.031 | 0.083 | 88.886 |
| pinky | resident | 0 | 0.520 | 0.857 | 91.370 | 0.036 | 0.089 | 89.825 |
| pinky | resident | 1 | 0.510 | 0.826 | 90.092 | 0.035 | 0.090 | 88.841 |
| pinky | baseline | 1 | 2.503 | 0.854 | 89.572 | 0.042 | 0.087 | 89.449 |

## Qualification and measurement limits

All139 opcodes, full CPU/gas/paid-state/register/exit-PC/checked-memory/permissions/source snapshots, ARC1000, memory pairs, host reply/budget matrix, real prefix, immutable publication, sparse boundary, direct-entry and independent stepOnce source-attempt accounting pass checked native and AddressSanitizer runs. The batch-memory witness is reused only after proving its complete test import closure byte-identical to the accepted parent; batch-witness-reuse.json is explicit about reuse. Experiment-specific witnesses are in qualification.log and supporting native logs.21 negative controls reject. Each valid timed call performs full reference checks, including DOOM output events. Golden frame1320 admission remains passed.

254 timing processes:70 small matrix,72 kernel confirmation,76 lifecycle,36 DOOM.13 calls/process, first3 warmups and median last10, except explicit cold one-call cases. Both process orders and six main/gameplay matched pairs. Fresh private-cache images are byte-equal for all six role/driver pairs. Complete source/fixture/image hashes remain stable throughout timings. Qualification is sealed before guarded timings, not rebuilt during admission.

The2-second monitor excludes our full process tree and records project compiler/executable/sustained Python/virtualization compute. Per the revised user instruction, the current cohort completes before load is assessed; no automatic exclusion or other-process stop. Earlier interrupted cohorts are preserved and excluded separately. Desktop/indexer/language-server activity remains background. No competing project compute observed during accepted cohort; discrete observations cannot rule out sub-sample contention. Statistical ARM64 same-machine CPU evidence, not hardware counters or simulated branch misses. Source attempts are not native instructions. Do not infer CPU causes from static instruction counts alone.

DOOM init203,298,231 source attempts/1,621callbacks/36,204retained nodes; gameplay12,180,040attempts/one callback/10,759nodes. Memory permissions, checked access, host protocols/publication, unsigned gas and observable exits retained. Cache remains monotone/unbounded with input-sized maps; a production admission/total-byte policy remains a gate. No engine-only RSS claim.

Pinned Nimony4724f66c2e01b17810c844f26575b2317995fda2; pinned PolkaVM interpreted69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa. Ten older accepted controls and tracked checkout unchanged.


Load observation: passed-no-observed-competing-task; 0 competing-process samples. Raw timings retained in full; observed overlap limits attribution.

Separate final statistical profile: 2411 stacks, thirteen fully checked init calls; all clocks discarded. Collapsed self occurrences (threshold>=5): flatCharge=554, flatBranch=374, runFlat=346, flatFusedRegisters=314, flatRegisterPair=179, changedMemoryPages=61, eQdestroyQ_SX4demory0macbfxz9n=47, newFlatFrame=46. This points to remaining charge/register/control/dispatch work but does not establish CPU causes. Raw linked ARM64 and generated sources retained.

All three authorized experiments complete. Final local implementation retains combined register workers plus first-touch pricing; specialized entry workers are restored/rejected. Stop for review; no fourth experiment or publication started.

No commit needed.

## Six fixed first-use pairs

Original two plus four additional pairs declared before the final verdict; all samples retained. Measured plan+frame+reset+cold call+final publication; fixture I/O/decoding/validation and final frame/plan destruction are outside this scope.262 timing processes total (254 main +8 additional cold). Additional load observation: passed-no-observed-competing-task.

| Order | Parent first-use ms | Candidate first-use ms | Change | Parent preparation ms | Candidate preparation ms |
|---|---|---|---|---|---|
| 0 | 838.297 | 820.534 | -2.12% | 68.701 | 35.644 |
| 1 | 842.554 | 821.361 | -2.52% | 69.011 | 43.431 |
| 2 | 842.252 | 811.334 | -3.67% | 66.827 | 39.086 |
| 3 | 848.579 | 814.818 | -3.98% | 70.683 | 35.437 |
| 4 | 842.589 | 810.265 | -3.84% | 70.746 | 37.803 |
| 5 | 839.302 | 807.669 | -3.77% | 69.134 | 35.302 |
