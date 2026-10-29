# Native paired-shift reduction

## Scope and proof

An isolated equivalent arithmetic rewrite inside already reserved three-block
native regions, for ARM64 and Linux x86-64. The pinned PVM semantics mask64-bit
shift counts modulo64. When opcode151 writes D from S, immediately followed by
opcode152 reading/writing D, with equal effective counts k, their complete result
is `(S << k) >> k = S & (2^(64-k)-1)` under64-bit wrapping arithmetic. For k=0,
the result is an ordinary full-width copy. All other coordinate/count patterns
retain the original two operations; a declined builder must stay untouched.

Native admission still requires the complete source block. Partial source quotas,
paid/gas failures and observable exits use the existing original workers, so the
intermediate left-shift value remains observable at the original boundary. Logical
source spans, prices and operation counters still include both instructions.
No header/host/memory boundary is crossed. No cache/frame/ABI/capacity policy or
upstream/toolchain pin changes. Rejected ARM store runtime is absent.

## Implementation and qualification gate

ARM uses one unsigned bitfield extract; x86 uses a mask with the original register
array contract. Only a genuine adjacent151/152 source pair with the same final
coordinate and matching masked counts qualifies. Helpers validate before mutating
the cold builder. Existing aliasing, source budget, branch, host, memory and owner
checks remain. No runtime condition or additional metadata enters the hot loop.

Direct native literals cover every13x13 source/destination pair, all64 effective
counts, high immediate bits and independent wrapping-shift equations over full64
values. Declined destination/source/count patterns leave code construction and
native execution unchanged. Existing complete-state three-block rotations and
every source/gas/paid prefix still run through the actual production selector.
All native compilation, execution, profiling and timings are CI-only. Require
same-runner both-order constructor/cold/reused comparisons for all seven workloads,
full source/compiler/input/image/reference-state checks and calibrated profiles.
Keep only useful benefit without material regressions; otherwise restore this
isolated arithmetic rewrite and retain useful evidence. No timing claim yet.

## Initial native qualification and CPU evidence

Both implementations passed the full native checks: 64,896 coordinate/count/value
literals and 507 unchanged-builder declines per architecture, complete source
prefix/gas/paid/exit rotations, ownership, checked memory and explicit refusal.
The rejected ARM store implementation is absent; its 43,904 checked fallback and
360 later-store boundary controls remain and pass. All measurements below use
pinned October 28 Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`.

Each architecture independently passed 70 normal processes / 910 complete checked
calls / 115 positive/refusal controls / 16 private fresh builds and eight equal
image pairs, exact source/compiler/input/image hashes and ordered host events.
Eight cold/reused profiles each contain 104 checked calls; four collection controls
passed. ARM also has eight diagnostic builds / four equal-image pairs. x86 profiles
use the normal sealed binaries. Simulated misses are not hardware measurements.

### X86 initial cohort

[Run 40790229416](https://github.com/jacogr/ragnarok/actions/runs/40790229416)
measured `fd811361aab41c0e80d7e33597e397806d275dcd` against `83c28ccb94ea7e42a984a5cbedabb8a88f30424a`, CPU `AMD EPYC 7763 64-Core Processor`.
CPU milliseconds forward / reverse; reused samples 1..12. Our public call includes
fresh invocation memory and immutable publication; PolkaVM is call-only. Constructors
and cold calls are separate. These are same-runner pairs; do not pool architectures.

| Workload | Previous JIT | Trial JIT | Checked interpreter | PolkaVM interpreted call | Trial/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 3.332/3.366 | 3.407/3.295 | 4.284/3.822 | 6.074/6.093 | 0.561/0.541 |
| Minimal100k | 6.316/6.295 | 6.354/6.333 | 6.359/6.354 | 7.500/7.470 | 0.847/0.848 |
| Memory fill100k | 4.637/4.629 | 4.600/4.647 | 4.827/4.893 | 4.184/4.190 | 1.099/1.109 |
| Pinky | 130.033/127.158 | 133.229/124.169 | 157.696/160.513 | 186.745/181.599 | 0.713/0.684 |
| Sieve10m | 331.521/339.415 | 321.880/322.802 | 355.255/378.354 | 444.274/443.180 | 0.725/0.728 |
| DOOM initialization | 333.415/329.226 | 319.556/327.311 | 609.749/611.377 | 775.618/775.996 | 0.412/0.422 |
| DOOM gameplay | 59.094/59.582 | 55.633/57.481 | 56.160/56.959 | 52.517/52.428 | 1.059/1.096 |

| Workload | Previous constructor | Trial constructor | Previous cold | Trial cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 3.906/3.775 | 3.753/3.781 | 12.437/13.161 | 12.724/12.755 |
| Minimal100k | 0.019/0.022 | 0.019/0.018 | 7.016/6.464 | 6.920/6.940 |
| Memory fill100k | 0.064/0.063 | 0.070/0.067 | 10.030/10.035 | 12.324/11.867 |
| Pinky | 0.831/0.876 | 0.847/0.870 | 138.556/134.230 | 137.131/132.722 |
| Sieve10m | 4.108/3.606 | 3.896/3.664 | 336.473/338.379 | 332.109/331.440 |
| DOOM initialization | 11.049/13.974 | 14.034/11.009 | 366.613/375.495 | 367.311/367.571 |
| DOOM gameplay | 11.065/10.931 | 11.028/10.886 | 86.132/86.150 | 84.601/83.735 |

| Reused scope | Previous Ir | Trial Ir | Previous conditional / indirect simulated misses | Trial conditional / indirect simulated misses |
| --- | ---: | ---: | ---: | ---: |
| sieve | 43,779,767 | 43,779,829 | 12,748 / 466,286 | 62,733 / 466,285 |
| pinky | 1,089,541,670 | 1,089,541,706 | 1,240,416 / 21,204,165 | 1,043,063 / 21,204,165 |
| init | 3,957,207,868 | 3,872,040,427 | 1,721,966 / 23,234,922 | 2,024,369 / 23,234,922 |
| tick | 584,794,070 | 584,795,344 | 523,025 / 11,182,072 | 645,631 / 11,182,072 |

Native logical work, calls and occupied entries are identical. Initialization code
shrinks 95,042 to 95,010 bytes at 1,023 entries; other profiled code footprints are unchanged. No eviction policy changes.

Report SHA256 (applications, native, profiles):

- `3bbe33f79bc1b869de22baef0142305a49733c1ddc9eb1a597da621fb5af8a0e`
- `be8450bfd596845f8e60b0e04da811cc2f819651f4ea1d67d4c9b144644966e4`
- `3931fd506602bab48412381aeb41e4082f7dfaa6823bc4c8c864b6e332096b2d`

### ARM initial cohort

[Run 40791565243](https://github.com/jacogr/ragnarok/actions/runs/40791565243)
measured `2fe3cc80f41709837edd1f2f1ed5e6bb38927a3f` against `203cce5615a51aa2f8656d925b4e2be9c3ecb233`, CPU `aarch64`.
CPU milliseconds forward / reverse; reused samples 1..12. Our public call includes
fresh invocation memory and immutable publication; PolkaVM is call-only. Constructors
and cold calls are separate. These are same-runner pairs; do not pool architectures.

| Workload | Previous JIT | Trial JIT | Checked interpreter | PolkaVM interpreted call | Trial/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 2.965/2.969 | 2.915/2.965 | 3.515/3.528 | 6.061/6.112 | 0.481/0.485 |
| Minimal100k | 5.969/6.223 | 5.920/5.903 | 6.174/6.199 | 5.453/5.548 | 1.086/1.064 |
| Memory fill100k | 4.369/4.448 | 4.395/4.380 | 4.450/4.405 | 3.753/4.127 | 1.171/1.061 |
| Pinky | 86.861/87.352 | 87.230/87.306 | 95.383/95.873 | 87.802/87.504 | 0.993/0.998 |
| Sieve10m | 283.057/283.686 | 287.468/287.418 | 339.425/346.549 | 333.957/333.523 | 0.861/0.862 |
| DOOM initialization | 331.473/310.106 | 325.803/311.189 | 524.555/529.010 | 627.597/627.599 | 0.519/0.496 |
| DOOM gameplay | 46.053/45.992 | 46.267/46.033 | 49.703/49.417 | 40.083/40.072 | 1.154/1.149 |

| Workload | Previous constructor | Trial constructor | Previous cold | Trial cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 2.977/2.852 | 2.964/3.010 | 10.575/10.512 | 10.589/10.627 |
| Minimal100k | 0.014/0.016 | 0.015/0.014 | 6.180/6.276 | 6.144/6.077 |
| Memory fill100k | 0.054/0.068 | 0.052/0.053 | 8.538/8.710 | 8.551/8.199 |
| Pinky | 0.738/0.732 | 0.896/0.726 | 91.149/91.440 | 93.089/91.575 |
| Sieve10m | 2.969/3.690 | 2.975/2.867 | 292.291/298.379 | 295.026/295.053 |
| DOOM initialization | 8.531/8.514 | 8.568/8.474 | 350.946/341.870 | 354.233/335.279 |
| DOOM gameplay | 8.626/8.545 | 8.593/8.472 | 64.815/63.856 | 64.554/63.531 |

| Reused scope | Previous Ir | Trial Ir | Previous conditional / indirect simulated misses | Trial conditional / indirect simulated misses |
| --- | ---: | ---: | ---: | ---: |
| sieve | 46,638,427 | 46,638,419 | 215,947 / 395,198 | 57,993 / 395,200 |
| minimal | 96,243,967 | 96,243,967 | 162 / 1,400,027 | 100,160 / 1,600,026 |
| init | 3,238,322,378 | 3,174,437,375 | 2,163,588 / 23,899,878 | 1,138,891 / 23,904,050 |
| tick | 616,325,377 | 616,325,377 | 1,565,074 / 8,523,586 | 507,276 / 8,535,351 |

Native logical work, calls and occupied entries are identical. Initialization code
shrinks 131,400 to 131,388 bytes at 1,024 entries; other profiled code footprints are unchanged. No eviction policy changes.

Report SHA256 (applications, native, profiles):

- `2ff948d70e9769e9c6a68bfbb60e1c305fca1689dec9c86d5a1462fd49c5c008`
- `d6c826b33531533e49648670b337d44cb23a405b749946fd4a00dfe7927a2508`
- `8e729dd1f8baa85ab8bfd3d1c642cf9fdac8c9ae87ec9b713ade4e9b798fa585`

### Pending repeatability verdict

The x86 initialization body executes about 85 million fewer native instructions per
reused call, with identical logical work. CPU initialization is 4.2% / 0.6% faster
and gameplay 5.9% / 3.5% faster in this cohort; the latter has no corresponding
logical/native work change, so it is not attributed to the pair reduction.
ARM initialization removes about 64 million instructions but is 1.7% faster / 0.3%
slower. Long sieve has identical code/work and varies by architecture. These are
not sufficient to declare a universal gain. An opt-in `jit-arm-replay` selector
now uses the existing sealed-image 60-process / 780-call replay protocol on ARM,
without profiling or extra ordinary CI jobs. Final retention awaits repeatability
and the independently qualified compact x86 parent. No checks are weakened.

## Final bounded-run verdict

Retain the small ARM pair reduction and its independently repeated initialization
gain; record the roughly1.4% long-sieve tradeoff explicitly. Defer the x86 pair
reduction: corrected-parent run40798590242 at3fb35982 passed all state/native
checks and130 processes/1,690 calls, but repeated minimal slows about9% while
initialization improves4% and gameplay improves about11%. Minimal has zero native
fragments. The later ten-scope diagnostic at1fca6f34 shows identical minimal
Ir92,997,007 and38/38 selected hot instruction sequences after relocation
normalization; gameplay36/36 are also identical. No hardware cause is established.

The same-source/image replay control40803954273 uses1fca6f34 for both roles,
passes exact image identity and does not reproduce that slowdown (minimal paired
median about+0.4%). Do not attribute the9% effect to policy selection or the pair's
executed arithmetic. These observations merit a separate code/data-placement study,
not an unconditional speedup claim.

Restore all x86 runtime, builder and qualification changes from this layer to its
parent. The exact native literal matrices, raw profiles and measured heads remain
in the immutable CI branches and repository history. ARM runtime and source/gas/
paid/host/ownership checks remain. The x86 three-block parent is also deferred by
its owning layer, so the shipping chain keeps the previously accepted x86 engine.
