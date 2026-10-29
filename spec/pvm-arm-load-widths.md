# ARM guarded load width coverage

## Scope and authority

Independent lowering of Gray Paper indirect reads124..130, retaining the canonical
PVM checks and pinned PolkaVM as a compatibility oracle. Existing native reads
support unsigned64 only; the trial adds unsigned8/16/32 and signed8/16/32 forms.
No source, toolchain or upstream pins change.

Both first-read-plus-arithmetic and transactional multi-read spans reuse the same
invocation-owned readable descriptors, modulo32 address calculation, protected
prefix/top guards and conservative eight-byte region-extent proof. Narrow reads
near a region end may fall back even when canonical access would succeed. No check
is weakened. Any narrow/signed member disables the shared scaled64-bit window;
each read retains individual original guards. Successful complete spans publish
registers once; refusal leaves them unchanged before canonical replay. Stores,
headers, host calls and other observable boundaries still terminate spans.

No frame/cache fields, ownership, source prices, budgets, handler ABI, reservation
or public default changes. Existing130 encodings and word-window paths remain.
Native instruction selection is cold and closed over the seven validated opcodes.

## Qualification gate (pending)

Keep all existing opcode, source/gas/paid-prefix, memory permission/fragmentation,
host resume/remap, source snapshot, stream transfer, refusal and ownership checks.
Strengthen the existing124..130 source witness to require real native work for all
legal nonempty map cases. Extend mixed read spans across every later load width,
including derived address aliases, later faults and all three price policies.
Add24,843 independent native literal cases: all13x13 coordinates, seven widths,
seven sign/high-bit values and three descriptor regions, with all13 registers
compared. Old LDR64 direct/span/window matrices remain unchanged.

All native builds, execution and profiling are CI-only. Require the full seven
workload both-order public comparison against the exact paired-shift parent,
complete state/host/source checks, fresh private compiler caches/equal-image
controls and calibrated cold/reused profiles. Constructors/cold/reused scopes
remain separate. Keep only a useful measured gain without material regressions;
otherwise restore this isolated runtime and retain meaningful evidence. No timing
claim before qualification.

## Originating compiler evidence

Run40796287963 at `aab374cbf6cba085a200ba52d9c4cd5a6c49cb38` stopped
at the two source-opcode conversions: the compiler could not prove their closed
124..130 domain from the distant source predicates. The fix captures each readonly
opcode in a local scalar and asserts the already required predicate immediately
before checked narrowing. No accepted opcode, runtime memory check or deadline is
changed. The original failure receipt remains under `build/pvm-arm-load-widths/first`.
This failure supplies no native or timing result. All fourteen width/address forms
also independently disassemble with LLVM to the intended LDRB/LDRSB/LDRH/LDRSH/
LDR-W/LDRSW/LDR-X instructions.

Run40796763526 at `a409f5f756acfd9f2f5c6ffd655b8c493a8c6fbc` confirmed
those production conversions compile, then rejected mixed signed/unsigned literal
types in the new full64-bit test vector. Every small vector literal is now explicitly
uint64; values and equations are unchanged. Retain this originating build log under
`build/pvm-arm-load-widths/second`; it is not a native or timing success.

## Qualified verdict: retain the guarded load family

[Run40797048906](https://github.com/jacogr/ragnarok/actions/runs/40797048906)
measured `db1a19fd89927afcdcac3dda35825c9f391239cb` against paired-shift
parent `6f8de63c4149192910a15365aa4655aec9b0b9b7`, native Linux ARM64
(CPU part0xd49), pinned October28 Nimony
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`.

Independent artifact audits passed all70 measured processes /910 checked calls /
115 positive/refusal controls /16 private fresh builds and eight equal-image pairs,
source/compiler/input/image hashes, complete CPU/gas/register/page/permission/source
snapshots and ordered host events. All nine native gates and two pricing-policy
controls passed, including24,843 new full-register width literals, all original
matrices and strengthened real native load coverage. Eight calibrated cold/reused
profiles include104 complete calls, eight private diagnostic builds/four equal-image
pairs and four collection controls. Profile clocks are discarded. No hardware
counters were collected.

CPU milliseconds forward/reverse; reused medians samples1..12. Our public call
includes fresh invocation memory and immutable publication. Reference is call-only;
its module construction and restore/call/teardown lifecycle remain distinct. The
paired-shift parent already has its small ARM tradeoff; this measures load coverage
alone, not every preceding layer against master.

| Workload | Previous JIT | Trial JIT | Checked interpreter | PolkaVM interpreted call | Trial/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 2.943/2.974 | 2.956/2.981 | 3.415/3.519 | 6.128/6.080 | 0.482/0.490 |
| Minimal100k | 6.177/5.899 | 5.635/5.721 | 6.336/6.297 | 5.468/5.530 | 1.031/1.035 |
| Memory fill100k | 4.436/4.457 | 4.436/4.454 | 4.438/4.427 | 3.730/3.758 | 1.190/1.185 |
| Pinky | 87.336/87.400 | 84.917/85.082 | 96.060/95.721 | 87.772/87.470 | 0.967/0.973 |
| Sieve10m | 288.799/287.327 | 280.986/280.860 | 346.887/345.989 | 333.559/338.157 | 0.842/0.831 |
| DOOM initialization | 322.780/325.792 | 324.682/325.203 | 541.996/536.905 | 627.442/627.489 | 0.517/0.518 |
| DOOM gameplay | 46.364/46.288 | 41.320/41.159 | 49.011/49.586 | 40.096/40.026 | 1.031/1.028 |

| Workload | Previous constructor | Trial constructor | Previous cold | Trial cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 2.935/2.982 | 3.020/3.055 | 10.562/10.517 | 10.680/10.748 |
| Minimal100k | 0.017/0.015 | 0.015/0.018 | 6.210/6.105 | 5.627/5.727 |
| Memory fill100k | 0.057/0.055 | 0.054/0.055 | 8.396/8.430 | 8.295/8.509 |
| Pinky | 0.750/0.749 | 0.728/0.736 | 91.598/91.448 | 89.296/89.444 |
| Sieve10m | 3.141/3.188 | 3.046/3.081 | 297.190/295.309 | 289.754/289.379 |
| DOOM initialization | 8.670/8.578 | 8.565/8.655 | 350.333/356.757 | 349.727/353.725 |
| DOOM gameplay | 8.510/8.558 | 8.653/8.542 | 64.366/64.103 | 59.663/59.553 |

Gameplay improves10.9%/11.1%, Pinky2.8%/2.7%, minimal8.8%/3.0% and long
sieve2.7%/2.3%. Short sieve and fill are within about0.5%; initialization is flat
(+0.6%/−0.2%). Constructors remain similar; cold gameplay also improves64.366/
64.103→59.663/59.553ms, including lazy native preparation/publication. This meets
the useful-gain/no-material-regression gate on this paired runner.

Minimal native logical work increases5,200,129→9,100,155 with the same1,300,039
calls and five entries; code880→1,300 bytes. Gameplay increases93,369,909→
122,792,155 logical operations and24,869,221→26,044,044 calls, with887→918 entries
and123,572→173,996 bytes. More coverage outweighs the extra handoffs here; this is
not a claim that handoffs are free. Initialization remains at1,024 occupied entries,
with the existing dominant connected work preserved; code131,388→159,840 bytes.
There is no eviction/promotion policy change. Counts cover the thirteen-call cohort;
profile Ir below covers one final reused call.

| Scope | Previous Ir | Current Ir | Previous conditional / indirect simulated misses | Current conditional / indirect simulated misses |
| --- | ---: | ---: | ---: | ---: |
| sieve | 46,638,427 | 46,614,407 | 57,993 / 395,200 | 208,568 / 394,970 |
| minimal | 96,243,967 | 89,443,896 | 100,160 / 1,600,026 | 147 / 1,300,024 |
| init | 3,174,437,375 | 3,171,417,697 | 1,138,891 / 23,904,050 | 1,232,130 / 23,526,707 |
| tick | 616,325,377 | 572,285,533 | 507,276 / 8,535,351 | 424,335 / 7,094,251 |

Simulated misses are not hardware measurements and do not establish a CPU cause.
Report SHA256 (applications, native, profiles):

- `45154615a1e0903f4f899f7efcd2f5f12c48ce6b82d394de28c3b6beffec3f48`
- `663e3900ae22362cedb7188b9c47267ec0495ec6cab258414f4e649852d4f957`
- `cc85520e858ef30ab30c6719cc63490e03143c88fc26c5c748678c1adf4fe808`

Exact ignored evidence: `build/pvm-arm-load-widths/third/tests`. Later CI-only or
documentation restacks preserve this measured-head provenance; the final retained
bundle receives its own public comparison.
