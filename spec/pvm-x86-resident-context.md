# Resident x86 region invocation bookkeeping

## Scope and hypothesis

Independent draft layer above the qualified ARM profile in stack1786. The parent
is the accepted single-region runtime; no rejected capacity change is restored.
The measured x86 connected-loop profile identifies region wrapper/accounting
work as a major boundary. This trial changes only invocation-local visit and
last-completed-header storage in emitted region code.

Caller-saved XMM0/XMM1 hold exact integer visit counts, XMM2 holds all-one lanes
for PSUBQ integer increments, and R11 holds the complete last-header value. SSE2
is baseline x86-64. Ordinary emitted bodies use only RAX/RCX/RDX/R8; gas/quota
remain in R9/R10. Every guarded/external return writes the same five-word scalar
context once. Zero-block returns preserve the complete incoming endpoint sentinel.
No pointer survives a call. Guest register access, source/gas guards, checked
memory, admission/hotness, quotas, handler policies and code-owner ABI are unchanged.

The original arithmetic/conditional emitters and checked fallback remain intact.
There is no FP arithmetic, optional ISA, new store/read lowering or ARM runtime
change. The context's exact integer visits remain bounded by source attempts;
each admitted block consumes at least two attempts before incrementing its count.

## Qualification and decision

The maintained CI qualifier adds1,440 independent scalar context cases across
one/two blocks, zero/partial/large quotas and gas, overflow-edge guest values and
full-width incoming sentinels. It compares all thirteen guest registers, gas,
remaining attempts, both visit counts, final endpoint and exact returned target.
Existing native/refused opcode, source-prefix, host/memory and owner controls remain.
All native compilation, execution and timing remains CI-only.

Keep only qualified same-runner useful paired gains without material regressions;
otherwise restore only the runtime emitter delta while retaining useful witnesses
and rejection evidence. Constructors, cold/reused public calls, retained-core
lifecycle and reference restoration remain separate. Both process orders and
complete source/state/image/compiler seals are required. The qualified verdict below rejects the runtime trial.

The manual x86 profiling target explicitly selects sealed baseline/current roles
for this trial, retaining the same sieve/Pinky/gameplay scopes and thirteen exact
return dumps. Direct profiler callers keep their interpreter/current default
unless `--paired-baseline` is supplied. The cohort still includes interpreted
policy and PolkaVM timings; paired profiles isolate the runtime emitter delta.


## Qualified verdict: reject

Run [40751649580](https://github.com/jacogr/ragnarok/actions/runs/40751649580)
measured candidate `426d97c5e7f8e3475271517f5a0fb37b3cf04e14` against accepted
parent `faf07492be08f5015065af75d513c8c1017afbac` on one AMD EPYC7763 runner,
both using pinned October28 Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`.
The runtime emitter is restored byte-for-byte from that parent. Independent scalar
context witnesses and paired profiling support remain. This is measured rejection
evidence, not a retained speedup; later documentation heads are not measured heads.

All15 native gates passed, including1,440 exact context cases and actual owner
move/copy lowering controls. The paired cohort passed70 processes/910 checked calls,
115 positive/refusal controls,16 private-cache builds/eight equal-image pairs and
full registers/gas/memory/permissions/source snapshots/ordered host-event checks.
Independent downloaded-receipt audits matched748 tracked Git identities, exact
source/compiler/image seals and all six calibrated profiles/78 checked profile calls.
Timing images are runner-sealed in the receipt; they are not retained in artifacts.
No hardware counters or cache simulation were collected. Simulated branch misses
below are profiler estimates, not hardware measurements.

CPU milliseconds, forward/reverse process order. Reused values are medians of
samples1..12; cold is sample0. Constructors remain outside calls; our prepared
owner and reference module construction have different responsibilities.

| Workload | Accepted reused | Trial reused | Reference interpreted call | Trial/accepted |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 3.414/3.389 | 3.432/3.428 | 6.061/6.029 | 1.005/1.012 |
| Minimal100k | 6.335/6.340 | 6.771/6.867 | 7.460/7.524 | 1.069/1.083 |
| Memory fill100k | 5.508/5.042 | 5.377/5.318 | 4.197/4.200 | 0.976/1.055 |
| Pinky | 136.505/132.866 | 136.376/134.601 | 188.091/187.863 | 0.999/1.013 |
| Sieve10m | 324.800/336.973 | 329.984/328.797 | 437.122/443.690 | 1.016/0.976 |
| DOOM initialization | 586.553/585.248 | 578.004/574.596 | 776.811/778.802 | 0.985/0.982 |
| DOOM gameplay | 57.171/56.914 | 58.868/57.398 | 52.444/52.697 | 1.030/1.009 |

| Workload | Accepted constructor | Trial constructor | Accepted cold | Trial cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 3.815/4.006 | 3.851/3.855 | 12.722/12.174 | 13.725/13.537 |
| Minimal100k | 0.018/0.019 | 0.019/0.022 | 6.881/6.982 | 7.211/7.401 |
| Memory fill100k | 0.069/0.068 | 0.068/0.069 | 10.787/11.933 | 10.618/12.169 |
| Pinky | 0.936/0.876 | 0.852/0.891 | 144.427/137.899 | 147.642/147.781 |
| Sieve10m | 4.127/3.790 | 3.798/3.985 | 333.298/347.993 | 334.742/332.606 |
| DOOM initialization | 11.312/11.030 | 11.145/10.945 | 626.826/623.710 | 611.363/618.594 |
| DOOM gameplay | 10.969/11.011 | 10.949/14.138 | 83.867/83.809 | 88.320/92.474 |

| Scope | Accepted Ir | Trial Ir | Accepted conditional/indirect simulated misses | Trial conditional/indirect simulated misses |
| --- | ---: | ---: | ---: | ---: |
| sieve cold | 114,161,993 | 114,512,940 | 740,225/504,033 | 765,162/504,007 |
| sieve reused | 42,529,377 | 42,879,377 | 62,732/466,285 | 76,096/466,283 |
| pinky cold | 1,112,783,584 | 1,112,783,620 | 2,130,203/21,196,756 | 1,990,366/21,196,553 |
| pinky reused | 1,087,438,640 | 1,087,438,676 | 1,827,774/21,176,047 | 1,682,715/21,176,048 |
| tick cold | 616,018,975 | 616,020,249 | 1,042,692/11,210,280 | 1,082,114/11,367,795 |
| tick reused | 584,515,590 | 584,516,864 | 663,257/11,182,072 | 702,813/11,339,586 |

Sieve executes350,000 more instructions in the trial; its conditional/indirect
branch totals are unchanged. Publishing counters once adds prologue/epilogue work;
fewer memory writes do not establish less total work. Minimal slows6.9%/8.3%,
although it does not exercise this connected-region body; changed image placement
is a possible factor, not an established CPU cause. Sieve has no consistent useful
gain, Pinky is inconclusive, and gameplay slows3.0%/0.9%. The initialization
improvement does not justify the other regressions. No replay is needed to reject
an optional complexity with no useful consistent target-workload benefit.

Retained core and reference restoration/teardown are separately recorded in the
complete cohort and are not mixed into the public call ratios above. Each profiled
role matches its own measured native fragments/calls/operations/code size and
branch/header totals. Cross-role code sizes differ as expected from changed emission;
this is not an equal-image runtime experiment. Equal-image controls apply to fresh
rebuild pairs and interpreted/JIT selection in the same candidate image.

Durable report SHA256: applications
`232e655101beb4c6786002d89c7d4e45dcf75eaec27de6afc4846a9009d2cb4d`;
native `65ed2e62a4db5016baf28ee8f50aec6c2ff92327ea31e69185dbbf656523fbf6`;
profiles `f370784ad4bbb90872611c043534a64a8e802637757d2f6e175c8cff189e22d8`.
Local ignored receipt root: `build/pvm-x86-resident/first/tests`.
