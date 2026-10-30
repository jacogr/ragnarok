<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# ARM candidate-local region refusal

## Scope

The review of production `5dace79e92997f596fb3841857a33587138be42c` traced an optimization
coverage defect: `publishArmRegion` sets its owner-wide refused status before checking a
candidate's shape or source span. A rejected candidate can therefore prevent an unrelated
eligible loop in the same prepared owner from becoming a region. Checked execution and ordinary
native leaves remain available. This is not a demonstrated wrong guest result.

The intended policy matches the existing x86 boundary: candidate-local shape, span or generated
image-size failure preserves availability; genuine owner-wide executable-storage/publication
failure remains sticky. The existing one-region policy, eight discovery visits per header,
4,095-instruction regional span, 1,024-word image, publication reservation and physical arena
limits must not increase. Source/PC, attempts, gas, aliases, snapshots and refusal fallback stay
unchanged. No memory/checkpoint, canonical-IR, dependency-pin or production API change belongs here.

## Discriminating witness

`test_pvm_arm_region_refusal` has a two-block loop whose first block contains 4,096 folded
`unlikely` markers and four additions. Its source span is 4,101 instructions, while its emitted
operations fit the ordinary native prefix. A separate small two-block loop follows at byte PC4,132.
Fresh-small, rejected-then-small and small-then-rejected owners must all execute an actual region
on supported native ARM64. Forced OS refusal and unsupported hosts must claim no native work.

Expected values do not come from another prepared execution. The pinned Gray Paper gas-table
reference gives block prices 5,528 /4 /21 /2 /2 at byte PCs0 /4,114 /4,132 /4,141 /4,150.
The long-loop prefix consumes exactly 82,120 attempts over20 rounds, sets R0=R2=80, leaves
9,889,360 gas from10,000,000, and stops at unpaid PC0. The small loop consumes13 attempts,
sets only R0=6, leaves9,999,929 gas and reaches the paid panic endpoint. Every register, gas deficit,
PC/paid flag and remaining attempt participates. A nonzero4KiB writable page and independently
retained snapshots must preserve every byte and permission across later calls.

The independent Python pipeline reference used for these literals is unchanged. The retained
derivation prunes only fully retired prefix entries with dependency-index remapping, cross-checks
exact prices/cycles against the original on50 smaller cases across32-entry window boundaries,
then evaluates the long literal source with all following bytes available for branch pricing.
No oracle prices are supplied to production execution.

Additional controls cover local shape/span/terminal/generated-word declines, exactly eight probe visits,
stable exhausted negative compilation, real publication-count/physical-byte exhaustion and
ordinary entries surviving global refusal. The test-only native receipt define records genuine
per-order region calls/blocks and ordinary native calls; missing/reordered/zero native receipts
fail native-host qualification. No exported runtime observation API is added.

## Execution and status

Local work is limited to source/inert tests and pinned semantic checks. Native compilation,
linking and execution are CI-only. `workflow_dispatch` scope `jit-arm-check` reuses the existing
ARM comparison job and complete `make check-pvm-native` gate without requesting application
timing, profiling or calibration. Other modes/defaults and the60-minute limit are unchanged.
The two regression executables and complete logs are retained even when qualification fails.

Baseline native reproduction: run41051261233 at `dcbd1ce59ff3c48ef874101bd7e6c870237844fb`,
with production sources byte-identical to5dace. Fresh owner executes2region calls/10blocks;
rejected-large then small executes0regions despite138ordinary native calls; small-first preserves
coverage, increasing2to5region calls/28blocks. Both orders and all literal state/storage/probe
controls pass before the intended candidate-local availability assertion. The focused manual mode
selects only native correctness; the ordinary PR Smoke remains a separate required gate.

The fix moves only the sticky-refusal assignment to the genuine publication boundary, matching
existing x86 policy. Fixed exact-head native confirmation and focused PR review remain pending.
This establishes an optimization-coverage defect, not a wrong guest result or a measured speedup.
