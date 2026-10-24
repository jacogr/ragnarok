# Shared preparation with memory and host effects — 2026-10-23

The bounded, program-owned table preserves the tested memory/host behavior across
reentry and different invocation inputs. It is not a universal performance improvement.
On the selected small memory/host loops at 1,000 iterations, preparation-inclusive
CPU time is about 5–8% worse than production. The host loop with 32 extra arithmetic
operations improves about 5% in throughput. Both independent processes agree on the
direction; the full spread and process-specific medians remain visible below.
One-shot preparation-inclusive calls show no established speedup.

These results qualify the earlier arithmetic-only full-execution gain in
[LOOP_RESULTS.md](LOOP_RESULTS.md). They support investigating selective preparation
for reused, decoder-heavy programs. Do not replace the current cache universally or
extrapolate a complete JAM performance gain from these synthetic loops.

## Representation and ownership

The generated `shared_step.nim` retains the production gas, memory, register, control,
host-response and response-only scheduler bodies. Only cache storage/lookup and its
read-only binding are changed. A private immutable table retains the validated Program
owner, decoded records and a uint16 byte-PC index. Entries hold no gas, registers,
memory, callback context or machine snapshot. Entry APIs accept fresh CPU/memory state;
the table supplies the program, preventing a detached table/source-program mismatch.

Preparation has typed invalid-program/byte-limit/instruction-limit refusals and no
partial executable result. Hard caps are 4,096 code bytes and 256 instructions, even
when larger caller limits are supplied. Limits are checked before allocating beyond
their budgets. The maximum payload is 24 KiB (8 KiB index plus 16 KiB decoded records),
excluding metadata/allocator overhead and the already-owned validated program blob.
This is a payload bound, not a process RSS measurement or total guest-memory ceiling.

| Code bytes | Decoded payload | Equivalent previous dense payload | Reduction |
| ---: | ---: | ---: | ---: |
| 18 | 420 B | 1,152 B | 64% |
| 20 | 488 B | 1,280 B | 62% |
| 116 | 2,728 B | 7,424 B | 63% |

The ordinary production memo is a transient 16-entry cache; these program tables have
persistent ownership and different lookup costs. Reduced payload versus the earlier
dense representation does not imply lower RSS or faster execution than production.
Generated C inspection found no table allocation/copy in the shared execution wrapper.

## Checked behavior

Each of two measurement processes checks 1,685 logical cases. This is a combination
of differential cases and independent state/refusal witnesses, not 1,685 independent
reimplementations of all PVM semantics:

- 11 preparation/default/maximum-capacity cases. The largest accepted table executes
  all 256 instructions, exercising the uint16 index value 256 and exactly 4,096 bytes.
- 874 memory/charging/budget cases: aligned and crossing loads/stores, absent/read-only/
  inaccessible pages, protected low memory, zero/exact/short budgets, complete page
  images/permissions and fault pages, atomic failed stores, repair/retry and zero-cycle
  prepaid retries. Retained original and fault snapshots remain unchanged after repair.
- 784 host-scheduler/program-lifetime cases: callback limits, instruction/gas ceilings,
  Continue/Panic/OutOfGas, rejected Halt/default/bad-memory/debt responses, valid host
  memory replacement, different programs with identical PCs and distinct immediates,
  varied registers/memory inputs, revisiting owners and execution after the original
  local Program handle retires.
- 16 direct suspension/application/reentry cases: exact host identifier, causing PC,
  gas, charged flag, registers, supplied memory, terminal states and refused responses.

The full automatic host loop preserves one instruction/callback budget and its price
memo across replies. A fault retry starts a new bounded execution with its existing
prepaid-block flag; it must not charge the paid block again. Pipeline prices are still
computed by production `blockGas`; this probe does not independently validate pricing.
Independent successful-state witnesses derive register/scalar/gas expectations from
fixture construction and compare every byte/permission in both fixture pages.

Checked release ARC/Clang ThinLTO remains enabled throughout. AddressSanitizer also
passed all 1,685 cases and all workload-result assertions in a separate build
(300 recorded samples plus warmups).
Its timings are discarded; it is not a leak or general ownership proof. The deliberate
assertion sentinel, pinned formatting, Python syntax, source identities and whitespace
checks pass. Results are local Apple M1 Max/macOS ARM64 only. Typed fallible host
callbacks, other memory widths, arbitrary programs and Linux remain outside scope.

## Measurement

Five scenarios contain a real read/modify/write guest loop, with optional host
suspension and 32 additional arithmetic operations. Each runs for 1 and 1,000 iterations.
Three modes compare production, reused program preparation and preparation paid on
every invocation. Both include equal input-snapshot construction and result
normalization. Full result validation and retained-output disposal happen outside
both clocks. CPU and elapsed samples, rotated order, three warmups and ten measured
samples per engine/case/process are retained. CPU clocks reduce scheduling noise but
do not remove frequency or cache contention.

Independent-process throughput ratios for 1,000 iterations:

| Process | Scenario | Reused vs production | Preparation-inclusive vs production |
| --- | --- | ---: | ---: |
| 1 | memory aligned | 0.925× | 0.918× |
| 1 | memory crossing | 0.954× | 0.951× |
| 1 | host aligned | 0.906× | 0.909× |
| 1 | host crossing | 0.938× | 0.948× |
| 1 | host + 32 arithmetic | 1.067× | 1.057× |
| 2 | memory aligned | 0.941× | 0.940× |
| 2 | memory crossing | 0.948× | 0.947× |
| 2 | host aligned | 0.919× | 0.926× |
| 2 | host crossing | 0.940× | 0.967× |
| 2 | host + 32 arithmetic | 1.063× | 1.035× |

Measured starting HEAD: `efb377c2c18233390f8a19d4464d8f7e34b82eca`. Actual working-tree source hashes and compiler/
Clang versions are recorded in `build/pvm-ir-experiment/effects-results.json`.
Uninstrumented binary SHA-256: `d2fa6d7d82ee55d8e68362fb2d59606dc3bee5116b70f8c79b088e65f38b3143`.
AddressSanitizer binary SHA-256: `d24140e22984864575cf05b97245848b0f073d777b0ad196841a2016a8ffc1b7`.

Reproduce with the repository-pinned compiler:

```sh
NIMONY=/absolute/path/to/pinned/nimony make -C experiments/pvm-ir effects
NIMONY=/absolute/path/to/pinned/nimony make -C experiments/pvm-ir effects-asan
```

See [effect_probe.nim](effect_probe.nim), [shared_api.nim.inc](shared_api.nim.inc),
[prepare_shared.py](prepare_shared.py), [run_effects.py](run_effects.py) and
[check_effects_asan.py](check_effects_asan.py). The exact production diff, generated
module, raw samples and compiler/sanitizer logs remain under ignored
`build/pvm-ir-experiment/`, removed by `make clean`.

A useful next decision requires representative PVM programs and profiling their
actual decode/cache costs. This prototype remains opt-in; no production dispatch
policy, native backend, specification interpretation or dependency pin is changed.

---

# Memory and host execution with shared preparation

Apple M1 Max; checked Nimony ARC / Clang ThinLTO. Twenty samples per case.

| Scenario | Guest iterations | Engine | CPU µs/invocation (range) | vs production |
| --- | --- | --- | ---: | ---: |
| memory aligned | 1 | production execute | 1.67 (1.64–2.03) | 1.00× |
| memory aligned | 1 | prepared reused | 1.71 (1.61–2.01) | 0.98× |
| memory aligned | 1 | prepare + execute | 1.84 (1.71–2.14) | 0.91× |
| memory aligned | 1000 | production execute | 314.25 (307.50–330.50) | 1.00× |
| memory aligned | 1000 | prepared reused | 335.50 (327.50–349.00) | 0.94× |
| memory aligned | 1000 | prepare + execute | 336.75 (329.00–362.50) | 0.93× |
| memory crossing | 1 | production execute | 1.94 (1.84–2.31) | 1.00× |
| memory crossing | 1 | prepared reused | 1.89 (1.81–2.06) | 1.03× |
| memory crossing | 1 | prepare + execute | 1.99 (1.92–2.47) | 0.97× |
| memory crossing | 1000 | production execute | 467.75 (447.00–503.00) | 1.00× |
| memory crossing | 1000 | prepared reused | 492.50 (474.50–516.50) | 0.95× |
| memory crossing | 1000 | prepare + execute | 493.00 (467.50–508.50) | 0.95× |
| host aligned | 1 | production execute | 2.42 (2.35–3.41) | 1.00× |
| host aligned | 1 | prepared reused | 2.38 (2.32–2.94) | 1.01× |
| host aligned | 1 | prepare + execute | 2.52 (2.46–2.82) | 0.96× |
| host aligned | 1000 | production execute | 407.50 (399.50–439.50) | 1.00× |
| host aligned | 1000 | prepared reused | 445.00 (428.50–465.50) | 0.92× |
| host aligned | 1000 | prepare + execute | 441.00 (429.50–467.00) | 0.92× |
| host crossing | 1 | production execute | 2.65 (2.58–3.70) | 1.00× |
| host crossing | 1 | prepared reused | 2.62 (2.55–3.11) | 1.01× |
| host crossing | 1 | prepare + execute | 2.71 (2.67–3.39) | 0.98× |
| host crossing | 1000 | production execute | 568.25 (557.00–637.50) | 1.00× |
| host crossing | 1000 | prepared reused | 614.75 (589.00–642.00) | 0.92× |
| host crossing | 1000 | prepare + execute | 598.25 (585.50–627.00) | 0.95× |
| host + 32 arithmetic | 1 | production execute | 9.21 (8.83–9.75) | 1.00× |
| host + 32 arithmetic | 1 | prepared reused | 8.95 (8.74–11.31) | 1.03× |
| host + 32 arithmetic | 1 | prepare + execute | 9.79 (9.34–10.29) | 0.94× |
| host + 32 arithmetic | 1000 | production execute | 1167.00 (1150.50–1211.00) | 1.00× |
| host + 32 arithmetic | 1000 | prepared reused | 1099.25 (1083.00–1140.00) | 1.06× |
| host + 32 arithmetic | 1000 | prepare + execute | 1114.25 (1092.00–1153.00) | 1.05× |

Code and decoded-table payload bytes by scenario: {0: {'code_bytes': 18, 'payload_bytes': 420}, 1: {'code_bytes': 18, 'payload_bytes': 420}, 2: {'code_bytes': 20, 'payload_bytes': 488}, 3: {'code_bytes': 20, 'payload_bytes': 488}, 4: {'code_bytes': 116, 'payload_bytes': 2728}}

1,685 checked cases per process: differentials, independent state witnesses and preparation refusals.
Each timed result is validated after both clocks stop. Two separate measurement processes.

Program-owned table; bounded to 4096 code bytes and 256 decoded records.
The table supplies program identity; CPU and memory are supplied afresh for each invocation.
Production gas, memory, host response and scheduler bodies are preserved.
Only 64-bit scalar memory operations and the response-only host scheduler are exercised.
Typed host callback failures, arbitrary guest programs and Linux remain untested.
Payload sizes exclude allocator/sequence metadata and the existing program owner.
Every timing includes equal input-snapshot construction and output normalization.
