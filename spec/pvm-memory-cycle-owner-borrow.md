# Borrow the active memory-cycle executable owner

**Performance tradeoff hold: keep draft.** Linux confirms a small native DOOM tick improvement, alongside a larger forced-interpreter tick cost and consistent Sieve regression. The ownership cleanup is correct, but the complete workload tradeoff is not accepted for readiness as-is. No extra CI is requested.

Baseline master: `d74ce4dd118eb260f07afef06f1b319f49c33c95`. Runtime handler SHA-256: `b7055951b001ae7cd867336ec4f56584e1852b73bb52c54f987ec707cce5e32f`. Backend remains `3532ea5cbc8bbd023ee898efe94fcef66e028f0584e49c3ae3bc6b79c6d15403`. Pinned checked ARC/Clang ThinLTO uses Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` and GP0.8 `3861aed15d7d016a3a416e14e61fc67dddf6daec`.

## Ownership and execution

The memory-cycle adapter copied `f.armJit` into a local owning reference for every entry and held it through mutable checked fallback. The exclusive frame already owns that cache for the native call. A bounded cursor scope now reads the same scalar headers, validates the same price/span/entry coordinates and calls the same native driver against disjoint register, region, dirty-page and local-context storage.

The cursor ends before any nil error, checked fallback or mutable post-call frame update. Scalar headers, admission flags and the 14-word invocation state carry the result across that scope. Native guard/refusal, gas, remaining attempts, paid-state clearing, unstarted-header progress and all original fallback choices retain their existing behavior. The context is stack storage; its initialization does not allocate or execute guest work. No ownership bypass or compiler assumption is used.

Actual matched DOOM ARM images shrink the wrapper from **209 to 163 instructions**, with stack **192 to 176 bytes**. The owning increment/decrement and destructor/unmap/free paths disappear. The retained witness images show 216 to 163 instructions with the same stack reduction. Checked-tail/control calls remain calls in those images; this is not a tail-call claim. Native code images, arena ownership/publication/caps, source accounting and the frame layout remain unchanged.

## Exact-source qualification

All 511 public runtime source files match the frozen candidate. Its inventory differs from master only in this wrapper. Both baseline and candidate passed all 11 retained ARM native/refusal/ownership checks and the plain witness; the candidate also passed native/refused policy, prepared blocks, gas plan, gas memo and pricing-owner checks. The existing witness includes 7,236 memory-cycle and 12,328 resident-memory-cycle frame cases, independent literal/register controls, source/gas/attempt/refusal exits and owner/host-memory lifecycle coverage.

The unmodified d74 witness is `d8f7badfadfec7fa34d2f9e85fc5560a88a79d6a708eadaedf3e2aeb9b6d95be`; qualification uses its unmodified controller `497b97ac002d2c792f6ff68e4548df6b6f7ed1d709c92d40d863f6324eeb1ad0`. Pinned formatting is byte unchanged. This change introduces no new witness protocol or receipt requirement.

Eight fresh same-canonical-path application images use identical build commands per driver family and have four byte-equal duplicate pairs. Initial unclocked controls passed 12 complete-state positives and 32 intended assertion/state/event refusals; the broader micro controls passed 20 positives and 40 intended refusals. Reference executables and complete inputs/expected-state/ROM identities were verified unchanged. Native six work/code metrics equal master for every case/order, and forced-interpreter native metrics are zero.

## Separate local ARM screens

Every process validates 13 complete public calls. CPU medians use calls 3–12 without sample/process exclusion. Each source/policy has four balanced process orders, duplicate image 0 for orders 0/1 and duplicate 1 for 2/3; matched PolkaVM interpreted references run in orders 0/3. These are bounded public-call measurements, not full blockchain throughput.

The first 36-process screen recorded tick **-1.048068%**, all four pairs faster with non-overlapping process ranges; paired ratios are 0.954590 / 0.990660 / 0.988947 / 0.989068. The high baseline first process is retained. Init was **+1.182198%**, three slower pairs and one faster with overlapping ranges: 1.037366 / 1.027107 / 1.004277 / 0.956666, retaining high candidate orders 0/1 and high baseline order 3. Interpreter tick was -1.625815% with three faster pairs/overlap; init +0.249691% with three slower pairs/overlap. Matched raw tick ratios: 0.311161 JIT / 0.502542 interpreted; init 0.166500 / 0.350689.

The separate broader 108-process gate reused these exact images and pinned inputs. The table reports **ratio of source-group process CPU medians**, not median of paired ratios; all pairs are also shown.

| Case / policy | CPU median change | Faster pairs | Process ranges | Candidate / baseline ratios, orders 0–3 |
| --- | ---: | ---: | --- | --- |
| tick / JIT | -1.108996% | 4/4 | non-overlapping | 0.989020 / 0.986957 / 0.996193 / 0.988763 |
| tick / interpreted | +1.328593% | 1/4 | overlapping | 1.049954 / 0.980141 / 1.011280 / 1.001294 |
| init / JIT | -0.594379% | 3/4 | overlapping | 0.988696 / 0.999425 / 1.001520 / 0.988240 |
| init / interpreted | +0.075112% | 2/4 | overlapping | 1.003395 / 0.995409 / 0.998302 / 1.008555 |
| minimal / JIT | +1.141864% | 1/4 | overlapping | 0.990129 / 1.009263 / 1.015373 / 1.015288 |
| minimal / interpreted | +1.554633% | 0/4 | overlapping | 1.029945 / 1.029535 / 1.007796 / 1.000443 |
| pinky / JIT | +0.054732% | 2/4 | overlapping | 1.007400 / 0.999975 / 1.001119 / 0.999488 |
| pinky / interpreted | -0.177067% | 3/4 | overlapping | 0.998858 / 0.991479 / 0.997100 / 1.002346 |
| memset / JIT | -0.905615% | 4/4 | overlapping | 0.992521 / 0.987508 / 0.991765 / 0.997387 |
| memset / interpreted | -0.087862% | 3/4 | overlapping | 0.997974 / 1.047565 / 0.998379 / 0.997835 |
| sieve / JIT | +0.181936% | 1/4 | overlapping | 1.002300 / 1.003425 / 0.997829 / 1.001373 |
| sieve / interpreted | -0.093361% | 3/4 | overlapping | 0.998944 / 0.997287 / 0.997811 / 1.003013 |

DOOM tick remains lower in every pair with non-overlapping ranges. Broader init has high baseline processes and overlap, so its negative median is not a settled improvement. Minimal has a slower JIT median and three slower pairs; interpreted Minimal is slower in all four. Sieve leans slightly slower; Pinky is near parity. Interpreter tick moves in the opposite direction to native tick. These costs and control drifts prevent a general throughput claim.

Matched raw broader ours/PolkaVM-interpreted ratios: tick **0.308759 JIT / 0.514647 interpreted**, init **0.163746 / 0.350199**. All six non-time native metrics remain exact master, including code bytes and publication fragment counts.

## Cold costs in the broader gate

Each entry is minimum / median / maximum across four processes, in process CPU milliseconds. Native preparation/publication is accumulated CPU already included in the corresponding calls, not wall elapsed time or an extra charge.

| Case / source / policy | Constructor CPU ms | First call CPU ms | Native preparation CPU ms |
| --- | --- | --- | --- |
| tick / baseline | 7.0430 / 7.0750 / 7.1360 | 20.2310 / 20.2590 / 20.3490 | 1.8890 / 1.9090 / 1.9210 |
| tick / candidate | 7.0670 / 7.1085 / 7.2060 | 20.2030 / 20.3305 / 20.5080 | 1.8950 / 1.9340 / 1.9770 |
| tick / baseline_interpreted | 7.0580 / 7.0685 / 7.1360 | 25.8400 / 25.8785 / 26.0310 | 0.0000 / 0.0000 / 0.0000 |
| tick / candidate_interpreted | 7.0490 / 7.1170 / 7.1430 | 25.9060 / 25.9245 / 26.0620 | 0.0000 / 0.0000 / 0.0000 |
| init / baseline | 7.0570 / 7.1215 / 7.2080 | 128.5680 / 129.5915 / 130.6570 | 5.9640 / 6.0655 / 6.1570 |
| init / candidate | 7.1080 / 7.1990 / 7.2080 | 128.4210 / 128.7560 / 128.9990 | 5.9140 / 5.9595 / 6.0270 |
| init / baseline_interpreted | 7.0430 / 7.0590 / 7.2120 | 242.4280 / 242.5990 / 243.1660 | 0.0000 / 0.0000 / 0.0000 |
| init / candidate_interpreted | 7.0440 / 7.1090 / 7.2450 | 241.8690 / 242.5435 / 243.4890 | 0.0000 / 0.0000 / 0.0000 |
| minimal / baseline | 0.0130 / 0.0325 / 0.0560 | 3.9770 / 4.1700 / 6.6130 | 0.0580 / 0.0685 / 0.1380 |
| minimal / candidate | 0.0110 / 0.0350 / 0.0600 | 3.9810 / 4.2610 / 6.1180 | 0.0430 / 0.0710 / 0.1310 |
| minimal / baseline_interpreted | 0.0140 / 0.0145 / 0.0160 | 4.3590 / 4.3905 / 4.5340 | 0.0000 / 0.0000 / 0.0000 |
| minimal / candidate_interpreted | 0.0120 / 0.0165 / 0.0220 | 4.4930 / 4.5555 / 4.7100 | 0.0000 / 0.0000 / 0.0000 |
| pinky / baseline | 0.4580 / 0.4855 / 0.5550 | 64.0710 / 64.2670 / 64.5120 | 1.7130 / 1.7630 / 1.8160 |
| pinky / candidate | 0.4550 / 0.4675 / 0.5020 | 64.1450 / 64.4020 / 64.9380 | 1.7050 / 1.7280 / 1.7520 |
| pinky / baseline_interpreted | 0.4530 / 0.4840 / 0.5020 | 80.8890 / 81.2675 / 81.7540 | 0.0000 / 0.0000 / 0.0000 |
| pinky / candidate_interpreted | 0.4420 / 0.4510 / 0.4950 | 80.9660 / 81.0925 / 81.3410 | 0.0000 / 0.0000 / 0.0000 |
| memset / baseline | 0.0480 / 0.0525 / 0.0550 | 3.1290 / 3.1945 / 3.2880 | 0.1550 / 0.1660 / 0.1860 |
| memset / candidate | 0.0480 / 0.0540 / 0.0610 | 3.0660 / 3.2470 / 3.3060 | 0.1610 / 0.1710 / 0.1920 |
| memset / baseline_interpreted | 0.0500 / 0.0530 / 0.0570 | 4.0850 / 4.3420 / 4.5060 | 0.0000 / 0.0000 / 0.0000 |
| memset / candidate_interpreted | 0.0510 / 0.0545 / 0.0590 | 4.1860 / 4.3070 / 4.3310 | 0.0000 / 0.0000 / 0.0000 |
| sieve / baseline | 1.5740 / 1.6060 / 1.7700 | 193.9530 / 194.0560 / 195.0530 | 2.6800 / 2.7480 / 2.8410 |
| sieve / candidate | 1.5980 / 1.6645 / 1.7310 | 193.2610 / 194.3510 / 195.5270 | 2.6810 / 2.7145 / 2.7360 |
| sieve / baseline_interpreted | 1.5450 / 1.6070 / 1.9120 | 329.9910 / 333.7025 / 334.1300 | 0.0000 / 0.0000 / 0.0000 |
| sieve / candidate_interpreted | 1.5800 / 1.5970 / 1.6730 | 332.5450 / 333.6260 / 334.8530 | 0.0000 / 0.0000 / 0.0000 |

## Frozen evidence and release status

Source manifest `f4e925044f11e3c0348af77f65b73445760b1c9f1d8a84fe80f9ae03512b8657`; qualification `e0cdda4f2a047f01867b95eda2cbdd0bd83550660543f6c76bf3a8a72d644ac7`; build manifest `a5dbd1480ccda87b07493826dd94087202709eb7e0c5677bc991e389dce9bcab`; initial controls `e151f64b747f62ddc99c310ffe0f2a3fc4c197cc2b6cfbcea491c773fb4a0daf`; first36 `dc40f1e434825e2a558008cecc591ceaabc28d99948a6e72de740d6e85e55585`; broader controls `1d1fec28bb2866cf7327c9fe90503022dec6443b3e109d82d3ab842661fbdc9e`; broader108 `13b03a6636a08955cc582e6e24b5c8cbaaf7338e2309aeafe11d45bd123f1735`. Independent checks cover all strict logs and complete schedules, 1,022 frozen source hashes, 55 input identities, all image equalities and within/across-source native activity.

A prior stacked owner-borrow screen used the held read-continuation runtime and is not pooled with this independent master comparison. It had tick -1.149552% with opposite process outliers/overlap and init -0.369011% with a high baseline process; interpreted tick -3.731808% and init +1.598167%, both consistent/non-overlapping in opposite directions. Its raw manifest `05dde7b19ff965db062fc835440d025f03a343b945eb4e5ee9b3d9de3cb68bbb` remains preserved. The read-continuation PR stays separately held on Linux regressions and is not a dependency.

The focused Linux ARM replay below completed. This source remains a reviewable draft on performance-tradeoff hold, with no broad CI labels or general speed claim.

## Linux ARM replay: performance-tradeoff hold

[Run41386090444](https://github.com/jacogr/ragnarok/actions/runs/41386090444) passed at `8cf62862d27aca4fbaffafd220e718ec2aa9b6ff` against exact d74. [Independent review](https://github.com/jacogr/ragnarok/pull/1893#issuecomment-6568964719) found no source/correctness defect. The result is mixed across execution policies and workloads.

| Replay case | Baseline median CPU ms | Candidate median CPU ms | Median change | Mean change | Faster pairs | Baseline / candidate ranges ms |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| tick | 20.794546 | 20.677430 | -0.563205% | -0.593058% | 6/6 | 20.750376–20.873812 / 20.572720–20.744292 |
| init | 141.618664 | 142.247246 | +0.443855% | +0.494150% | 1/6 | 140.785536–142.331756 / 141.878780–142.960776 |
| minimal | 5.224968 | 5.245536 | +0.393648% | +0.551997% | 3/6 | 5.200076–5.277024 / 5.214776–5.310996 |
| pinky | 78.516808 | 78.428740 | -0.112165% | -0.033853% | 3/6 | 78.341196–78.670168 / 78.306824–78.698444 |
| sieve | 253.338344 | 256.232916 | +1.142572% | +1.011140% | 0/6 | 253.203652–253.475096 / 254.561164–256.400160 |

All six native tick pairs are faster with non-overlapping ranges. All six Sieve 10m pairs are slower with non-overlapping ranges. Init has five slower pairs with overlap; Minimal and Pinky are mixed/overlapping. No outlier or process was excluded.

| Primary case | JIT median change | JIT faster pairs / ranges | Forced-interpreter median change | Interpreter faster pairs / ranges |
| --- | ---: | --- | ---: | --- |
| init-0 | +0.855671% | 0/2 / non-overlapping | +0.525166% | 0/2 / non-overlapping |
| memset-100000 | +0.280755% | 0/2 / non-overlapping | -0.021821% | 1/2 / overlapping |
| minimal-100000 | -0.010019% | 1/2 / overlapping | -0.822676% | 2/2 / non-overlapping |
| pinky-1 | +0.021141% | 1/2 / overlapping | -0.113138% | 1/2 / overlapping |
| sieve-100000 | -1.294554% | 1/2 / overlapping | -0.271015% | 2/2 / non-overlapping |
| sieve-10000000 | +1.304388% | 0/2 / non-overlapping | +0.666347% | 0/2 / non-overlapping |
| tick-0 | -0.227233% | 2/2 / non-overlapping | +2.826815% | 0/2 / non-overlapping |

Matched raw primary ours/PolkaVM-interpreted ratios: tick **0.516793 JIT / 0.718559 interpreted**, init **0.227437 / 0.506860**. The primary interpreter tick +2.826815% cost is consistent in both process pairs/non-overlapping; primary init and Sieve also show costs in both policies. The smaller native tick gain and clearer owner lifetime remain useful evidence, but do not remove those measured costs. These Linux and macOS cohorts stay separate.

Cold process-CPU brackets across the same six replay processes are minimum / median / mean / maximum milliseconds. Native preparation/publication CPU is already inside call CPU and is not added again or called wall elapsed time.

| Case / source | Constructor CPU ms | First call CPU ms | Native preparation CPU ms |
| --- | --- | --- | --- |
| tick / baseline | 8.487288 / 8.566480 / 8.549643 / 8.595320 | 31.942768 / 31.995564 / 32.065736 / 32.265744 | 2.324080 / 2.348900 / 2.363263 / 2.438336 |
| tick / candidate | 8.464424 / 8.523508 / 8.507393 / 8.540264 | 31.846728 / 31.997216 / 32.015529 / 32.177592 | 2.335552 / 2.354680 / 2.399981 / 2.637816 |
| init / baseline | 8.454280 / 8.519748 / 8.562845 / 8.789768 | 162.773552 / 163.662584 / 163.688297 / 164.516448 | 7.689576 / 7.806520 / 7.788487 / 7.883744 |
| init / candidate | 8.451296 / 8.526164 / 8.620467 / 9.164520 | 163.611952 / 164.413656 / 164.764469 / 167.793512 | 7.642928 / 7.757448 / 7.799723 / 8.094712 |
| minimal / baseline | 0.015928 / 0.018972 / 0.018707 / 0.021032 | 5.413584 / 5.442408 / 5.442091 / 5.468072 | 0.092856 / 0.096264 / 0.096893 / 0.101200 |
| minimal / candidate | 0.013992 / 0.015176 / 0.016303 / 0.020360 | 5.431408 / 5.456540 / 5.466793 / 5.522432 | 0.093760 / 0.098164 / 0.100289 / 0.112496 |
| pinky / baseline | 0.703304 / 0.727756 / 0.732765 / 0.790592 | 82.979720 / 83.174720 / 83.142875 / 83.325272 | 1.827208 / 1.884120 / 1.878304 / 1.925104 |
| pinky / candidate | 0.707504 / 0.723568 / 0.726463 / 0.751960 | 82.856048 / 82.992080 / 83.046163 / 83.365408 | 1.812808 / 1.877732 / 1.877883 / 1.928648 |
| sieve / baseline | 2.876704 / 2.928056 / 2.925811 / 2.960240 | 261.180664 / 261.308580 / 261.326881 / 261.516800 | 3.062152 / 3.139564 / 3.134931 / 3.181752 |
| sieve / candidate | 2.879608 / 2.920496 / 2.933072 / 3.009760 | 263.192168 / 264.232504 / 264.145331 / 265.069216 | 3.096008 / 3.137676 / 3.164264 / 3.337168 |

Official artifact `13115573836`: ZIP SHA-256 `5dae1845adab24a796cd7dde83065780ab39a67fd5d6684d9caaffcd96268108`; applications report `70e7a4d5aa1f199cd3804182dcd87909116579198c51376b73f5ad063ec7e292`; native report `92d79ad3daafc640d367a159c4e8eeaf4df6740124db629e3ad9e1c7d4576ffa`. Independent root checks cover all 144 strict process parses, exact 60 replay schedule, 42 positive/96 refused controls, 2,575 role / 519 native source hashes, 32 fixture identities, 18 duplicate/policy image equalities, 11 native records, two policy suites and unchanged six non-time native work/code metrics across source roles. The final evidence-only spec change does not alter the measured runtime/witness.

This draft preserves a qualified scoped-borrow implementation. Reconsidering it or combining it with a larger execution region requires evidence for that resulting runtime; no readiness, lgtm or additional CI is requested here.
