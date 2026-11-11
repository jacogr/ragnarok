<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# x86 mixed-loop branch layout

The default x86 mixed-loop lowerer packs the same certified sources under the existing
4096-byte arena ceiling. The boundary/fixup assumptions, monotone finite termination,
position map and conservative pre-relaxation per-leaf ceiling are documented beside
[sealMixedLoop](../src/pvm/internal/x86_mixed_loop.nim). Source admission, gas/attempt
receipts, original continuations, eight-entry inventory and sixteen reconstruction checks
remain owned by the shared pipeline.

The frozen comparison uses d7a879b9ac8571fdf288865cb7c7388405ebd832 and
its relaxed successor e8d10e5613da9da6e95ee9dc626aeaa04d442026. The native qualifier's
1d3065004c402237b8dafe4b93eb70af6155471a baseline is a separate identity.

| Source header | Original bytes | Relaxed bytes | Arena offset |
| --- | ---: | ---: | ---: |
| 469077 | 1104 | 943 | 0 |
| 467392 | 1062 | 905 | 944 |
| 467872 | 1476 | 1275 | 1856 |
| 503995 | 518 | 452 | 3136 |

All four ranked leaves fit in 3588 bytes with the existing sixteen-byte alignment.
The earlier three-entry arena occupied 3652 bytes. ARM lowering is unchanged.

The maintained [layout suite](../tests/unit/codec/test_pvm_x86_mixed_loop_layout.nim)
checks all sixteen Jcc conditions and JMP, forward/backward/self edges, exact signed
limits and adjacent misses, unchanged scalar bytes, and a multi-pass cascade.
[Native Linux qualification](https://github.com/jacogr/ragnarok/actions/runs/43104436898)
passed both ISAs: 273 literal layout cases on x86, original transactional and paid
fault/repair continuations, RX publication/retirement controls, and fresh plus same-owner
full DOOM state/event oracles. Independently authenticated raw packets show four live
x86 sources, unchanged primary work and exact cumulative owner receipts.

[Matched default x86 comparison](https://github.com/jacogr/ragnarok/actions/runs/43107123283)
passed all 208 micro guard cells, with no established JIT timing improvement beyond baseline
variation. Retained fresh tick CPU was −0.305%, full same-owner CPU −0.648%; both remain
within stock-repeat IQR. The demonstrated benefit is four-source coverage and 64 fewer
RX bytes. The comparison uses d7 against e8 with balanced stock/repeat/candidate orders,
both policies, CPU/wall cold/first-reuse/retained/full scopes, fresh init/tick and
init followed by twelve ticks. All208 micro cells retain the +10% regression guard.
