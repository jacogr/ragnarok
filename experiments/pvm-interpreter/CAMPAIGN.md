# Interpreter campaign, 26–27 October 2026

Local macOS arm64 investigation on `codex/pvm-interpreter-lab`. The starting checkpoint is
`72c79e4d36ae9b51f5d3f971477f0bb4b144df7d`; the final runtime is the accepted store-splice
model at `80350f56`, with later commits preserving rejection evidence and more accounting
witnesses. Production source, default selection, CI and dependency pins remain unchanged.
No PR or merge is part of this campaign.

## Direct cumulative comparison

The final table is populated only from the fresh `cumulative-final` cohort. Incremental trial
percentages must not be multiplied. Frozen master denotes the existing sealed local image,
not a freshly retrieved master build. Reference constructor and publication equivalents are
unavailable, so comparisons to PolkaVM are calls only.

[Complete paired report](findings/cumulative-final.md) and
[all parsed samples](findings/cumulative-final.json), with [exact source, compiler, fixture and image seals](findings/cumulative-provenance.json). CPU milliseconds, forward/reverse;
reused calls exclude the same first three of thirteen fully checked calls in both roles.

| Workload | Starting checkpoint | Final | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 86.466 / 86.162 | 83.317 / 83.084 | 118.775 / 118.883 | 91.922 / 92.719 | 0.906x / 0.896x |
| sieve | 3.174 / 3.248 | 3.171 / 3.206 | 3.330 / 3.329 | 5.707 / 5.710 | 0.556x / 0.561x |
| minimal | 5.117 / 5.139 | 4.841 / 5.040 | 7.261 / 7.294 | 5.853 / 5.892 | 0.827x / 0.855x |
| memset | 3.683 / 3.724 | 3.685 / 3.682 | 3.389 / 3.452 | 3.825 / 3.807 | 0.963x / 0.967x |
| init | 715.740 / 714.832 | 316.216 / 316.417 | 1323.540 / 1310.331 | 655.713 / 652.946 | 0.482x / 0.485x |
| tick | 28.576 / 28.672 | 27.680 / 27.641 | 83.731 / 83.962 | 34.106 / 33.589 | 0.812x / 0.823x |

The six-pair median call changes against the starting checkpoint are Pinky −3.64%, sieve
−1.84%, Minimal −6.22%, memory fill −0.53%, DOOM initialization −56.03% and gameplay −3.10%.
Gameplay lifecycle improves about 22.6%, including reset and full final publication. All
four small-workload medians improve, but memory fill remains slower than frozen master and
Pinky/memory fill do not meet the 0.85× reference CPU-duration target. Minimal straddles that
target in the displayed orders. These are CPU-duration ratios, not throughput ratios.

Cold first use includes plan/frame construction, reset, one call and publication. Initialization
falls from 790.858/779.107 ms to 367.599/356.897 ms; gameplay from 87.799/88.198 ms to
64.479/65.202 ms. These exclude fixture I/O, decoding/validation and final destruction.
Representative frame construction falls from about 27 ms to 14 ms and reset from about
20 ms to 10 ms. Full constructor and host-phase tables remain in the detailed report.

All 200 timed processes and four negative controls pass with stable source/fixture/image
seals. DOOM source attempts and host calls remain exactly 203,298,231/1,621 for initialization
and 12,180,040/1 for gameplay. These are guest source attempts, not native instruction counts.
The starting checkpoint has a source-quota issue fixed during the campaign; the fully completed
timed programs do not trigger its deficient partial-execution path. Dedicated witnesses cover
the correction separately. No claim of general correctness for that old checkpoint is made.

## What changed

| Retained change | Evidence and reason |
| --- | --- |
| Checked bulk page construction | [bulk page copy](findings/bulk-page-construction.md): constructor/reset work falls; all region and permission checks remain |
| Immutable page identity in host preflight | [shared page validation](findings/shared-page-validation.md): skip unchanged owners while preserving complete two-pass validation |
| Active-stream source quota barrier | [quota witness](findings/active-stream-barrier.md): correctness fix when a cached suffix has a different physical stream; preserve exact attempted prefixes |
| Binary search in sparse host refresh | [host refresh](findings/binary-checkpoint.md): locate changed pages without scanning unrelated source images |
| Observed register/branch composition | [register branch](findings/register-branch.md): retain independent entries and partial-quota boundaries |
| Expanded checked register reservation | [charged templates](findings/charged-expanded.md): eliminate composed helper calls without weakening gas or source-budget checks |
| Guarded concrete block cycles | [fixed coordinates](findings/fixed-expanded.md): learn exact immutable record coordinates and recheck actual edges; ordinary dispatch handles divergence |
| Exact snapshot capacity | [page capacity](findings/exact-page-capacity.md): avoid repeated page-sized growth/copies; complete owned snapshot remains required |
| Checked store expansion | [store splice](findings/store-splice.md): splice existing checked fast path into its callers; slow fallback unchanged |

The cycle change is the largest result. A count-only trace identified a three-block register
cycle in DOOM initialization. After a real first round resolves valid branch targets, subsequent
rounds reuse exact concrete coordinates. Each logical block still charges gas, checks the source
quota and preserves its source PCs. Each branch edge must match before the next remembered
record is read. Changing paths leave the loop through ordinary dispatch. This is a native loop
inside the interpreter, with bounded native stack use; it emits no native guest code.

The separate [dynamic-coordinate control](findings/dynamic-predicate-control.md) retained the
same comparison expansion but removed concrete coordinate retention. Its initialization cost
rose about 93% against the accepted model. This supports the design choice; it does not identify
a particular hardware cause. Static disassembly facts are distinguished from executed native
instructions and hardware counters throughout the evidence.

## Rejected experiments and costs

Rare-exit outlining, unpaid-entry specialization, a dirty-publication directory, composed
charged workers, dynamic cycle coordinates, checked-load expansion and source-count
specialization were rejected. Their measured results and useful witnesses remain under
`findings/`; their runtime changes do not. [Investigation log](AUTONOMOUS.md) records parents,
controls, regressions and decisions in order.

The retained checked-store expansion increases the three driver text sections by 10,560 bytes
each. Its isolated memory-fill median regressed 0.61% while Pinky, Minimal and both DOOM phases
improved. The early combined register/branch trial also had a cold gameplay lifecycle tradeoff.
The final cumulative cohort, rather than those isolated observations, determines the combined
result. All declared timing pairs are retained, including busy observations and slower pairs.

Exact page-image capacity reduced separate complete-process peak RSS from 270.23–270.36 MiB
to 232.08–232.20 MiB in eight probes of its isolated trial. Those figures include fixtures,
validation and every process owner; they are not engine-only allocations. Probe clocks were
excluded from CPU comparisons. No cumulative peak-RSS claim is inferred from that trial.

## Qualification and remaining gates

Accepted runtime changes passed all eight native and AddressSanitizer witness groups, including
139 opcodes, ARC lifetime, gas/source quotas, checked memory, exact exit state, host reentry and
immutable publication. Subsequent truth-table and interior-entry witnesses passed separately
on the accepted runtime. Every timed call compares complete reference state and source snapshots;
DOOM also checks output and host counts. Fresh private-cache repeats at equal source/output
coordinates produce equal images for both roles and three drivers. Source/fixture/image seals,
negative controls and process-load snapshots are retained locally. Eight pure harness tests and
pinned source formatting are additional checks, not substitutes for native state validation.

This remains an architectural experiment. Dense input-sized maps and a monotone stream need a
bounded admission/resource policy; constructor assertions need the production typed-error
contract. Backend integration, tracing, production API ownership and fresh current-master,
Linux/x86-64 qualification remain open. The benchmark fixtures and frozen reference images
still depend on the preserved local laboratory, so a clean-checkout measurement recipe is also
required before a production PR.

The next substantial design question is memory-bearing block execution: retain stable decoded
facts while keeping checked address/permission state explicit. The smaller branch-only variants
cover relatively little of Pinky. Avoid weakening checks or assuming unsupported alias contracts.
Review this direction with the measured campaign results before another runtime experiment.

## Evidence storage

Structured findings preserve every parsed timing, phase, count and observation. Numeric rows
and small records are compacted without changing numeric/bool/null values at any JSON path.
Duplicate full command output is represented by a hash and bounded excerpt; byte-exact original
JSON files remain under ignored `build/pvm-interpreter-experiment/evidence-originals/`.
[Compaction manifest](findings/compaction-manifest.json) binds originals to their compact forms;
[cleanup script](findings/compact-evidence.py.txt) records the equality checks. Existing raw-report
hashes continue to identify the untouched ignored comparison reports. A local log hash is added
only if its current bytes still match the original output, avoiding overwritten-log ambiguity.
