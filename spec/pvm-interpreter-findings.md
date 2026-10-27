# Interpreter investigation: retained findings and provenance

## Current implementation and checks

The single production engine is `src/pvm/internal/handler_stream.nim`; its public adapters,
resource policies and qualification boundaries are recorded in [the contract](pvm-handler-stream.md).
Ten `test_pvm_stream_*` groups run through ordinary native discovery and the calibrated sanitizer
runner. Their former standalone copies, snapshot overlay and duplicate check runner are retired.

The maintained detailed comparison is `make bench-pvm-interpreter`, implemented in
`tools/pvm_interpreter_compare.py` with the two `tests/performance/pvm_stream_*.nim` drivers.
It compares exact master, our core and pinned PolkaVM interpreted in both process orders, validates
complete state and refusal controls, repeats fresh private-cache builds and retains every sample.
Constructors, cold/reused calls, reset and publication are separate. It runs only on explicit Linux
comparison requests. Ordinary PVM/DOOM performance jobs measure public API calls separately.

## Retained design findings

- The accepted model uses a lazy flat handler stream with sealed operands, bounded source/fact/node
  admission, source-attempt budgets, exact exit PCs and whole-block pricing. Checked memory and
  immutable observations remain mandatory; the internal execution representation is private.
- Checked contiguous regions, bulk page construction, immutable page identity and sparse dirty
  publication reduce construction/reset/host-boundary work. Register and target specializations
  were accepted only with paired measurements and complete state checks.
- Reduced static work alone did not reliably improve CPU time. Rare-exit outlining and paid/unpaid
  entry splitting were rejected after measured regressions or noise. Keep their original evidence
  when reconsidering those hypotheses; do not repeat their claims as accepted optimizations.
- Complete versus lazy preparation, private-frame reuse and immutable public API execution have
  different costs. Large initialization workloads and host-heavy applications must be measured
  alongside small loops, with preparation and publication visible.

## Historical local checkpoint

These are macOS ARM64 call-only measurements from the final local campaign, not current public API
or Linux results. Each cell preserves forward/reverse CPU milliseconds. Master is a frozen existing
prepared-interpreter image, not a fresh build of current master. Reference-equivalent reset,
constructor and publication timings were unavailable.

| Workload | Candidate core | Frozen master | PolkaVM interpreted | Candidate / PolkaVM |
| --- | ---: | ---: | ---: | ---: |
| Pinky | 83.317 / 83.084 | 118.775 / 118.883 | 91.922 / 92.719 | 0.906 / 0.896 |
| sieve | 3.171 / 3.206 | 3.330 / 3.329 | 5.707 / 5.710 | 0.556 / 0.561 |
| minimal | 4.841 / 5.040 | 7.261 / 7.294 | 5.853 / 5.892 | 0.827 / 0.855 |
| memory fill | 3.685 / 3.682 | 3.389 / 3.452 | 3.825 / 3.807 | 0.963 / 0.967 |
| DOOM initialization | 316.216 / 316.417 | 1323.540 / 1310.331 | 655.713 / 652.946 | 0.482 / 0.485 |
| DOOM gameplay | 27.680 / 27.641 | 83.731 / 83.962 | 34.106 / 33.589 | 0.812 / 0.823 |

The cumulative campaign retained 200 timed processes and four negative controls. Compared with
its starting checkpoint, reused DOOM initialization improved about 56% and gameplay calls about
3%; gameplay lifecycle improved about 22.6%. Complete CPU/gas/memory/permissions/source snapshots
and host events were checked. Process-load observations are not proof of uninterrupted idleness;
no individual outlier was dropped. Counts of source attempts are not native instructions.

The compared starting commit was `72c79e4d36ae9b51f5d3f971477f0bb4b144df7d`.
Candidate runtime SHA-256: `33b3b3baa63cdd981c5065e43d37877a4876fb2ef05f430b02398a744ca84935`.
Candidate memory SHA-256: `70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`.
Compiler revision: `4724f66c2e01b17810c844f26575b2317995fda2`.
Reference revision: `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`.

## Qualified Linux core checkpoint

[Run 40452151944](https://github.com/jacogr/ragnarok/actions/runs/40452151944) at
`e1bccc7372b284868d50b3ba1e6461f5fcb91969` compared exact master
`5de8efcb0a1bcd16dcc5bc596b56c6dedd691bf0` on AMD EPYC 7763. All 36 processes / 468 checked calls,
54 controls, eight repeat builds and six independent DOOM admission controls passed. The complete
CPU tables, constructor/cold/lifecycle scopes and source/image hashes are linked from
[the qualified report](https://github.com/jacogr/ragnarok/pull/1720#issuecomment-6434232839).
It found substantial master improvements but no uniform lead over PolkaVM: gameplay calls were
6–11% slower and minimal 4–8% slower. The ARM64 results did not generalize uniformly to x86-64.
These are core retained-frame measurements, not integrated production API timings.

## Recovering the full investigation

The removed lab is preserved at exact commit `b7d566be4966b2288028fd56619498ac0a8c0a42`,
with Git tree `d7908935f0945750297171d67c3e490cada6b8b5` for `experiments/pvm-interpreter`.
Use `git show <commit>:experiments/pvm-interpreter/<path>` without changing the working tree.
Permanent records include the
[full cumulative report](https://github.com/jacogr/ragnarok/blob/b7d566be4966b2288028fd56619498ac0a8c0a42/experiments/pvm-interpreter/findings/cumulative-final.md),
[all samples and phases](https://github.com/jacogr/ragnarok/blob/b7d566be4966b2288028fd56619498ac0a8c0a42/experiments/pvm-interpreter/findings/cumulative-final.json),
[campaign decisions](https://github.com/jacogr/ragnarok/blob/b7d566be4966b2288028fd56619498ac0a8c0a42/experiments/pvm-interpreter/AUTONOMOUS.md) and
[original source provenance](https://github.com/jacogr/ragnarok/blob/b7d566be4966b2288028fd56619498ac0a8c0a42/experiments/pvm-interpreter/provenance.json).
This preserves accepted and rejected evidence without keeping the full lab in the production tree.
