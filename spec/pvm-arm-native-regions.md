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

## Final default-path qualification

The production source enables the admitted graph in the regular ARM path. Copied Frame/stream/prepared activity diagnostics are guarded by pvmArmMacroReceipt; no Prototype behavior define is required. Runtime SHA256:

- arm64_jit.nim: `5cc2046b7d526c4308d7226ad1c0fb1891438cf22657ead093db51c54d058c82`
- handler_stream.nim: `4d3c7f0cd3f16eace31ade85cc563e5fc3cc5a63e60c7deaafbbcae9c9c5d586`
- step.nim: `1e4ee7636d575e5583bfb3be3954d27395b1c0858c26b3158d64f3a06e6d6f5f`

The complete 12-row maintained ARM qualification and plain witness pass on this runtime, including normal, native-storage refusal, macro append refusal, all-opcodes, host and four ownership orders. The final controller additionally skips the native-only macro append-refusal build on checked-only hosts; that controller-only correction leaves the qualified ARM command matrix and every compiled source unchanged. All six new mandatory receipts have paired native/refused/plain positives and independent missing/truncated/duplicate negatives; the Python suite passes 19 tests.

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

Cold CPU diagnostics below retain every group. Values are milliseconds in min / median / mean / max order. Compilation is process CPU already included in the relevant first call; it is not added again.

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
