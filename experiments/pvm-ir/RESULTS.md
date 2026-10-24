# Observed local results — 2026-10-23

The subsequent [real guest-loop comparison](LOOP_RESULTS.md) measures production execution.
The figures below remain the first arithmetic-kernel experiment.

This isolated experiment supports exploring prepared instructions, with no production
integration yet. Both independent process runs reproduced the following pattern:

- Four-operation loop: decoding once and retaining the existing evaluator is effectively
  tied with the 16-slot cache. Separate-run ratios were 1.00× and 0.99×; the pooled 1.02×
  is below the noise threshold and is not a win.
- 32/256-operation sequences: the full prepared representation runs about 2.7× faster
  than the cache kernel. Both process runs agree. These inputs deliberately expose
  cache collisions; the benefit depends on real program working sets and reuse.
- The compact two-operation evaluator runs about 4–9× faster than the cache kernel.
  This combines decode reuse, a smaller record and a specialized evaluator. It does
  not demonstrate that changing representation alone produces that gain.
- Fully decoded one-shot execution is slower than the cache in every selected size.
  Preparation must be amortized. The compact IR's one-shot behavior is approximately
  tied at four operations and modestly faster on the larger selected sequences.
- IR payload is 40 bytes/operation versus 64 for a full decoded result. Raw PVM code
  here takes 3–6 bytes/operation plus its bitmap: decoding expands the working set.

Exact initial HEAD: `b589f43deb4e56524fca2903903a43a5a5889c77`.
Compiler pin: `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410` (Nimony 0.6.3).
Measured binary SHA-256: `6130592bf14f04f73eb53cc59d423870f29bcf22282dedbe55b52fced0ed5400`.
Production source and ordinary build/test configuration were not changed.

Checks passed: 240 engine/oracle comparisons over complete thirteen-register results,
including zero iterations, signed immediates and unsigned wraparound; every warm timing
result checked; cold batch checksums; failing assertion sentinel; pinned formatting;
Python syntax. Two process runs contribute twenty measured samples per engine/case.
All runtime checks remain enabled. This is macOS ARM64 evidence, not Linux validation.

The first wall-only attempt had wide scheduling variation under concurrent work and
was not used for the final speedup claims. Both clocks are retained in the final raw
CSV/JSON. CPU time reduces scheduling noise but is still sensitive to frequency and
shared cache contention. Initial evidence is in `build/pvm-ir-experiment/initial-wall-only/`.

Reproduce from this checkout using a read-only existing pinned toolchain:

```sh
NIMONY=/absolute/path/to/pinned/nimony make -C experiments/pvm-ir bench
```

Review implementation and scope in [README.md](README.md), [probe.nim](probe.nim),
and [run.py](run.py). Full raw data, environment, source hashes and compile log are
under `build/pvm-ir-experiment/`. That directory is ignored and removed by `make clean`;
this record preserves the observed findings.

Next bounded experiment: preserve the production evaluator, prepare one actual guest
loop with a branch, and compare against `execute` while checking gas, step budgets,
PCs and exact exits. Only then add a lowered evaluator behind the same checks.

---

# PVM decoded instruction / IR experiment

CPU: Apple M1 Max. Checked release Nimony ARC / Clang ThinLTO.

Two process runs; three warmups and ten measured samples per case per run.
Ratios use process CPU time medians; ranges include all twenty samples. Raw elapsed times are retained.

| Operations per pass | Engine | Warm CPU ns/op (range) | vs cache16 | Cold CPU µs/pass |
| --- | --- | ---: | ---: | ---: |
| 4 | decode | 18.05 (17.42–22.77) | 0.50× | 0.07 |
| 4 | cache16 | 8.98 (8.50–11.73) | 1.00× | 0.09 |
| 4 | prepared | 8.80 (8.53–12.28) | 1.02× | 0.11 |
| 4 | compact-ir | 2.19 (2.09–2.32) | 4.10× | 0.09 |
| 32 | decode | 20.52 (18.91–25.33) | 1.20× | 0.60 |
| 32 | cache16 | 24.58 (22.20–26.89) | 1.00× | 0.70 |
| 32 | prepared | 9.24 (8.80–11.89) | 2.66× | 0.85 |
| 32 | compact-ir | 2.73 (2.64–3.29) | 9.00× | 0.59 |
| 256 | decode | 20.63 (19.76–23.85) | 1.17× | 5.16 |
| 256 | cache16 | 24.10 (23.35–29.96) | 1.00× | 5.99 |
| 256 | prepared | 8.83 (8.52–10.91) | 2.73× | 6.11 |
| 256 | compact-ir | 2.73 (2.63–3.17) | 8.82× | 4.37 |

Payload bytes per instruction: full decoded result 64; compact IR 40.
These sizes exclude sequence metadata, capacity and the shared program owner.

Preparation includes allocation, decoding and disposal:

| Operations | Representation | CPU µs/preparation |
| --- | --- | ---: |
| 4 | prepared | 0.08 |
| 4 | compact-ir | 0.08 |
| 32 | prepared | 0.54 |
| 32 | compact-ir | 0.55 |
| 256 | prepared | 4.00 |
| 256 | compact-ir | 3.71 |

Arithmetic kernels only; not a full PVM execution comparison.
No gas, guest branches, memory, host calls, faults or snapshots.
No deterministic hardware/instruction counters available on this host.
Cold includes preparation, execution and disposal, excluding common program validation.
PREP is a coarse two-batch observation, not a precise latency estimate.
Ratios use process CPU time; raw elapsed time is retained and is noisy under concurrent load.

No production speedup or complete PVM conformance is claimed.
