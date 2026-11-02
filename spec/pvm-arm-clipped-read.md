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
Retrospective review verified its fixture hashes, but it is not final source
provenance. Warm tick candidate/baseline CPU ratios were 0.9421 and 0.9632 in
reversed orders; the A/A ratio was 1.0211. Init ratios of 0.9983 and 0.9963
were smaller than its A/A drift of 0.9803. No init speed claim follows. Final
confirmation requires one canonical build path, two fresh identical images per
role, and before/after hashes for the complete relevant source, configuration,
headers, compiler, all six prepared input files, ROM and compiled images before
any further timing or publication.

A Nimony generated-C direct-field observation in one width-loop test caller
cached a JIT counter across a call. The supported native witness uses a
transparent `noinline` test reader for that counter; copied public and owner
statistics and application validation are independent checks. No production
counter workaround or compiler change is part of this stage.
