# Sieve after the merged PVM and Nimony updates

This refresh updates the experiment to master
`cdc9dc7a73f61768c09286ac98828240d5e1f9f7`, including the October 23 Nimony upgrade,
PVM execution improvements, and merged state/storage work. Production sources and pins
match that master exactly. The changes here only adapt experiment generators and bindings:

- Replace the current paired instruction-cache object with the existing prepared table.
- Initialize the complete current block-price cache through its production constructor.
- Supply the private cursor and fresh-invocation mode required by current execution.
- Generate shared host execution from the current response-only cursor scheduler.

The four-entry gas memo, staged scalar writes, retained control targets and current
publication/host semantics remain in both compared paths. This increment introduces no
new interpreter optimization or IR operation. Its purpose is to establish that the prepared
representation still executes correctly against the improved interpreter and toolchain.

## Method and identities

Same real Rust sieve, guest build, four sizes and differential checks as the
[original comparison](SIEVE_RESULTS.md). PolkaVM remains explicitly **interpreted** at
pin `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`, with synchronous `Full(L2Hit)` gas and
4 KiB pages. The checked export includes counting and validation, unlike the stock
upstream benchmark entry. It links to 157,152 code bytes, 38,590 static instructions,
74 distinct static opcodes and 262 mapped pages.

Both Nim engines now use Nimony 0.6.3 nightly commit
`4724f66c2e01b17810c844f26575b2317995fda2`, checked release / ARC / Clang ThinLTO.
Bounds checks remain enabled and both deliberately failing assertion controls pass.
Rust toolchains and dependency versions remain as before. Exact commands and compiler
identities are retained alongside the measurements.

Apple M1 Max, macOS ARM64. Primary metric is process CPU time; raw wall times are also
retained. Two sequential passes reverse engine order, with three warmups plus ten measured
samples per small case per pass. At ten million, each pass has one warmup plus two measured
samples. That gives twenty measured samples per small case and four at the largest size.
Setup/preparation remains outside execution clocks; gas accounting, memory work and result
publication remain inside. Every invocation starts from the same pristine CPU/memory state.

## Measurements

| Limit | Engine | CPU ms median (min–max) | Samples | Master / engine |
| ---: | --- | ---: | ---: | ---: |
| 1,000 | polkavm | 0.482 (0.459–0.591) | 20 | 3.892× |
| 1,000 | master | 1.878 (1.777–2.010) | 20 | 1.000× |
| 1,000 | prepared | 1.835 (1.774–1.926) | 20 | 1.023× |
| 10,000 | polkavm | 2.039 (1.929–2.167) | 20 | 7.188× |
| 10,000 | master | 14.655 (14.207–14.994) | 20 | 1.000× |
| 10,000 | prepared | 14.438 (14.098–14.916) | 20 | 1.015× |
| 100,000 | polkavm | 6.090 (5.921–6.221) | 20 | 19.879× |
| 100,000 | master | 121.063 (118.816–124.863) | 20 | 1.000× |
| 100,000 | prepared | 119.222 (117.760–123.415) | 20 | 1.015× |
| 10,000,000 | polkavm | 375.889 (374.794–376.467) | 4 | 31.140× |
| 10,000,000 | master | 11705.107 (11659.952–11788.395) | 4 | 1.000× |
| 10,000,000 | prepared | 11475.550 (11404.488–11538.621) | 4 | 1.020× |

Preparation/binding wall time: median 1.184 ms, range
1.116–3.469 ms across eight process initializations. This is reported
separately and excluded from the execution table.

| Limit | Engine | Pass 1 CPU median, ms | Pass 2 CPU median, ms |
| ---: | --- | ---: | ---: |
| 1,000 | polkavm | 0.484 | 0.471 |
| 1,000 | master | 1.911 | 1.851 |
| 1,000 | prepared | 1.855 | 1.819 |
| 10,000 | polkavm | 2.067 | 2.010 |
| 10,000 | master | 14.803 | 14.348 |
| 10,000 | prepared | 14.639 | 14.227 |
| 100,000 | polkavm | 6.166 | 6.048 |
| 100,000 | master | 122.226 | 119.573 |
| 100,000 | prepared | 121.497 | 118.260 |
| 10,000,000 | polkavm | 375.147 | 376.372 |
| 10,000,000 | master | 11758.393 | 11670.888 |
| 10,000,000 | prepared | 11480.635 | 11466.470 |

Prepared differs from merged master by roughly 1.5–2.3% in these combined medians.
Treat these small differences as unproven: there is no established broad gain from this
representation. PolkaVM interpreted remains about 20× faster than merged master at
100,000 and 31× faster at ten million. The larger size is particularly limited by its
four measured samples per engine. These are local workload observations, not a general
ratio between the interpreters.

The prepared table still retains 2,784,064 payload bytes (2.66 MiB), excluding allocator
metadata and its existing program owner. Capacity remains bounded to 1 MiB of code and
65,535 decoded records for sieve; the earlier small-table caps remain 4,096 bytes and
256 records. No fused operations or specialized sieve instructions are introduced.

The older results describe older source/toolchain combinations. The improvement from
those figures includes both merged implementation work and the compiler upgrade; this
refresh does not isolate their individual contributions. Similarly, the old profile's
single-price-cache and per-store-copy observations are historical, not descriptions of
the current execution path.

## Correctness and continuation

All refreshed checks passed with the new pinned compiler:

- Sieve: 252 invocations (60 warmups and 192 measured), checking known prime counts,
  exact gas, all thirteen registers, all mapped page bytes, permissions, terminal metadata
  and unchanged source snapshots. Input/reference fixtures match between both passes.
- Guest loops: 7,203 boundary scenarios per process against both engines, including gas,
  instruction and simulation limits, interior entry, invalid PCs and branch targets.
- Shared effects: 1,685 cases per process, including bounded preparation refusals, faults,
  atomic stores, repair/reentry, host responses and ownership; both measurement processes pass.
- Separate checked AddressSanitizer effects profile: all 1,685 cases and workload assertions
  pass. Instrumented timings are discarded.
- Initial arithmetic kernels: complete-register oracle checks and both measurement processes pass.
- Pinned Nim/Rust formatting, Python syntax and whitespace checks pass. Sieve source/binary
  and fixture hashes still match the accepted report after the other checks complete.

The historical loop/effects pages retain their original measurements. Refreshed raw reports
and summaries are saved under their usual ignored build paths. These compatibility checks
preserve the existing tested scope; they do not extend fallible-host or general ISA coverage.

The next design question remains whether a complete reusable execution representation
can offer a better way to use the interpreter. These measurements establish a baseline
for that investigation. They do not motivate adding isolated tuning changes to the
experiment or replacing the current cache based on small timing differences.

Reproduce with `make -C experiments/pvm-ir sieve` and the current pinned `NIMONY`, as
in [README.md](README.md#upstream-sieve-comparison). The runner defaults to the frozen
master above and rejects a supplied compiler that does not match its toolchain pin.
Raw results, per-pass medians, generated diffs, source/binary hashes, commands and fixtures
are under `build/pvm-ir-experiment/sieve/`. Earlier local evidence was preserved under
`build/pvm-ir-experiment/sieve-pre-master-refresh/`; committed earlier result pages remain
unchanged. Linux evidence, general fault/opcode coverage and a production preparation
policy remain outside this refresh.
