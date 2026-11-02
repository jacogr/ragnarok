# ARM native macro regions

A hot resident memory cycle currently returns to C for a static jump, a pure conditional block, a signed scalar branch and a guarded read block. This change keeps that source-derived graph inside one native entry, linking the three existing same-owner children and lowering the scalar controls. It preserves an independent checked return at every source block boundary.

## Admission and ownership

- The existing resident cycle owns prefix, dirty and tail blocks. Its exit must lead through a cached opcode40 to an existing whole pure 131/149/81 child. One pure arm exits to checked code; the other reaches a genuine scalar88 whose arms return to pure or enter the full guarded-read block. The read terminal1 returns to the cycle. Register numbers, immediates, source PCs and code addresses come from admitted source; none are benchmark constants.
- Seven internal source headers must be distinct. Frame admission proves complete source spans, including folded leading noops, matching prices, cached targets and the three installed handler ABIs. The current conservative Frame limit is 64 source instructions per block. Custom pricing, paid entry and temporary barriers use the existing checked paths.
- Publication appends one separate macro image and scalar cache record. It does not overwrite the resident cycle, pure or read entry. The existing 1,024-fragment/1MiB limits, aligned/range-checked same-arena branches and W^X publication remain in force. Failed discovery/publication retires only macro observation.
- Current invocation registers, descriptors, dirty words and the 26-word state are borrowed for one call. No frame or memory address is retained. All Frame mutation and checked fallback occur after the JIT cursor scope. Code-only transfer uses fresh registers and memory mappings.

## Charging and returns

Each block tests zero attempts before price, then the full source span before mutation. Partial entries return to the unstarted canonical header. A late read refusal refunds exactly the unread block, preserving earlier stores, registers and completed work. State word13 is the cycle child's last completed header; separate word24 is the global last completed header across the full graph. Returning to the root invokes its saved canonical handler rather than recursively re-entering the macro.

Global calls/branches/headers count one C-to-arena entry. Native operations include genuine scalar40/88/1 work and completed child operations; folded noops count only source attempts. Nested cycle calls have separate counters. Existing memoryCycle.calls continues to count C-to-arena cycle entries. Return-time gas and attempt conservation checks cover every semantic category.

## Final fixed-head Linux ARM qualification

Run [41401353716](https://github.com/jacogr/ragnarok/actions/runs/41401353716) passed on runtime head `851f6db63c9b9cb4c59cfdb7bbb35d2f46294d68` against exact d74. Artifact 13122271929 ZIP SHA256: `8ee507fd652cc0e437d7317702b1fc514788d88b93d26ccec2269617a7e43e34`. Application/native report SHA256: `716e008aabefc1955c44d4ba467d6c4d928bc0898c94a8ecb6b8d20a941ed786` / `9c4fe4605e3ba42e13325132d099d033849ba69eb9c19af42b97a3f72cdeab07`.

The author independently verified all 2,575 role and 519 native source hashes, 84 primary and 60 scheduled replay parses, 138 positive/refusal controls, all 12 qualification rows and all seven macro receipts, and 18 image equalities. Independent review additionally matched 317 raw/embedded logs and smoke source hashes. Native semantic-work receipts match original b32 across workloads; both interpreter policies report zero native work.

Six scheduled replay pairs use CPU medians from fixed sample indices 3 through 12, keeping every process and outlier. Millisecond source-group brackets below are min / median / mean / max; change is ratio of source-group medians.

| Workload | Baseline CPU ms | Candidate CPU ms | Change | Faster pairs | Ranges overlap |
| --- | --- | --- | ---: | ---: | --- |
| tick | 20.888172 / 20.904200 / 20.910749 / 20.942672 | 16.358544 / 16.400274 / 16.397874 / 16.425560 | -21.545555% | 6/6 | False |
| init | 141.587732 / 142.225352 / 142.212984 / 143.021880 | 140.700664 / 140.892384 / 140.995792 / 141.820412 | -0.937223% | 5/6 | True |
| minimal | 5.208628 / 5.214464 / 5.234046 / 5.280044 | 5.214788 / 5.280094 / 5.263931 / 5.294432 | +1.258614% | 1/6 | True |
| pinky | 78.429584 / 78.521476 / 78.530676 / 78.635784 | 79.508044 / 79.706712 / 79.683076 / 79.767272 | +1.509442% | 0/6 | False |
| sieve | 253.272344 / 253.357410 / 253.365935 / 253.542256 | 270.594620 / 270.738136 / 271.682662 / 273.711648 | +6.860161% | 0/6 | False |

**Sieve +6.860161% and Pinky +1.509442% are repeatable costs**, with all six candidate processes slower and nonoverlapping ranges. Sieve remains slower in calls 3–7 (+6.843755%) and calls 8–12 (+6.880703%); no causal attribution or warmup dismissal is made. Minimal is +1.258614% by median (five slower, overlapping; mean +0.570980%). Init is -0.937223% (five faster, overlapping). Native DOOM tick is -21.545555%, all six faster/nonoverlapping.

The tradeoff is accepted for the explicit DOOM-first application priority and the larger native-region architecture gain. It is not an all-workload improvement. Sieve remains a follow-up performance target; neither its final cost nor the separate earlier costs are suppressed.

Primary two-process results are a separate cohort. Each baseline/candidate cell gives median CPU milliseconds; direction and overlap refer to those two process medians.

| Workload / policy | Baseline ms | Candidate ms | Change | Faster pairs | Ranges overlap |
| --- | ---: | ---: | ---: | ---: | --- |
| init/0 / jit | 141.784546 | 141.699824 | -0.059754% | 2/2 | True |
| init/0 / interpreter | 317.630100 | 316.641482 | -0.311248% | 2/2 | False |
| memset/100000 / jit | 3.290964 | 3.292858 | +0.057552% | 0/2 | True |
| memset/100000 / interpreter | 3.443876 | 3.453268 | +0.272716% | 0/2 | True |
| minimal/100000 / jit | 5.281336 | 5.248500 | -0.621737% | 1/2 | True |
| minimal/100000 / interpreter | 5.478022 | 5.481478 | +0.063088% | 1/2 | True |
| pinky/1 / jit | 78.393218 | 79.543130 | +1.466851% | 0/2 | False |
| pinky/1 / interpreter | 86.165196 | 86.865014 | +0.812182% | 0/2 | False |
| sieve/100000 / jit | 2.591908 | 2.575374 | -0.637908% | 2/2 | False |
| sieve/100000 / interpreter | 3.061670 | 3.070612 | +0.292063% | 0/2 | False |
| sieve/10000000 / jit | 253.438526 | 270.808770 | +6.853829% | 0/2 | False |
| sieve/10000000 / interpreter | 321.088920 | 319.813048 | -0.397358% | 2/2 | False |
| tick/0 / jit | 20.932636 | 16.409620 | -21.607484% | 2/2 | False |
| tick/0 / interpreter | 28.087940 | 27.384558 | -2.504214% | 2/2 | False |

Final primary raw ours / PolkaVM interpreted: DOOM tick **0.409536589 native / 0.683439255 interpreter**; init **0.224924948 / 0.502615790**. Primary native tick is -21.607484% and interpreted tick -2.504214%, both pairs agree with nonoverlapping ranges. Primary native large Sieve is +6.853829%, Pinky +1.466851%; both pairs agree/nonoverlapping.

Cold native diagnostics use the same six replay processes, with min / median / mean / max brackets in milliseconds. Constructor and first-call values are process CPU. Native preparation/publication is the owner's cumulative process CPU diagnostic across the retained calls; it is already included in those calls and is not added to first-call or lifecycle totals.

| Workload / source | Constructor CPU ms | First-call CPU ms | Native preparation/publication CPU ms |
| --- | --- | --- | --- |
| tick / baseline | 8.543624 / 8.608692 / 8.614437 / 8.737656 | 32.154592 / 32.406500 / 32.418647 / 32.632320 | 2.386776 / 2.416412 / 2.441731 / 2.592336 |
| tick / jit | 8.533208 / 8.587044 / 8.581925 / 8.629632 | 27.178512 / 27.506376 / 27.601629 / 28.114280 | 2.387192 / 2.396180 / 2.404612 / 2.439144 |
| init / baseline | 8.539744 / 8.632852 / 8.622729 / 8.698320 | 163.904344 / 164.379956 / 164.320769 / 164.774736 | 7.676432 / 7.824216 / 7.821087 / 7.926040 |
| init / jit | 8.497920 / 8.645668 / 8.616296 / 8.713136 | 162.366576 / 162.727924 / 162.691524 / 162.862664 | 7.652248 / 7.797272 / 7.772885 / 7.863824 |
| minimal / baseline | 0.016672 / 0.017588 / 0.017655 / 0.018848 | 5.418448 / 5.438280 / 5.448933 / 5.511552 | 0.094256 / 0.098688 / 0.098125 / 0.100784 |
| minimal / jit | 0.017592 / 0.019652 / 0.019355 / 0.020472 | 5.421328 / 5.499468 / 5.480072 / 5.531672 | 0.089240 / 0.097264 / 0.097032 / 0.106976 |
| pinky / baseline | 0.703352 / 0.723152 / 0.720539 / 0.729296 | 83.005504 / 83.183908 / 83.140555 / 83.233576 | 1.816568 / 1.857772 / 1.866443 / 1.936376 |
| pinky / jit | 0.694224 / 0.728960 / 0.734480 / 0.792040 | 83.959496 / 84.265628 / 84.222363 / 84.369480 | 1.847944 / 1.886532 / 1.882736 / 1.906400 |
| sieve / baseline | 2.810984 / 2.872512 / 2.867213 / 2.920856 | 260.925744 / 261.238108 / 261.225740 / 261.435632 | 3.078448 / 3.122496 / 3.115607 / 3.136592 |
| sieve / jit | 2.845768 / 2.865944 / 2.910803 / 3.019584 | 278.096336 / 279.161424 / 279.670120 / 281.582592 | 3.027440 / 3.065984 / 3.080941 / 3.188432 |

Interpreted DOOM cold CPU uses the separate two primary processes per source. Native preparation/publication is exactly zero. Milliseconds retain min / median / mean / max.

| Phase / source | Constructor CPU ms | First-call CPU ms |
| --- | --- | --- |
| tick / baseline_interpreter | 8.616824 / 8.641796 / 8.641796 / 8.666768 | 36.308456 / 36.734324 / 36.734324 / 37.160192 |
| tick / interpreter | 8.578200 / 8.670536 / 8.670536 / 8.762872 | 35.607872 / 35.905924 / 35.905924 / 36.203976 |
| init / baseline_interpreter | 8.695480 / 8.699200 / 8.699200 / 8.702920 | 328.968144 / 329.739252 / 329.739252 / 330.510360 |
| init / interpreter | 8.556088 / 8.641832 / 8.641832 / 8.727576 | 328.463560 / 328.594604 / 328.594604 / 328.725648 |

DOOM tick first-call CPU is 32.406500 to 27.506376 ms (-15.120806%). Sieve first-call CPU is 261.238108 to 279.161424 ms (+6.860912%). The initial b32 Linux replay remains separate: tick -21.573525%, Sieve +2.450383%, Pinky +1.316827%. Those measurements do not replace the stronger fixed-head Sieve cost.

Fixed runtime SHA256: handler_stream.nim `e89d9fd9bea2825aa1336adbef434e9d2d8aaad5bcd706f8d871aa045d315b28`, arm64_jit.nim `56b915188a108bac36efd5acf4b230e60ff53cdf42e491811eac202cc1158316`; step.nim remains `1e4ee7636d575e5583bfb3be3954d27395b1c0858c26b3158d64f3a06e6d6f5f`. Author audit: build/pvm-arm-native-regions/ci-fixed-audit.json. Independent complete source/cold record: /tmp/review1894/fixed/final-cold-source-record.json.

## Linked publication fallback regression

Independent review of b32ad5c found that a successful smaller linked-cycle
publication installed the resident-only macro observer. Its first eligible exit
called armMacroCycleExit, whose resident-mode precondition correctly rejected the
linked cache. This was a real assertion failure; the original resident-only
Frame fixtures missed the publication outcome.

The observer is now installed only for resident cycles. The observer itself also
checks resident eligibility before the resident-only getter. Linked cycles keep
the original flatArmMemoryCycle handler directly.

A per-owner, receipt-only fault injection declines resident publication while
leaving actual source discovery and linked publication intact. The new Frame
regression reproduced the assertion on the unfixed code. After the fix it checks
all budgets 0 through 160, full Step CPU/memory results and actual linked activity
after moving the code cache into a fresh frame. It proves resident/macro work
stays inactive. The 162-case receipt is mandatory in native and macro-append-refused
builds; native-storage-refused and plain builds report zero. Paired positive,
missing, truncated and duplicate protocol fixtures cover this seventh receipt.
All four complete local main-witness builds pass, and all 19 Python tests pass.
Evidence is in build/pvm-arm-native-regions/linked-fallback/audit.json, including
the original failing execution and all fixed source hashes.

The local measurements below and the separately retained first Linux replay belong to original head
b32ad5c1508adee22789cc913d207ed0e6f01e65, before this eligibility fix. They are
preserved as measured evidence; they do not qualify the follow-up source.

## Final default-path qualification

The production source enables the admitted graph in the regular ARM path. Copied Frame/stream/prepared activity diagnostics are guarded by pvmArmMacroReceipt; no Prototype behavior define is required. Runtime SHA256:

- arm64_jit.nim: `5cc2046b7d526c4308d7226ad1c0fb1891438cf22657ead093db51c54d058c82`
- handler_stream.nim: `4d3c7f0cd3f16eace31ade85cc563e5fc3cc5a63e60c7deaafbbcae9c9c5d586`
- step.nim: `1e4ee7636d575e5583bfb3be3954d27395b1c0858c26b3158d64f3a06e6d6f5f`

The complete 12-row maintained ARM qualification and plain witness pass on this runtime, including normal, native-storage refusal, macro append refusal, all-opcodes, host and four ownership orders. The final controller additionally skips the native-only macro append-refusal build on checked-only hosts; that controller-only correction leaves the qualified ARM command matrix and every compiled source unchanged. All original six mandatory receipts have paired native/refused/plain positives and independent missing/truncated/duplicate negatives; the Python suite passes 19 tests.

Final-source public qualification passes 18 full 13-call cohorts plus six DOOM assertion/state/event negatives. The eight actual final timing images also pass 48 positives and 112 assertion/state/event negatives. All 555 public qualification identities and 1,049 final pilot source/image/fixture identities were independently checked. Native macro activity remains exactly the same as the private prototype.

All four final duplicate image pairs are byte identical within their source/family. Final image hashes differ from the private prototype, so the final source received one new balanced 36-process DOOM pilot. Its 468 raw samples and every outlier are retained; it does not pool or replace either earlier cohort.

| DOOM phase | Native change | Native faster groups | Native ranges overlap | Interpreted change | Interpreted faster groups | Interpreted ranges overlap |
| --- | ---: | ---: | --- | ---: | ---: | --- |
| tick | -20.258% | 4/4 | False | -0.042% | 2/4 | True |
| init | +0.431% | 1/4 | True | +0.262% | 1/4 | True |

Final native tick group medians are 11.375 / 10.917 / 10.8885 / 10.8645 ms versus 13.6695 / 13.7445 / 13.6755 / 13.6675 ms on d74. Matched raw ours / PolkaVM interpreted ratios are 0.255848 and 0.244064 for native tick, 0.504408 and 0.501505 for interpreted tick. Init is slightly slower in this final cohort: native +0.431% and interpreted +0.262%, both with overlapping ranges. These final-source results and earlier prototype micro costs remain visible separately.

Final cold CPU values are milliseconds in min / median / mean / max order, without double-counting native preparation CPU.

| DOOM phase / source | Constructor CPU | First call CPU | Native preparation CPU |
| --- | --- | --- | --- |
| tick / baseline | 7.034 / 7.109 / 7.099 / 7.146 | 20.339 / 20.459 / 20.441 / 20.507 | 1.902 / 1.971 / 1.956 / 1.979 |
| tick / candidate | 7.059 / 7.085 / 7.171 / 7.454 | 17.511 / 17.631 / 17.942 / 18.992 | 1.911 / 1.951 / 2.018 / 2.259 |
| tick / baseline_interpreted | 7.051 / 7.112 / 7.123 / 7.218 | 25.856 / 26.137 / 26.203 / 26.684 | 0.000 / 0.000 / 0.000 / 0.000 |
| tick / candidate_interpreted | 7.055 / 7.061 / 7.081 / 7.149 | 25.851 / 25.966 / 26.017 / 26.287 | 0.000 / 0.000 / 0.000 / 0.000 |
| init / baseline | 7.053 / 7.069 / 7.224 / 7.704 | 128.440 / 128.708 / 128.756 / 129.167 | 5.935 / 5.987 / 5.995 / 6.074 |
| init / candidate | 7.071 / 7.239 / 7.242 / 7.418 | 128.782 / 129.084 / 129.441 / 130.813 | 5.974 / 6.117 / 6.097 / 6.181 |
| init / baseline_interpreted | 6.994 / 7.101 / 7.199 / 7.600 | 241.501 / 241.990 / 242.260 / 243.558 | 0.000 / 0.000 / 0.000 / 0.000 |
| init / candidate_interpreted | 7.009 / 7.049 / 7.045 / 7.072 | 241.795 / 242.298 / 242.316 / 242.873 | 0.000 / 0.000 / 0.000 / 0.000 |

Final private evidence: build/pvm-arm-native-regions/qualification/{results.json,controller-supplement.json}, final-public-audit.json and final-pilot-audit/audit.json. Final pilot raw SHA256: `7b664c0b7cecf7b473c7614542c0fae53d196c5770d9849cbe4524e36da1481d`; final timed controls SHA256: `50b0ba11c2b58510c8ff988ae8861b07cb50020bbcc133d21fcc277fcf6d78e3`. These remain local ARM evidence pending focused Linux ARM qualification.

## Qualified private prototype

The private prototype is based on exact master d74ce4dd118eb260f07afef06f1b319f49c33c95. Its runtime and diagnostics hashes are recorded in build/pvm-arm-macro-prototype/stage2-frame-results.json. This section is prototype evidence; the final default-path source requires its own qualification and measurements.

- Checked release/ARC/Clang ThinLTO with bounds checks enabled: 13,524 Step comparisons in each of normal, native-refused and macro-append-refused builds (40,572 total), plus a proved native signed backedge, late-read refund, fragmented replacement, permission fault and actual macro activity after an owner move.
- Literal backend controls cover independent block/child price boundaries, R12, signed branch and backedge, late read rollback, fresh host buffers, owner/shape refusal, fragment/byte caps and final append refusal without damaging children. Existing memory-cycle/resident witnesses retain their complete 7,236/12,328 Frame cases.
- Eighteen public 13-call DOOM/micro cohorts and six assertion/state/event negative controls passed. Thirteen public native DOOM ticks executed 8,462 outer macro entries containing 1,667,243 nested cycle visits and 1,658,781 complete read blocks. Interpreted policy reports exact zero native/macro activity; init publishes no macro image.
- All eight actual timing images passed 48 positive and 112 assertion/state/event negative controls. Four same-canonical-path duplicate build pairs are byte identical, with identical flags and pinned source/compiler/fixtures.

## Local ARM prototype measurements

One 36-process DOOM pilot showed native tick -20.44% by ratio of source-group medians. One separate broader 108-process cohort used the same frozen images and all six workloads. Every process retains all thirteen complete checked calls; medians use fixed sample indices 3 through 12. The table uses the ratio of the four source-group medians, not the median of paired ratios. All processes and outliers remain in the evidence. These are macOS ARM results, not Linux qualification.

| Workload | Native change | Native faster groups | Native ranges overlap | Interpreted change | Interpreted faster groups | Interpreted ranges overlap |
| --- | ---: | ---: | --- | ---: | ---: | --- |
| tick | -19.809% | 4/4 | False | +0.621% | 1/4 | True |
| init | +0.022% | 2/4 | True | +0.048% | 2/4 | True |
| minimal | -1.252% | 3/4 | True | +0.254% | 2/4 | True |
| pinky | +0.501% | 1/4 | True | +0.035% | 2/4 | True |
| memset | -1.560% | 3/4 | True | -1.655% | 3/4 | True |
| sieve | +0.273% | 0/4 | False | -0.039% | 3/4 | True |

The native DOOM tick gain is consistent across both cohorts. Sieve's +0.273% is a repeatable cost in the broader cohort (all four slower, nonoverlapping ranges). Pinky and interpreted DOOM tick also have higher medians, with overlapping ranges. Init is near parity. These costs remain part of the assessment. Matched broader native DOOM tick / PolkaVM interpreted raw ratios are 0.241122 and 0.255905; interpreted ratios are 0.498353 and 0.492828.

Native tick receipts change from 1,013 to 1,014 fragments, 10,584,184 to 5,602,641 outer native calls, 175,146,673 to 180,128,216 genuinely lowered operations and 253,416 to 254,240 code bytes. Other workload native receipts are unchanged. All metrics are deterministic within source/workload, excluding measured compilation CPU.

The 108-process runner stopped during postprocessing on an obsolete assumption that baseline and candidate native counters must be equal. All 108 timed processes had already passed and their 1,404 samples were saved. The original results retain status incomplete and original script/hash; separate analysis and independent reparse establish the complete results without rerunning any process.

Cold CPU diagnostics below retain every group. Values are milliseconds in min / median / mean / max order. Compilation is cumulative process CPU already included in the measured calls; it is not added again.

| DOOM workload / source | Constructor CPU | First call CPU | Native preparation CPU |
| --- | --- | --- | --- |
| tick / baseline | 7.081 / 7.178 / 7.414 / 8.217 | 20.323 / 20.700 / 21.179 / 22.993 | 1.952 / 2.002 / 2.039 / 2.200 |
| tick / candidate | 7.093 / 7.141 / 7.171 / 7.310 | 17.647 / 17.898 / 17.885 / 18.097 | 1.973 / 2.026 / 2.019 / 2.051 |
| tick / baseline_interpreted | 7.117 / 7.130 / 7.130 / 7.143 | 25.802 / 25.887 / 25.876 / 25.930 | 0.000 / 0.000 / 0.000 / 0.000 |
| tick / candidate_interpreted | 7.055 / 7.085 / 7.083 / 7.107 | 25.824 / 25.937 / 25.928 / 26.015 | 0.000 / 0.000 / 0.000 / 0.000 |
| init / baseline | 7.025 / 7.056 / 7.113 / 7.314 | 128.378 / 128.868 / 129.867 / 133.355 | 5.886 / 5.988 / 6.035 / 6.278 |
| init / candidate | 7.007 / 7.139 / 7.139 / 7.272 | 128.562 / 128.905 / 129.276 / 130.731 | 5.967 / 6.038 / 6.043 / 6.128 |
| init / baseline_interpreted | 6.995 / 7.080 / 7.111 / 7.291 | 242.280 / 242.867 / 244.204 / 248.805 | 0.000 / 0.000 / 0.000 / 0.000 |
| init / candidate_interpreted | 7.049 / 7.064 / 7.075 / 7.123 | 241.811 / 242.542 / 242.509 / 243.140 | 0.000 / 0.000 / 0.000 / 0.000 |

Private evidence pointers: build/pvm-arm-macro-pilot-audit/{audit.json,timed-image-controls.json,broad-audit.json}, build/pvm-arm-macro-prototype/{stage2-frame-results.json,stage3-public-audit.json}; the speed worktree retains original raw cohorts and source/image inventories.

## Remaining architectural work

The three child ABIs still write back and reload guest registers at their boundaries. A future resident variant needs an explicit new ABI and independent lifecycle, partial-budget and refund evidence; it cannot jump to guessed interior code offsets. Pure-family generalization is likewise separate from this measured change. x86-64 is unchanged.

## Resident macro core follow-up

The next increment retains guest X4-X16 across the admitted seven-header source
graph, composing shared typed cycle, pure and multi-read bodies. It removes the
three inner native-child call boundaries; the outer C-to-arena ABI and semantic
child/work counters stay unchanged. The compact 12-byte entry records and OS
arena ownership stay unchanged. This remains source-shaped admission, with no
benchmark name, input or diagnostic PC selection. General native CFG coverage
and multi-root region planning remain future work.

The shared cycle core explicitly borrows X19/X20, carries gas/attempts in
X21/X22, cycle totals in X23-X27 and the global last-completed header in X28.
Its scratch contract includes X0-X3/X17 and D0/D16-D22. The outer image preserves
callee-saved registers and retains X29 for profiling/unwinding. It loads the
union of every read and prospective write before any guard, then publishes only
the written union on exit. Zero-work exits therefore retain initialized values.

A multi-read body may fail after speculative register writes. Only that body's
written guest slots are checkpointed in caller-saved D18-D30 while the read is
live. Every failed guard restores those slots before refunding the whole read
charge/attempt span and replaying the original source. Earlier dirty memory
writes remain committed. The read renderer uses no SIMD scratch; its checkpoint
lifetime ends before the next dirty core. Both the child-local last header in
word 13 and the global last header in word 24 retain their distinct contracts.

Publication checks the complete image, relocations and byte capacity before
installing it. A published image may contain 1 through 1,024 words including RET.
Resident refusal leaves the previous linked macro available without displacing
children or poisoning publication state. Full append and executable-storage
refusal remain separate controls. Native qualification now requires a dedicated
resident-only-refused profile, resident-kind/word-bound/rollback receipts, and
missing/truncated/duplicate and wrong-policy negatives through both the parser
and the full qualification controller.

### Local correctness and source audit

Baseline is merged master `4c1bc91bf1787bc550fcff24d37a5f14c720ebde`. Checked
release ARC/Clang ThinLTO uses the same pinned compiler binary SHA-256
`bf61bfc2c5953de2d3236ddd99be61fce551809a57ce32ca6d34bbc6b1f8bd70`.
Normal resident and forced-linked witnesses pass all 13,524 macro frame controls,
31 backend controls and 162 linked-cycle fallback controls, including signed
backedges, late read refunds and owner moves. Integrated append/storage refusal
and checked-only witnesses also pass. The literal resident image has 620 words;
this count is evidence, not a required exact code layout.

A new address-dependent late-read case changes R10 and R5 before a second read
faults. It checks literal fault PC 39, gas 999639, R5=3, R10=65544 and
R6=18432313718031039402, retaining prior AA/BB dirty bytes and full independent
source/memory comparison. Omitting the restore deliberately fails this new case
(`CONTROL_REGISTER,5,4,3,4096`), while the old late-read case still passes.

An independent audit compared all 351,624 ABI coordinates over the 13,524
controls, normalizing only pointer presence in words 5/7. All other values match
linked execution. It verified 513 runtime/native files (three changed in the
private prototype), eight repeated-build images, 64 raw process logs and 832
CPU records. Duplicate builds are byte-identical. Final integration adds the
production proof profiles and preserves measured-image flags; a separate
full-state DOOM control must certify actual resident execution before timings.

### Local timing screen and limits

All six matched groups are retained. The private harness used calls 1-12; an
independent audit also recomputed the CI-standard calls 3-12. These are median
paired candidate/baseline process CPU ratios, not group-median ratios:

| Workload | Calls 1-12 | Calls 3-12 | Interpretation |
| --- | ---: | ---: | --- |
| DOOM tick | 0.94665 | 0.947689 | All six pairs faster in both windows |
| DOOM init | 1.00186 | 1.002503 | Near flat/noisy |
| Sieve 10M | 0.99902 | 0.998704 | Near flat/noisy |
| Pinky | 1.00360 | 1.007153 | Small cost; all six slower in the original window |

Equal-source second/first ratios for baseline/candidate duplicates respectively
were tick 0.99367/1.02196, init 0.99813/1.04209, Sieve
0.99771/0.99819 and Pinky 0.99989/1.00786. DOOM's favorable paired direction
supports qualification, but the equal-source spread limits precision. No exact
5% shipping speedup or recovery of earlier costs is claimed from this screen.
Every process checks full CPU, mapped memory and DOOM events. Native semantic
work counters match; resident code occupancy is allowed to grow.

Evidence remains under the speed checkout's `build/pvm-resident-macro` and the
review checkout's `build/pvm-resident-final-audit`,
`build/pvm-resident-integrated-check` and `build/pvm-resident-app-check`.
Final Linux ARM qualification, matched PolkaVM-interpreted ratios, Tooling
and Smoke are recorded below. These are bounded guests, not full blockchain
throughput measurements.

The integrated local check also passes both native all-opcode and region/host
consumer suites. All 50 affected Python parser/controller/application tests and
the source-owned verification inventory pass. The new real-DOOM control executes
13 full-state checked calls with 8,462 resident macro entries, 1,667,243 semantic
cycle children and 1,658,781 completed reads, with zero read refusals. Its native
work/code occupancy exactly matches the measured ordinary image: 1,014 physical
fragments and 256,676 code bytes. Diagnostic macro receipt flags are confined to
this separate control; measured images retain the existing flag profile.

### Qualified Linux ARM result

Runtime head: `30c603f50367cb603b2395d6bd110cf426503a15`.
[ARM qualification/replay](https://github.com/jacogr/ragnarok/actions/runs/41432717048),
[Tooling](https://github.com/jacogr/ragnarok/actions/runs/41432328219) and
[Smoke](https://github.com/jacogr/ragnarok/actions/runs/41432225434) passed.
Tooling ran 1,655 tests (two skipped), plus inventory, lifecycle/mutant and
compiler-rejection controls. The first ARM dispatch was cancelled by the
same-ref workflow concurrency rule; its replacement used an isolated CI ref
at the identical runtime commit. It is not counted as a second successful run.

Artifact `13136271322`, ZIP SHA-256:
`1ebb2a9690df11c1d917e54c44f7a761be973abcb318c544ccd6ab0dc9d4cfef`.
Independent audits verify 2,575 role/519 native hashes, 84 primary and 60 replay
processes, 138 controls, 13 qualification rows, ten macro receipts, 18 image
equalities, 24 frozen fixtures, two owner moves and 320 raw-log matches.
The extra real-DOOM control verifies 515 source hashes and all 13 public calls.
Its resident receipt and native work/occupancy agree with the measured image.
All 44 paired comparisons retain semantic work; only tick code bytes grow
from 254,240 to 256,676, with unchanged physical fragment counts.

All qualified warm windows use calls 3-12, without exclusions. Group-median
changes are ratios of group medians of process warm CPU medians. Paired-median
changes are a separate estimator. Overlap refers to full process-median ranges.

| Six native replay pairs | Group-median change | Median paired change | Faster / slower | Ranges overlap |
| --- | ---: | ---: | ---: | --- |
| tick | -3.509280% | -3.620605% | 6 / 0 | no |
| init | +0.593798% | +0.349358% | 1 / 5 | yes |
| sieve | -4.382184% | -4.399773% | 6 / 0 | no |
| pinky | -0.171084% | -0.136043% | 5 / 1 | yes |
| minimal | +0.251364% | -0.320595% | 4 / 2 | yes |

DOOM tick and Sieve are consistently faster in all six pairs, with separated
ranges. Init has a small cost in five pairs with overlap. Pinky is near flat
with overlap. Minimal has four faster pairs but a slightly higher group median;
its ratio-of-means change is -0.090381%. All processes remain included. Sieve's
resident macro is inactive and its work/code occupancy is unchanged, so its
observed gain is not attributed specifically to macro activation.

Complete primary comparisons retain interpreter costs explicitly:

| Primary workload | Policy | Group-median change | Faster / slower | Ranges overlap |
| --- | --- | ---: | ---: | --- |
| init:0 | jit | +0.057242% | 1 / 1 | yes |
| init:0 | interpreter | -0.503918% | 2 / 0 | no |
| memset:100000 | jit | +0.091966% | 0 / 2 | yes |
| memset:100000 | interpreter | +0.392446% | 0 / 2 | yes |
| minimal:100000 | jit | +0.059486% | 1 / 1 | yes |
| minimal:100000 | interpreter | -1.165031% | 2 / 0 | no |
| pinky:1 | jit | -0.137488% | 1 / 1 | yes |
| pinky:1 | interpreter | -0.405866% | 2 / 0 | no |
| sieve:100000 | jit | -2.221092% | 2 / 0 | no |
| sieve:100000 | interpreter | +0.431002% | 0 / 2 | no |
| sieve:10000000 | jit | -4.165523% | 2 / 0 | no |
| sieve:10000000 | interpreter | +0.816185% | 0 / 2 | no |
| tick:0 | jit | -3.770983% | 2 / 0 | no |
| tick:0 | interpreter | +1.315658% | 0 / 2 | no |

The primary interpreter costs are tick +1.315658%, Sieve 10M +0.816185%
and Sieve 100K +0.431002%, each slower in both orders without range overlap.
Memset interpreter +0.392446% and native +0.091966% are slower in both orders
with overlap. These costs are retained; the change is not an all-policy gain.

Matched raw public-call CPU ratios against **interpreted PolkaVM**:

| Workload | Ragnarök JIT / PolkaVM interpreted | Ragnarök interpreted / PolkaVM interpreted |
| --- | ---: | ---: |
| tick | 0.393924 | 0.686828 |
| init | 0.225867 | 0.503545 |
| sieve | 0.770368 | 0.964926 |
| pinky | 0.906188 | 0.984972 |
| minimal | 0.957820 | 0.997385 |

Cold CPU entries below are medians [minimum, maximum] over all six processes,
in milliseconds. Constructor and first public call are separate. Compiler /
publication CPU is a cumulative diagnostic already included in calls; it is
not wall time, need not all occur in the first call, and is never added again.

| Workload / role | Owner constructor | First public call | Cumulative compiler/publication |
| --- | ---: | ---: | ---: |
| tick / baseline | 8.580772 [8.520488, 8.655992] | 27.685444 [27.559224, 28.663888] | 2.428172 [2.381440, 2.486952] |
| tick / jit | 8.528120 [8.443840, 8.563576] | 27.359544 [27.080528, 27.535664] | 2.423344 [2.392128, 2.445800] |
| init / baseline | 8.585780 [8.522216, 8.666848] | 163.227676 [162.344344, 163.748792] | 7.824324 [7.745144, 7.881232] |
| init / jit | 8.520496 [8.432816, 8.643024] | 163.685344 [162.366952, 164.456888] | 7.892040 [7.756448, 7.997448] |
| sieve / baseline | 2.941764 [2.822864, 3.219048] | 276.532520 [276.054664, 276.641008] | 3.162924 [3.104104, 3.348608] |
| sieve / jit | 2.895904 [2.854712, 3.132632] | 264.287368 [264.065360, 264.836888] | 3.153984 [3.090448, 3.252200] |
| pinky / baseline | 0.704504 [0.687256, 0.722520] | 84.220152 [84.081776, 84.369768] | 1.901228 [1.876160, 1.947160] |
| pinky / jit | 0.715192 [0.699952, 0.748424] | 84.081280 [83.862152, 84.310512] | 1.896520 [1.851912, 1.924920] |
| minimal / baseline | 0.019048 [0.016984, 0.020152] | 5.466124 [5.422616, 5.506664] | 0.096236 [0.092264, 0.103872] |
| minimal / jit | 0.016012 [0.014784, 0.018280] | 5.472760 [5.425248, 5.494760] | 0.099068 [0.094216, 0.147352] |

Root audit records: `build/pvm-resident-ci/audit.json` and `distributions.json`.
The independent reviewer record is `/tmp/review1897/final-cold-source-record.json`
(SHA-256 `1d2951e3f52201520842d79ec3287938e95608ffc03ebc937b621229062c6b63`).
Bounded guest results do not establish full blockchain throughput.

A separate local interpreted-only follow-up reused four verified final-screen
DOOM images without rebuilding. Six alternating pairs passed full CPU/pages/
events and strict interpreted policy, with every native owner counter zero.
Calls 3-12 ratios were 0.962962, 1.005104, 0.998246, 1.001428, 1.005143 and
1.017761 (median 1.003266, four slower); calls 1-12 median was 1.003737.
Equal-image 3-12 controls were 0.996764 baseline and 0.999824 candidate.
This bounded macOS follow-up does not consistently reproduce the Linux primary
+1.315658% magnitude and does not establish its cause. It does not replace or
negate that Linux cost. Records: speed checkout
`build/pvm-resident-interpreted-followup/results.json` and 16 raw logs.
The remaining interpreter cost is retained for the next ordered investigation.
