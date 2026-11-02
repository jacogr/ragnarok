# ARM clipped native reads

## Scope and safety boundary

This stage changes the frame-owned ARM JIT's individual scalar-read lowering. The
canonical PVM memory preflight, eight-byte conservative native extent, decoded
opcode widths, gas/source accounting, host handoff and checked fallback remain the
authority. The change is a code-size optimization; it does not widen the set of
native-readable addresses. It applies to direct reads, scalar leaf reads and
transactional read spans, including narrower signed and unsigned forms.

A frame owns one 144-byte `ArmReadContext`: three original `(base, extent-minus-seven,
borrowed pointer)` triplets followed by three clipped triplets. A clipped triplet
intersects the original legal eight-byte starting addresses with the protected
address interval `[65536, 0xfffffff8)`. It is empty when the intersection is empty.
Its pointer advances by the intersection's offset, so the unchanged unsigned
subtract/extent test still proves every native access. The context is rebuilt only
after the frame owns moved stack/RW/RO byte allocations, and again on scratch or
host-map replacement; neither a JIT owner nor a stream retains its pointers.

The JIT owner fixes raw versus clipped scalar-read mode before publishing code.
Frame owners use clipped mode; direct legacy witness owners retain the raw 72-byte
ABI. Six typed full-context call routes cover ordinary reads, branches, mixed
reads, dirty loops, memory cycles and macro execution. Raw helpers assert that
the owner is raw before entering native code, and full-context helpers assert the
opposite. Whole read windows and stores continue to use the first three raw
triplets. Entry records remain exactly 12 bytes; mode is source-constant owner
state rather than an entry flag. Scalar-leaf refusal leaves its guest registers
unchanged, and a later failed read within a transactional read body rolls back
earlier speculative reads before checked replay. Mixed, cycle and macro outer
calls may retain earlier committed prefixes before a later refusal.

## Qualification

The supported `pvm_arm64_jit_witness` checks the production frame constructor
with a contiguous page-15/page-16 capture crossing the protected prefix, then
compares native admission at the last page's `0xfffffff7` and `0xfffffff8`
addresses. It requires native calls in accepted and refused cases, positive
operations only for admitted starts, distinctive bytes to expose a missing
pointer adjustment, and independent full CPU/memory checked state. A bounded
private upper-fence mutant (`0xfffffff9` instead of `0xfffffff8`) failed inside
this frame block before its receipt. A separate pointer mutant using the
unadjusted region start failed the independent full-state comparison with
`CONTROL_REGISTER,0,0,1234605616436508552,9`. Both overlays and logs remain
under ignored `build/`; neither changed the shipping runtime.

The same witness compares raw and clipped native results and all 13 registers
across 288 region/address cases, 378 width/alias/region/0..8-byte cases, 28
direct width fence cases, 12 modulo-32 displacement cases and three two-read
late-refusal cases. Literal A64 descriptor words and expected 36→31 span /
34→29 leaf word counts pin the intended lowering. A separate mode of the same
supported witness first enters valid raw and full typed bridges, then requires
the full owner to reject a raw 72-byte call before native entry. The ARM
qualification runner requires these receipts in native modes and rejects them
in interpreted or OS-refused modes. The existing frame witness retains complete
source, gas, memory, host, macro, resident and transfer controls.

The private stage-zero prototype also passed the independent mathematical
intersection oracle, the frozen ARM memory corpus, public runtime-policy and
compiled-engine suites, and full unclocked prepared DOOM tick/init state and
event checks. Its one-call ARM image saved 18,460 bytes for tick and 41,100 bytes
for init with equal native fragments/calls/operations/branch/header counts.

An exploratory 12-process/156-call prepared DOOM pilot used separate archive
build paths and froze only two runtime source files per role plus image hashes.
Its warm tick CPU ratios were 0.9421 and 0.9632 in reversed orders, against an
A/A baseline ratio of 1.0211. Init ratios of 0.9983 and 0.9963 were below its
A/A drift. The pilot remains distinct from final confirmation.

The final exact-`6d6ca888` versus source-`38126fb5` confirmation built each role
twice at one canonical source/cache/output path. Repeated image hashes matched;
6,028 baseline and 6,029 candidate source/config/header files, both compilers,
all six prepared DOOM inputs, the ROM, eight guest input/expected files and all
images were hashed before and after. The candidate's compiled source differed
only in the two intended runtime files. All 48 actual measured processes made
13 fully checked calls (624 total), with warm samples 3–12 and first calls
reported separately. Native fragments, calls, operations, branches and headers
and prepared cache occupancy matched between roles. The thirteen-call ARM image
saved 18,520 bytes for DOOM tick and 41,480 for init; Minimal, Sieve10M, Pinky
and Memset saved 180, 47,280, 17,820 and 640 bytes respectively.

The final DOOM tick JIT candidate/baseline warm CPU ratios across six alternating
pairs were 0.9417, 0.9704, 0.9980, 0.9522, 0.9837 and 1.0116 (median 0.9770).
Five pairs favored the candidate; one did not. Interpreted tick controls were
0.9993 and 0.9969, while same-role JIT warm medians moved by several percent
within the cohort. The tick signal required the current-master replay below
and is not a universal gain. Init JIT ratios were 0.9871, 0.9982, 0.9988, 0.9946, 0.9927
and 0.9544 (median 0.9936); interpreted init controls were 0.9974 and
1.0000. Retain the fast last candidate, but no stable init gain is established
over the pilot's init A/A ratio of 0.9803. Minimal100k slowed in both clean pairs (1.0102 and
1.0176); Pinky1 and Memset100k changed direction between pairs.

A private collector parser failed after the first Sieve10M baseline process had
already completed successfully. Its raw log was reparsed, then only the eleven
unrun micro processes were executed. No workload, image or input was rerun or
changed; the complete 32-process DOOM/interpreted sequence and four Minimal
processes were uninterrupted. Sieve pair one (0.9876) is **interrupted** and
cannot be treated as an uninterrupted paired comparison. Its second reversed
pair (0.9893) was adjacent and clean; the two Sieve pairs must not be pooled as
two clean reversals. The local final audit verified 48 raw logs, 624 complete
samples, 15 fixed inputs, eight repeated images and unchanged source/toolchain
bytes, with only this documented collector correction. No more local timing is
part of this stage.

Master `360ed9e6` was then merged normally after preserving all `38126fb5`
cohort artifacts. Combined source passed the native width/alias/fence witness,
legacy raw/full ABI refusal, ARM fragmented-memory and host reentry, exclusive
frame/stream move/copy checks, persistent page chunks, and unclocked complete
DOOM tick/init calls under JIT and interpreted policies. One-call JIT image bytes
and native work matched the qualified clipped candidate; interpreted native
counters stayed zero. This combined head has **no local timing result**. Its one
authorized [Linux ARM replay](https://github.com/jacogr/ragnarok/actions/runs/41543935100)
used master `360ed9e6` as the baseline and `b3ca755f` as the candidate, with
paired interpreter controls. Its retained `pvm-comparison-arm64-1` artifact
(ID `13189161889`, SHA-256
`dba74e63bc556a67fa5bdbe220d633e7515567157543d715862caa5ecf85d62e`)
passed. The candidate runtime source blobs are unchanged at the later fixture
and report commits. The audit matched 84 primary and 60 replay process logs,
138 controls, 18 paired images and the exact native work/fragments in all 44
baseline/candidate comparisons. The later strict native gate also accepted all
14 qualification rows against the retained log bytes and exit codes.

The Linux replay's six alternating warm CPU ratios (candidate/baseline) were
1.0197, 1.0131, 1.0226, 1.0195, 1.0175 and 1.0180 for init: every pair
slowed, with a reported group change of +1.8154%. The corresponding tick
ratios were 0.9672, 0.9680, 0.9671, 0.9668, 0.9758 and 0.9660: every pair
improved, with a reported group change of -3.0795%. The primary JIT run also
showed slower init (+1.9819%) and faster tick (-3.4817%) in both orders;
replay first-call init was slower (+1.6417%). Minimal improved in all six
Linux replay pairs (group -2.5066%, ranges overlapping), unlike the older
local cohort. Sieve10M improved in all six (group -0.8638%, ranges not
overlapping), while Pinky was small and its ranges mixed. Interpreted init
and tick controls were mixed with overlapping ranges. These results support
the current-master tick gain and init regression, with no overall cold gain.

A Nimony generated-C direct-field observation in one width-loop test caller
cached a JIT counter across a call. The supported native witness uses a
transparent `noinline` test reader for that counter; copied public and owner
statistics and application validation are independent checks. No production
counter workaround or compiler change is part of this stage. The suspected
behavior, project-bound reproducer and pending reduction gates are tracked as
[NIM-005](compiler-issues.md).
