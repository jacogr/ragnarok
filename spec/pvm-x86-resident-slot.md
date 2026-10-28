# One resident x86 guest register in closed pure regions

## Bounded trial

The accepted connected pure-loop compiler repeatedly loads/stores guest register
array coordinates. This isolated trial selects one guest coordinate from a bounded
cold scan of the same admitted source facts, scoring explicit reads/writes and
breaking ties by lowest index. At least three static accesses justify selection.
Only that coordinate stays in caller-saved R11 across the closed region; all other
sources/destinations retain the original array accesses. One prologue loads R11;
every external/guard exit, including zero-completed-block returns, publishes it.

Gas/quota remain R9/R10 and the five-word scalar context/visit/endpoint model is
unchanged. No callee-saved register, optional ISA, guest memory operation or native
cache capacity is added. Both original sources are consumed before a destination
write; all register aliases and full64/sign/shift/high-product semantics remain.
Only region publication accepts this builder mode, and every active body must
agree on its coordinate. Ordinary entries reject it before allocating/publishing.
No invocation pointer or mutable guest value survives the native call.

## Qualification gate

An independent scalar region oracle now covers all13 cached coordinates across
one/two blocks, overflow-edge guest values, partial/zero/large gas/source quotas and
full64 zero-block endpoint sentinels:18,720 native context cases, plus the unchanged
1,440 original context cases. A portable-evaluator matrix covers every supported
opcode, saturated source/destination shape, all13 cached coordinates and ten
boundary source seeds:27,560 native complete-register/context/return cases.
Actual native coverage, ordinary-builder refusal and existing opcode/source-prefix/
host/memory/ownership/refused controls remain mandatory.

All native compilation/execution/profiling stays on CI. Keep only complete-state
exact-head same-runner useful paired CPU improvement without material regressions;
otherwise restore this runtime delta while retaining meaningful tests/evidence.
Constructors/cold/reused/core/reference lifecycle stay separate in both process
orders. Simulated branch misses do not establish hardware behavior. No timing
claim before qualification; the earlier counter/immediate trials remain rejected.

A read-only scalar selection tag consumes existing region-record padding (the
record remains72 bytes), allowing the maintained production-loop witness to prove
that both one/two-block cold selectors actually cached guest R0. This adds no
hot-path branch and retains no guest value. Two mismatched-coordinate/builder-mode
publication refusals remain explicit negative controls.


## Qualified verdict: reject resident runtime, retain generic region controls

The original complete cohort/profile [40762340241](https://github.com/jacogr/ragnarok/actions/runs/40762340241)
and bounded exact-head replay [40766837405](https://github.com/jacogr/ragnarok/actions/runs/40766837405)
both measured `0d84b7ae5f674cbb3338b3490aa7a193a1501877` against
`50fec1e9c8eb0e1cfaf86631ab7dbd9dc01146c0`, pinned October28 Nimony
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`. First CPU: AMD EPYC9V74;
replay CPU: Intel Xeon Platinum8573C. Ratios are paired only inside each runner;
absolute times across those different CPU models are never pooled.

All15 native gates passed, including46,280 new resident context/arithmetic cases,
two mismatched publication refusals, two actual production selectors, existing
1,440 context/3,168 literal controls and actual owner lowering. Each normal cohort
passed70 processes/910 full-state calls,115 positive/refusal controls and16 private
builds/eight equal-image pairs. Original profiles passed six scopes/78 calls and
four calibration controls. Replay adds36 fresh processes/468 calls, each with the
same sealed image/input/protocol and exactly matching per-role native activity.
Independent downloaded audits verify all raw logs,13calls/process, exact source/
compiler/image seals and the alternating36-process schedule (1,378 calls total).

First runner CPU milliseconds, forward/reverse, reused medians of samples1..12.
Reference call excludes restoration/teardown; constructors/cold/core retain separate
scopes and are not folded into these public ratios.

| Workload | Accepted reused | Resident reused | PolkaVM interpreted call |
| --- | ---: | ---: | ---: |
| Sieve100k | 2.626/2.638 | 2.623/2.642 | 4.976/4.979 |
| Minimal100k | 4.994/6.463 | 5.001/5.005 | 6.208/6.172 |
| Memory fill100k | 3.596/4.269 | 3.510/4.248 | 3.898/3.905 |
| Pinky | 80.058/79.090 | 78.225/79.449 | 102.585/103.318 |
| Sieve10m | 264.726/263.202 | 261.364/260.956 | 387.427/395.542 |
| DOOM initialization | 423.581/419.515 | 446.264/422.693 | 673.153/672.959 |
| DOOM gameplay | 46.698/47.702 | 47.320/46.447 | 44.986/44.849 |

| Workload | Accepted constructor | Resident constructor | Accepted cold | Resident cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 3.145/3.089 | 3.119/3.166 | 10.936/10.829 | 11.176/11.154 |
| Minimal100k | 0.017/0.019 | 0.017/0.019 | 5.161/6.528 | 5.174/5.274 |
| Memory fill100k | 0.062/0.071 | 0.057/0.060 | 9.075/11.476 | 10.629/11.378 |
| Pinky | 0.759/0.717 | 0.763/0.724 | 84.704/84.125 | 82.695/84.375 |
| Sieve10m | 3.315/3.322 | 3.114/3.652 | 269.707/270.562 | 266.856/268.743 |
| DOOM initialization | 8.534/11.189 | 8.907/8.505 | 488.973/469.184 | 485.202/462.684 |
| DOOM gameplay | 8.482/8.986 | 8.755/8.619 | 70.653/71.783 | 73.628/71.466 |

Replay distribution: six fresh processes per role/case. Reused is the median
of each process's samples3..12; the table shows median across those six medians and
their minimum/maximum. Owner/cold remain separate in the raw report.

| Case | Accepted median (min/max) | Resident median (min/max) |
| --- | ---: | ---: |
| init | 455.599 (452.243/457.932) | 457.835 (455.918/459.048) |
| minimal | 5.884 (5.775/5.902) | 5.858 (5.678/5.993) |
| pinky | 93.740 (93.207/93.959) | 94.592 (92.508/95.417) |

| Replay-run normal calls | Accepted reused f/r | Resident reused f/r |
| --- | ---: | ---: |
| Sieve100k | 2.787/2.820 | 2.774/2.803 |
| Sieve10m | 247.890/249.437 | 253.079/255.178 |
| DOOM gameplay | 50.200/49.610 | 50.381/50.073 |

| Original profile scope | Accepted Ir | Resident Ir | Accepted conditional/indirect simulated misses | Resident conditional/indirect simulated misses |
| --- | ---: | ---: | ---: | ---: |
| sieve cold | 114,161,905 | 114,355,989 | 740,263/504,033 | 699,824/503,976 |
| sieve reused | 42,529,290 | 42,629,290 | 62,771/466,285 | 12,951/466,283 |
| pinky cold | 1,112,783,572 | 1,112,844,796 | 2,130,224/21,196,756 | 1,967,155/21,196,584 |
| pinky reused | 1,087,438,629 | 1,087,438,641 | 1,827,793/21,176,047 | 1,661,068/21,176,046 |
| tick cold | 616,017,784 | 616,099,927 | 1,043,306/11,210,280 | 894,007/11,210,319 |
| tick reused | 584,514,399 | 584,515,591 | 663,873/11,182,072 | 511,724/11,182,072 |

The first runner's small long-sieve improvement does not survive replay: long sieve
is2.09%/2.30% slower on the replay runner. Initialization/Pinky process distributions
show no useful gain. Reused sieve adds100,000 native instructions for entry/exit
publication; Pinky and gameplay profiles do not enter flatX86Region/callX86Region.
Their virtually unchanged Ir and timing movements do not establish a resident-cache
benefit or a hardware cause. Simulated branch misses are not hardware measurements;
no hardware counters/cache simulation were collected.

Restore all runtime emitter/selection/tag changes exactly from the accepted parent.
Remove controls specific to the removed builder mode; retain a useful2,120-case
independent whole-region arithmetic/context matrix over the restored emitter, in
addition to the original source/gas/host/ownership/literal controls. The next useful
study is connecting the already recognized exact three-shape pure round and its
large-program publication admission, with a dedicated initialization profile.
A resident cache may be reconsidered with a different region workload, without
claiming the rejected two-block experiment helps today.

Original report SHA256: applications
`3afdc73cbddcd9bbb31b240958a154e8881eb910691eef16d75f0c66aba8ad93`;
native `0fe8ad5aec6e32663b727ea8318500b3a545916113e4badf29b932db87d826ac`;
profiles `634a78e24e48cc7a43c4fa6b742987e0fbd3422eed3d74d5b77b608035918210`.
Replay applications `d3da2000040c154791868c369cfede520f70282071f454bc22c2af3fa1a60b6f`;
replay native `4f664dc0ef70532b19c17c9c41921212113eba4d6c34a62788479cf7e4882a86`.
Ignored downloaded evidence: `build/pvm-x86-resident-slot/{first,replay}/tests`.
