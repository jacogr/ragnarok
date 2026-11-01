# Immutable snapshot page directories

## Ownership and update cost

`MemoryData` privately retains sorted page references through immutable blocks of at most
64 initialized entries. The last block contains exactly its live entries. A successor copies
the root's block references and clones each affected block once, then installs fresh page
owners. Untouched blocks, pages and 512-byte chunks remain shared through ordinary acyclic
ARC ownership. No parent links accumulate snapshot history.

For P stored pages and B affected blocks, sparse publication retains O(ceil(P/64) + 64B)
references instead of retaining every page. `withReplacedPages` checks physical indices and
strict ordering first, then validates complete membership/access before allocating copied
successors. Sparse batches use bounded searches; dense batches keep a monotone merge.
Scalar and host writes retain complete range/permission/copy-budget preflight before cloning.
`changedMemoryPages` skips identical immutable blocks, validates all differing mapping metadata,
then produces sorted copied deltas. Guest page limits, errors, bytes and public APIs are unchanged.

An active `ScalarMemoryWriter` keeps its mutable working vector. Publication moves those page
references into immutable blocks, avoiding another page-wide retain/release pass. Subsequent
aliased writer stores follow the existing epoch isolation rules. General insertion/remapping
still rebuilds the sorted directory. Invocation entry still copies eager private memory.

The indexed helper expands a borrowed location. Generated C confirms that binary-search
lookups introduce no page-owner duplication or allocation. Construction transfers page
references out of the consumed vector.

## Validation

The registered `pvm_memory_directory` suite checks complete 129-page patterns, dense and sparse
batches, shared predecessors, both reference-block boundaries and the partial final block.
It covers scalar and host crossings, caller-buffer mutation, aliased writer epochs, rejected
batches and unchanged output on invalid slots. A thousand release cycles retire multi-block
roots, predecessors and writer epochs without changing occupied ARC memory. Existing machine,
chunk, scalar-step, execution/cache, independent memory-access/boundary and host-reentry checks
also pass. The public DOOM driver checks complete CPU, every page, source immutability and host
events on every invocation. Native owner activity matches the baseline exactly, excluding the
measured compilation-time counter; interpreted runs retain zero native activity.

## Local ARM comparison, 2026-11-01

Apple M1 Max, checked ARC/Clang ThinLTO, pinned Nimony
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`. Shipping baseline:
`2e6f9bfe04d52755cff49438d271b3eb743b9533`.

Both roles use the same canonical source/output/cache paths, flags and public drivers.
Two fresh builds per role/family produce identical binaries. Four balanced fresh processes
per source role execute 13 prepared public calls; each process contributes the median of
samples 3 through 12, and the table takes the median across processes. Two fresh interpreted
PolkaVM processes supply the raw-call denominator using the established benchmark lifecycle.
Public interpreter/JIT calls include their invocation ownership and checkpoint work.

| Workload/backend | Baseline ms | Candidate ms | Change | Candidate / PolkaVM interpreted |
|---|---:|---:|---:|---:|
| DOOM init JIT | 171.048 | 120.010 | -29.84% | 0.175 |
| DOOM init interpreter | 304.050 | 244.897 | -19.45% | 0.356 |
| DOOM tick JIT | 17.316 | 17.294 | -0.13% | 0.399 |
| DOOM tick interpreter | 24.516 | 24.322 | -0.79% | 0.561 |
| Minimal JIT | 4.230 | 4.247 | +0.42% | 0.698 |
| Pinky JIT | 66.180 | 66.622 | +0.67% | 0.696 |
| Memset JIT | 2.772 | 2.806 | +1.20% | 0.690 |
| Sieve 10m JIT | 212.530 | 215.827 | +1.55% | 0.578 |

DOOM initialization improves substantially. JIT tick process ranges overlap; its small point
estimate does not establish a speedup. Micro point estimates regress by 0.4–1.6%, including
nonoverlapping sieve process ranges. These costs remain part of the tradeoff. The Linux qualification below provides the separate portable comparison.

A separate single-executable policy control compares 64-entry blocks with one full-sized
reference block. It gives init 188.826→119.232ms (-36.86%) and tick 17.332→17.351ms (+0.11%).
That large-block policy retains the new directory indirection and validation, so the shipping
comparison above supplies the actual baseline delta.

Local evidence is retained under `build/pvm-page-directory/`. Shipping raw JSON SHA-256:
`2dd1f3504938ef8d26b7443d4cf106fb19e7ff1338460c6b7d9576bf597e4f82`.
Policy-control raw JSON SHA-256:
`cde270522d11276e84bd95268def9c5a394d25cedaf4642eaafb628487df79ae`.
`shipping-comparison/formatted-image.json` ties final formatted source to the measured images:
the kernel binary is identical; all loaded DOOM code/data sections and addresses are identical
except three assertion diagnostic line-number digits. The first strict full-file comparison
failure is preserved in `formatted-first-image.json`.


## Linux ARM qualification

[Focused run 41296206338](https://github.com/jacogr/ragnarok/actions/runs/41296206338)
qualifies runtime commit `43db1a8a6f7db3e9dde8d929ebdd4bf6ba56478c` against the same
`2e6f9bfe04d52755cff49438d271b3eb743b9533` baseline. All 20 builds, 84 primary runs,
138 declared positive/refusal controls and 60 process replays pass. Fresh reparsing reproduces
all 144 primary/replay records. Fourteen cross-source native activity pairs match exactly apart
from compilation time; explicit interpreted policies retain zero native activity. The independent
review also verifies frozen fixtures, direct/dirty/word/mixed/priced controls and stream/frame moves.

Six fresh replay processes per JIT role, process medians of samples 3:13:

| Workload | Baseline ms | Candidate ms | Change |
|---|---:|---:|---:|
| DOOM init | 235.639 | 148.213 | -37.10% |
| DOOM tick | 27.953 | 28.100 | +0.52% |
| Minimal | 5.619 | 5.583 | -0.64% |
| Pinky | 84.052 | 84.269 | +0.26% |
| Sieve 10m | 274.156 | 283.852 | +3.54% |

Tick process ranges overlap (baseline 27.651–28.195ms, candidate 27.664–28.312ms), with
mixed paired directions. All six long-sieve candidate processes are slower. The primary
interpreted cohort has only two fresh processes per role: init improves 20.89%, while tick
regresses 2.73% (31.648/32.148→32.525/33.016ms). This observed interpreter tick cost is part
of the tradeoff and has less process replication than the JIT replay result.

Primary raw DOOM tick ratios to PolkaVM interpreted are 0.698 JIT and 0.818 interpreter;
init ratios are 0.236 and 0.518. These use the primary cohort and its established call lifecycle,
not a replay numerator combined with another cohort's denominator.

The implementation is accepted as a substantial checkpoint/initialization improvement with
explicit tick/interpreter/sieve costs. It does not establish a uniform execution speedup. Future
work should preserve the immutable sharing benefit while reducing entry and fragmented-region
costs. This qualification uses one focused ARM runner and no broad verification label.

Artifact `pvm-comparison-arm64-1`, ID `13079423649`; application report SHA-256:
`01e91028d93c85a9b67d2dad66615eb1b17777deb12a69753faf556fcab179a5`.
Independent [source review](https://github.com/jacogr/ragnarok/pull/1879#issuecomment-6556723020)
and subsequent artifact audit found no correctness, ownership or refusal defect. Later changes
are verdict/documentation only; runtime and fixture sources remain those of the qualified commit.
