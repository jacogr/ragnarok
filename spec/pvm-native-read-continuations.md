# Native read continuations through canonical control

Baseline: `d74ce4dd118eb260f07afef06f1b319f49c33c95`. Pinned Nimony: `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`. Gray Paper 0.8: `3861aed15d7d016a3a416e14e61fc67dddf6daec`.

## Execution and correctness

A successfully completed multi-read native span ending at opcode 1 can invoke its canonical C control worker in the same activation. That worker retains target resolution and validation, paid-state reset and failure behavior. It returns the next executable offset to ordinary dispatch; it does not recursively execute another guest block. The terminal remains C work and is excluded from native operation/branch counts.

A private static template shares the existing native memory bridge. Its descriptor/register borrow ends before mutable control or checked fallback. Partial reservations and native guard refusals invoke the original checked worker directly; successful checked fallback does not take this shortcut. The existing span admission, source accounting, permissions, publication, image limits and prepared ownership remain unchanged. There is no new native image, ABI, GP evaluator, retained invocation pointer or frame field.

The functional witness compares 365 paid/unpaid, gas, attempt, folded-source and span-boundary cases against independent Step execution, including later faults, fragmented reads and invalid following blocks. Separate literal checks cover all-thirteen-register rollback, exact next-block out-of-gas PC/paid state and oversized-image fallback. The controller requires those four complete receipts in native, OS-refused and plain modes; its fixtures independently reject missing, truncated and duplicated receipts. These checks exercise execution semantics rather than handler-array organization.

The frozen runtime handler SHA-256 is `3f0408668c043bf40f121efcbe170743e9cbb2aefda0148669fb6ccf648b1ebe`; backend `3532ea5cbc8bbd023ee898efe94fcef66e028f0584e49c3ae3bc6b79c6d15403` is unchanged. The measured private witness was `90e95015`; the public witness removes only an unused zero activation counter/receipt and corrects inherited comments (`e7e4d3dbcf5beb4e6e910850676fa94acf64bc00f73b2ccfa84eaadef69cfbbb`).

## Local ARM evidence

Checked ARC/Clang ThinLTO images used one canonical source path and identical commands per driver family. All four fresh duplicate pairs were byte equal. Each process validated 13 complete public calls; reported CPU medians use calls 3–12, with no sample or process exclusion. Both source-matched forced-interpreter controls and matched PolkaVM interpreted references are retained. Source-specific and reference timings are call-only observations, not full blockchain throughput.

The first 36-process screen recorded DOOM tick -0.704625% with all four pairs faster and non-overlapping process ranges; init +0.324481% with all four slower and non-overlapping ranges. Interpreter tick +0.143771% was mixed/overlapping; init -0.314837% had three faster pairs/overlap. Raw ours/reference tick ratios were 0.309830 JIT / 0.513138 interpreted; init 0.164721 / 0.349063. Raw manifest SHA-256: `158b4fb54238925bd46a1d6be5ac07d25bfadc130902c437cffa45c54a24ab34`.

A separate broader 108-process gate reused those exact images and pinned inputs after 20 positive and 40 intended refusal controls. Its six cases retained four balanced source/policy orders, two duplicate images and two matched references per case. The earlier 36-process screen remains separate.

| Case / policy | CPU median change | Faster pairs | Process ranges | Candidate / baseline ratios, orders 0–3 |
| --- | ---: | ---: | --- | --- |
| tick / JIT | -0.964736% | 3/4 | overlapping | 1.039328 / 0.985244 / 0.992015 / 0.988940 |
| tick / interpreted | +0.859053% | 1/4 | overlapping | 1.007676 / 1.004348 / 1.052567 / 0.991684 |
| init / JIT | +0.251866% | 0/4 | non-overlapping | 1.002303 / 1.001602 / 1.002704 / 1.004009 |
| init / interpreted | -0.762205% | 3/4 | overlapping | 0.991562 / 0.993193 / 1.002891 / 0.988358 |
| minimal / JIT | +1.091135% | 1/4 | overlapping | 0.994225 / 1.013289 / 1.008542 / 1.019236 |
| minimal / interpreted | +0.435694% | 1/4 | overlapping | 1.010042 / 1.006491 / 1.003488 / 0.999118 |
| pinky / JIT | -0.186464% | 3/4 | overlapping | 0.997595 / 1.003950 / 0.997341 / 0.997973 |
| pinky / interpreted | -0.048147% | 1/4 | overlapping | 1.004633 / 0.996535 / 1.000794 / 1.001034 |
| memset / JIT | +0.040314% | 1/4 | overlapping | 1.001612 / 1.003630 / 0.996982 / 1.000000 |
| memset / interpreted | +0.148689% | 2/4 | overlapping | 0.997172 / 1.003113 / 1.003785 / 0.999324 |
| sieve / JIT | +0.358111% | 0/4 | non-overlapping | 1.002034 / 1.005095 / 1.003683 / 1.005564 |
| sieve / interpreted | +0.294370% | 1/4 | overlapping | 1.003562 / 0.943794 / 1.005566 / 1.002326 |

The broader raw ours/reference ratios are DOOM tick **0.309319 JIT / 0.513234 interpreted**, init **0.164236 / 0.346934**. Init and Sieve JIT costs are consistent across every pair; Minimal and interpreter tick also have slower medians. Tick has one slower pair and overlapping ranges. This supports a small workload-specific improvement and reduced dispatch, not a general speed claim.

The broader raw manifest SHA-256 is `2227edb5d0ab8e0a533f30a936b091b0d7f2ae46f8f23f4a836eab494cd7a070`. The build manifest is `3dadc58973847b0ee73019fc38770292b3320742201298f945de88345c853aff`. Independent review checked all 108 strict parses, exact schedule, 1,022 source hashes, eight images/four duplicate equalities, 55 fixture identities, complete control logs and intended refusal reasons.

All six non-time native metrics match baseline exactly for every case/order; interpreted metrics are zero. DOOM tick retains 1,013 fragments, 10,584,184 calls, 175,146,673 operations, 253,416 code bytes, 6,990,119 branches and 5,625,893 headers. Init retains 1,024 / 17,233,187 / 2,289,314,092 / 230,056 / 7,902,385 / 5,448,073.

An isolated, fully validated unclocked DOOM tick observed 160,528 native-success canonical continuations. The earlier complete dispatch census fell from 1,606,537 to 1,446,009 outer selections per warm call with unchanged native work/code. Its scope counts outer selections and charge-body calls; it does not count every nested C helper. The control worker still executes. Instrumented source/images were excluded from timing. Actual ARM disassembly has 90 instructions in the continuation worker, a 64-byte frame and no extra memory-worker call.

## Cold costs in the broader gate

Each entry below is minimum / median / maximum across four processes, in milliseconds of **process CPU time**. Compilation diagnostics use process CPU, not wall elapsed time; they are already included in the corresponding call and must not be added again. Constructor and first-call measurements are retained rather than inferred from warmed medians.

| Case / source / policy | Constructor CPU ms | First call CPU ms | Compilation CPU ms |
| --- | --- | --- | --- |
| tick / baseline | 7.1560 / 7.1780 / 7.9030 | 20.2980 / 20.5980 / 22.2340 | 1.9020 / 1.9790 / 2.3470 |
| tick / candidate | 7.0850 / 7.1030 / 7.1460 | 20.2310 / 20.3525 / 20.4130 | 1.8950 / 1.9500 / 2.0060 |
| tick / baseline_interpreted | 7.0770 / 7.0920 / 7.1230 | 25.8270 / 25.8690 / 25.9420 | 0.0000 / 0.0000 / 0.0000 |
| tick / candidate_interpreted | 7.0720 / 7.1040 / 7.1230 | 25.9420 / 25.9630 / 26.1100 | 0.0000 / 0.0000 / 0.0000 |
| init / baseline | 7.0860 / 7.1310 / 7.3500 | 128.4450 / 128.5970 / 136.3800 | 5.9650 / 5.9755 / 6.9450 |
| init / candidate | 7.0580 / 7.0730 / 7.1070 | 128.8530 / 129.1500 / 129.4160 | 5.9680 / 5.9980 / 6.0200 |
| init / baseline_interpreted | 7.0860 / 7.1115 / 7.2720 | 242.0210 / 242.5610 / 244.6470 | 0.0000 / 0.0000 / 0.0000 |
| init / candidate_interpreted | 7.0670 / 7.0805 / 7.0970 | 240.7970 / 241.9025 / 242.2800 | 0.0000 / 0.0000 / 0.0000 |
| minimal / baseline | 0.0120 / 0.0170 / 0.0600 | 3.9750 / 4.1180 / 10.3740 | 0.0490 / 0.0570 / 0.1290 |
| minimal / candidate | 0.0150 / 0.0170 / 0.0370 | 4.1510 / 4.1915 / 4.3040 | 0.0490 / 0.0640 / 0.0930 |
| minimal / baseline_interpreted | 0.0130 / 0.0150 / 0.0160 | 4.4540 / 4.5055 / 4.5650 | 0.0000 / 0.0000 / 0.0000 |
| minimal / candidate_interpreted | 0.0120 / 0.0140 / 0.0160 | 4.4340 / 4.5260 / 4.6280 | 0.0000 / 0.0000 / 0.0000 |
| pinky / baseline | 0.4440 / 0.4780 / 0.5030 | 63.8110 / 64.1800 / 65.3410 | 1.6800 / 1.7160 / 1.9440 |
| pinky / candidate | 0.4450 / 0.4685 / 0.4850 | 64.2770 / 64.3420 / 65.0470 | 1.6910 / 1.7490 / 1.7900 |
| pinky / baseline_interpreted | 0.4500 / 0.4770 / 0.5210 | 80.7870 / 81.5770 / 81.8940 | 0.0000 / 0.0000 / 0.0000 |
| pinky / candidate_interpreted | 0.4550 / 0.4805 / 0.5290 | 81.4510 / 81.5595 / 82.3390 | 0.0000 / 0.0000 / 0.0000 |
| memset / baseline | 0.0540 / 0.0575 / 0.0580 | 3.2370 / 3.3400 / 3.5830 | 0.1660 / 0.1875 / 0.1940 |
| memset / candidate | 0.0490 / 0.0495 / 0.0510 | 3.1330 / 3.1725 / 3.3200 | 0.1560 / 0.1630 / 0.1770 |
| memset / baseline_interpreted | 0.0510 / 0.0525 / 0.0530 | 4.3010 / 4.3250 / 4.3530 | 0.0000 / 0.0000 / 0.0000 |
| memset / candidate_interpreted | 0.0500 / 0.0530 / 0.0560 | 4.0840 / 4.2945 / 4.4110 | 0.0000 / 0.0000 / 0.0000 |
| sieve / baseline | 1.5530 / 1.6045 / 1.6570 | 193.3080 / 194.2585 / 194.4290 | 2.7130 / 2.8535 / 2.8860 |
| sieve / candidate | 1.5400 / 1.6330 / 1.7130 | 194.4230 / 194.8640 / 196.1580 | 2.6830 / 2.7875 / 2.7950 |
| sieve / baseline_interpreted | 1.5620 / 1.6125 / 1.6690 | 333.3120 / 334.1125 / 351.5540 | 0.0000 / 0.0000 / 0.0000 |
| sieve / candidate_interpreted | 1.5970 / 1.6640 / 1.7880 | 332.5650 / 333.9510 / 334.9890 | 0.0000 / 0.0000 / 0.0000 |

## Scope and qualification

The frozen private candidate passed all 11 retained ARM native/refusal/ownership checks plus both policy suites, prepared blocks, gas plan, gas memo, pricing-owner and plain checks. The updated public controller passed all 11 retained ARM native/refusal/ownership checks and the plain witness against the exact public runtime/witness hashes above. The receipt-controller fixtures pass all 19 Python tests. Pinned formatting and whitespace checks pass. One focused Linux ARM replay comparison remains required before readiness; Linux evidence will be recorded here when available.

The earlier C prototype has different runtime source and is not pooled with these measurements: its 52-process screen had tick -3.475% (3/4 faster/overlap), init +0.425295% (3/4 faster/overlap); its 108-process screen had tick -1.118789% (3/4 faster/overlap), init +0.038125% (3/4 slower/overlap), Sieve +0.321084% (3/4 slower/overlap). Both retain all outliers. Their manifests are `bd02f26601be952e118ed90f0e70cea749e6f84adeb25e3bd3e3ec73f1aa449c` and `c226d2f28a943c61f62bd55d9dc2ad55ada885c5486a0e51156a8ee125e9364e`. A larger native-jump prototype remains private; its results do not qualify this implementation.
