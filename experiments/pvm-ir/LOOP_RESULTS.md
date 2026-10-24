# Real guest-loop follow-up — 2026-10-23

The subsequent [bounded memory/host experiment](EFFECT_RESULTS.md) checks broader effects
and records regressions that qualify this arithmetic-heavy result.

Preparing actual PVM operands preserves a measurable benefit through full execution,
but it is much smaller than the earlier arithmetic-kernel results. Keep this as an
experiment: this evidence does not yet justify production integration.

The 64-operation loop at 10,000 iterations improves from about 15.28 ms CPU time per
invocation to 10.48 ms including preparation (1.46× throughput; about 31% less CPU time).
The 16-operation loop improves about 8–9% in throughput. The tiny repeated loop is tied.
For one-iteration calls, preparation-inclusive medians are slightly slower, mostly
within a few percent: no one-shot speedup is established. Reused preparation helps
some short calls modestly; it is not a benefit that all callers receive.

The decoder cache is the only execution strategy replaced. The generated module uses
production register evaluation, branch validation, gas simulation/cache, instruction
budgets, exact exits and snapshot publication. Its cache parameter is read-only; an
initial per-call ARC sequence copy was found in generated C and removed. Final C
inspection confirms no decoded-table allocation/copy in the prepared entry wrapper.
The pre-borrow exploratory measurements are retained locally under
`build/pvm-ir-experiment/loop-before-borrow/`.

The lookup deliberately uses one full decoded-result slot per guest **byte PC**, so
operand bytes occupy unused slots. It costs 1,088 / 3,776 / 12,992 payload bytes for
2 / 16 / 64 arithmetic body operations, excluding sequence and source-snapshot owners.
This is a simple benchmark layout, not the proposed production representation.
Prepared plans are bound to one immutable input snapshot. Sharing across different
register/memory inputs is outside this increment.

Verification uses an independent fixed-program oracle for arithmetic, branch/exit,
charge timing, balances, PCs and the charged flag. Pipeline prices and minimum accepted
simulation limits come from the existing production gas module; pricing itself is not
independently reimplemented here. Each process checks 7,203 scenarios against both
engines (14,406 engine/oracle comparisons), plus absent-owner controls. The matrix covers:

- Uncharged/prepaid entry, zero/insufficient/exact gas, including insufficient gas at halt.
- Zero/exact/one-short/extra attempted-instruction budgets and gas simulation ceilings.
- Interior instruction entry, operand-byte and out-of-range PCs, taken and untaken invalid targets.
- All thirteen registers, gas, deficit, PC, blockCharged and exact exit/error reason.
- Original input CPU snapshots retained across every execution; input memory is empty.

Every timed invocation result is checked outside both clocks. Each engine/case has
three warmups and ten measured samples in each of two processes, with rotated order.
Baseline and candidate retain identical output batches during timing; output validation
and destruction are outside timing. The cold candidate includes preparation/table
disposal; both exclude common validated program and input-machine construction.
Checks, formatting, Python syntax, assertion sentinel and measured-source hashes pass.
No host calls or memory faults are exercised. This is local macOS ARM64 evidence only.

Independent-process throughput ratios on the repeated loop:

| Process | Arithmetic body operations | Reused vs production | Preparation-inclusive vs production |
| --- | --- | ---: | ---: |
| 1 | 2 | 0.989× | 0.984× |
| 1 | 16 | 1.070× | 1.081× |
| 1 | 64 | 1.461× | 1.465× |
| 2 | 2 | 0.991× | 0.999× |
| 2 | 16 | 1.086× | 1.087× |
| 2 | 64 | 1.455× | 1.457× |

Measured starting HEAD: `9718453cfa43fc881bf656cb2e2f7fe5b6ddb69d`. The evidence JSON records all actual working-tree
source hashes, generated overlay identity, compiler flags, compiler/Clang versions and
binary SHA-256 `02b987013e289b45a82cae6ac2f9519b264c491d56fc9b292c1555b41cea65b9`. No production sources or dependency pins changed.

Reproduce with the pinned compiler:

```sh
NIMONY=/absolute/path/to/pinned/nimony make -C experiments/pvm-ir loop
```

See [loop_probe.nim](loop_probe.nim), [prepare_overlay.py](prepare_overlay.py), and
[run_loop.py](run_loop.py). The generated module, exact production diff, raw CPU/wall
samples, source identities and compiler diagnostics live under
`build/pvm-ir-experiment/`. These ignored artifacts are removed by `make clean`.
The generator edits only exact source anchors and preserves the semantic bodies.

Next useful increment would exercise memory faults and host suspension/reentry with a
bounded, reusable program-owned table before considering production adoption. No native
compiler or specialized arithmetic evaluator was added in this follow-up.

---

# Real guest-loop comparison

Apple M1 Max; checked Nimony ARC / Clang ThinLTO. Twenty samples per case.

| Body operations | Guest iterations | Engine | CPU µs/invocation (range) | vs production |
| --- | --- | --- | ---: | ---: |
| 2 | 1 | production execute | 0.63 (0.62–0.67) | 1.00× |
| 2 | 1 | prepared reused | 0.58 (0.57–0.63) | 1.09× |
| 2 | 1 | prepare + execute | 0.65 (0.64–0.94) | 0.97× |
| 2 | 10000 | production execute | 721.17 (698.00–748.33) | 1.00× |
| 2 | 10000 | prepared reused | 721.00 (699.67–744.67) | 1.00× |
| 2 | 10000 | prepare + execute | 725.17 (697.67–760.33) | 0.99× |
| 16 | 1 | production execute | 2.81 (2.73–2.95) | 1.00× |
| 16 | 1 | prepared reused | 2.66 (2.56–2.76) | 1.06× |
| 16 | 1 | prepare + execute | 2.87 (2.81–2.99) | 0.98× |
| 16 | 10000 | production execute | 3300.17 (3202.00–3426.67) | 1.00× |
| 16 | 10000 | prepared reused | 3055.83 (2935.33–3142.00) | 1.08× |
| 16 | 10000 | prepare + execute | 3040.00 (2953.00–3434.00) | 1.09× |
| 64 | 1 | production execute | 26.08 (25.59–28.14) | 1.00× |
| 64 | 1 | prepared reused | 25.42 (25.09–27.84) | 1.03× |
| 64 | 1 | prepare + execute | 26.44 (26.11–30.59) | 0.99× |
| 64 | 10000 | production execute | 15276.83 (15174.33–15525.00) | 1.00× |
| 64 | 10000 | prepared reused | 10513.50 (10327.33–10825.00) | 1.45× |
| 64 | 10000 | prepare + execute | 10479.33 (10305.67–10830.67) | 1.46× |

Decoded table payload bytes by body length: {2: 1088, 16: 3776, 64: 12992}

7,203 oracle scenarios per process compare both engines: 14,406 engine/oracle checks.
Each timed result is validated after both clocks stop. Two separate measurement processes.

Prepared source is a generated copy of production step.nim with a replaced decoder cache.
Gas, control, register evaluation and publication bodies are shared verbatim; cache is borrowed read-only.
Only add/xor/counter/branch/halt and empty memory are exercised.
No memory faults, host calls, arbitrary programs or Linux validation.
Dense byte-PC indexing spends memory on operand bytes; not a proposed final layout.
Preparation is bound to one immutable source snapshot, not shared across distinct inputs.
CPU clocks reduce scheduling noise but not frequency/cache contention.
