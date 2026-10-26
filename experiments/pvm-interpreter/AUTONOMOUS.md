# Autonomous investigation

Authorized 2026-10-26 at 20:32:28 Asia/Nicosia. Absolute ceiling is 2026-10-27 at
04:32:28 Asia/Nicosia (02:32:28 UTC). Stop earlier if useful hypotheses/returns are exhausted.
Branch: `codex/pvm-interpreter-lab`; starting checkpoint `72c79e4d`.

No PR, CI experiment, merge, default engine switch or other checkout edits during this run.
Each isolated trial keeps gas, attempt ordering, exit PCs, checked memory and immutable host
observations intact. Keep/revert decisions require complete native/reference checks and paired
CPU timing. Constructors, cold calls, reset, host work and final publication remain visible.
All samples remain recorded; competing activity is observed, not automatically discarded.
The maintainer reports no other active agents at the start of this window.

## Trial 1 — rare exit/error outlining

Hypothesis: the compiler currently expands rare observable-state/error publication into hot
block-entry and opcode workers. Preserve the exact helper bodies and call ordering but require
`flatStopExit`, `flatLocal` and `flatBudget` to stay out of line. Inspect actual linked ARM64 and
measure whether the smaller hot bodies help DOOM initialization without material regressions.
This does not remove any state write or reuse rejected exit-derived source accounting.

Status: rejected and restored. Eight native and eight sanitizer groups pass, all six role/driver
fresh-cache image pairs are equal, and192 clean-cohort processes plus4negative controls complete.
Reused init +0.39%, gameplay +1.41%, Minimal lifecycle +2.53%; no useful gain. Full logs,
inputs, profile images and process timings belong under
`build/pvm-interpreter-experiment/comparisons/outline-exits` and `build/ci/outline-exits-*`.

The first diagnostic timing cohort is excluded in full after a sample-count/log-reuse harness
repair; no individual outlier was selected. Qualified runtime/image bytes remained unchanged.
The accepted checkpoint is restored exactly. Comparison/report tools and eight focused harness
tests are retained for following experiments. See findings/outline-exits-qualified.md.

## Next hypothesis — paid versus unpaid entry

Normal successful control transfers always clear the paid flag before selecting a charge header.
Initial invocation/reentry may instead be prepaid. Test separating those paths once at invocation
start, rather than loading/testing the flag at every ordinary block entry. Preserve price failure,
zero budget, barrier restoration, gas and exact source-attempt contracts. This is distinct from
rejected per-opcode entry-worker specialization and rejected exit-derived budget accounting.

Trial2 is now the unpaid-entry split. Eight native groups pass, including paid/unpaid and failed
pricing-policy entry witnesses. All subsequent trials use six reused DOOM initialization pairs
as well as six gameplay pairs, with both cold orders retained. An assertion-instrumented copy
will independently check the internal unpaid-entry invariant; its clocks are excluded.

Trial2 verdict: reject and restore. Six reused init pairs median +0.40%, six gameplay pairs
+0.12%; sieve kernel +1.48%, fill kernel +2.11%. The ordinary-entry invariant is confirmed in
native/ASan instrumented images (70,220,477unpaid and1,621paid entries), but reduced static work
again fails to improve CPU time. Findings and the exact patch are retained.

## Next focus — construction and host publication algorithms

Two dispatch-only simplifications failed. Current phase data show substantial frame construction,
reset and host snapshot costs. Inspect bulk page construction (currently byte-at-a-time append)
and a bounded dirty-page working set that avoids scanning every mapped page at every observation.
These are independent hypotheses and will be measured separately; no runtime change started yet.

## Trial3 — bulk page construction

Replace the per-byte append loop in private contiguous-region construction with one checked
4096-byte extent growth and bulk page copy. Validate native-int addition and exact grown length
before taking raw addresses. Same region coalescing, source ownership, mapping, permissions,
private byte storage and reset/publication contracts. Constructor work is mandatory in the report;
execution-call timing alone cannot demonstrate this hypothesis. Native checks pass; ASan and
fresh same-path controls are running. Exact parent: b19262e5.

Trial3 verdict: keep bulk page construction. Reused gameplay lifecycle median -17.10%, every
pair -16.76..-17.99%; calls +0.09% (flat). Six retained cold-init pairs: call -0.32%, lifecycle
-1.35%median; one busy pair remains +7.87%/+6.45%. Constructor/reset clearly improve; no broad
kernel gain claim. All208timed processes +4negative controls pass with stable seals. Eight full
native and ASan groups pass, six fresh role/driver equal-image controls pass. Eight separate
RSS probes observe270.22..270.34MiB for both roles; clocks excluded. No sample discarded.

## Next hypothesis — immutable page identity before metadata validation

`changedMemoryPages` already uses immutable page identity in its copy pass. Test using that same
positive ownership fact in the preceding mapping-validation pass, skipping index/permission
loads only for identical retained page owners. Keep two passes and complete mapping validation
before allocating any delta, preserving refusal/atomicity ordering. This targets host resume
cost without altering guest execution or introducing a new memory representation.

## Trial4 — shared-page validation

Exact parent bb7530f6. Keep the existing complete preflight and two-pass delta construction;
inside preflight, identical immutable PageData ownership proves index/access identity and avoids
redundant metadata dereferences. Six new late-permission mismatch cases, separate equal-byte
owners, shared prefixes and default-owner witnesses pass with all eight native/ASan groups.
Fresh same-path baseline/candidate repeat images match for all three drivers. Timing now starts.
No changes to guest execution, cache, publication payloads or delta-allocation/refusal ordering.

Campaign housekeeping: stop starting new work by02:22UTC (04:22Asia/Nicosia) to reserve ten
minutes for qualification/restore, commits, push and the final report before the absolute ceiling.
The next publication diagnostic is prepared under the ignored build directory; run only after
current timings finish. It counts scanned metadata pages, dirty candidates and empty observations;
all diagnostic clocks are discarded. Do not compile/profile concurrently with valid timing runs.

Trial4 verdict: keep shared-page metadata shortcut. All six reused init calls improve0.65–1.98%
(median0.79%); lifecycle -0.87%. Resume phases33.28–33.58ms ->25.53–25.90ms. Gameplay/small
kernels broadly flat. Native/ASan8groups including6new metadata cases,6equal-image pairs,
200timed processes/4negative controls and stable seals pass. Diagnostic clocks discarded.

## Trial5 planned — bounded dirty publication directory

Separate count-only diagnostic: init1621observations scan6,945,985mapped headers but only9253
are dirty candidates (8293actually changed); all observations are nonempty. Tick scans4285for
336dirty/273changed. Host delta positive cases1590cover6,813,150mapped pages with2026different
owners. Archive probe source/counts in findings. Next: directory at existing first-dirty transition,
bounded by mapped page count, private sorted copy and checked source-slot lookup for publication.
Keep bitmap and its full clearing initially; retain original per-candidate bit/permission/copy checks,
refused-reply state, source snapshots and observation/epoch semantics. One mechanism at a time.

## Correctness interlude — active-stream quota barrier

The directory trial's new mixed-prefix witness exposed an existing accepted-parent bug; no timing
of that optimization has run. Minimal program: two load-immediates then halt. Run1instruction,
resume2tohalt, reset, run2: oldparent incorrectly returnsHalt instead ofStepLimitExceeded because
compiledForPc now points into another suffix. Exact parent84b8cbe3 reproduces independently.

Fix chooses the first active-stream node with source site at/after the reserved prefix boundary,
starting at the actual charge header. Valid program admission guarantees concrete terminating
nodes; folded gaps retain their original PC through barrierFact. Keep all temporary restoration,
paid/gas/source-count behavior. Minimal +14mixed-prefix epochs +162folded-prefix epochs pass,
as do all eight native/eight ASan groups. Fresh same-path image repeats match for3drivers/2roles.
An exploratory unterminated-program fixture was rejected by the existing decoder's final-T rule
(GP-PVM-004); no decoder/fallthrough behavior changed. Correctness comparison now starts against84.

The dirty-directory runtime is saved only as a pending diagnostic. Reapply
build/pvm-interpreter-experiment/pending-directory-only.patch AFTER committing this fix; do not
copy the old complete pending runtime back, because that would reintroduce the fixed barrier bug.

Correctness interlude verdict: retain active-stream quota fix.200timed processes/4negative
controls and stable seals pass; init reused paired median +0.16%, tick -0.24% within spread.
No speed gain claimed. Exact-parent failure and all176new prefix epochs are retained with
the complete eight native/eight ASan witness groups. Production src remains untouched.

Trial5 resumed against correctness parent9e3317d5. Applied directory-only patch; active-stream
quota fix remains present. Full updated publication witnesses must pass before timing.

Trial5 verdict: reject dirty directory. Complete200timed/4negative controls pass with stable
seals; all8native/8ASan and fresh image controls pass. Init reused call median -0.70%,
but Minimal kernel +5.52% and Pinky +1.63%. Exact runtime restored to9e3317d5; quota fix
and its witnesses remain. No sample removed. The first-dirty helper changes possible hot
store lowering even when rarely called; timing does not establish a CPU cause.

Next: binary search for sparse checkpoint refresh. This changes only post-host source-image
lookup, preserving complete preflight, checked copies, sorted changes and commit ordering.

## Trial6 — sparse checkpoint binary lookup

Parent ee649d60 (runtime identical to9e3317d5). Replace only flatRefreshImages' monotone
linear scan with checked lower-bound search in the remaining source suffix. Preserve exact
matching-index assertion and complete PageImage assignment. Existing mixed/top-page, host
refusal/repair, snapshots and reset witnesses cover this path; no guest-store/dispatch change.

Trial6 verdict: keep sparse checkpoint lookup. Init all6pairs -0.43..-0.91%, median -0.61%.
Small kernel medians within0.13%; tick +0.35% (range+0.005..+0.79%) remains visible. Full
200timed/4negative,8native/8ASan and6fresh equal-image pairs pass with stable seals. No
broad guest-loop speed claim. Next diagnostic: fresh init statistical profile and count-only
register-first pair trace; all diagnostic clocks excluded.

## Trial7 — observed arithmetic/branch combination

Fresh accepted-image3second/1ms init profile (13fully checked calls) has619collapsed charge
hits,355dispatch,121register-prefix and multiple branch workers. These are statistical hits,
not time fractions or hardware counters. Separate count-only full-state init observes
21,295,001executions of131->88(add_imm_32 then signed immediate branch), vs only small
remaining register/register combinations. No diagnostic clocks retained.

Try only this pair. Cold first worker executes the original prefix/branch validation and
self-patches only after observing the genuine cached branch handler. Hot worker uses the
shared arithmetic/condition equations and cached arms; the second node remains independently
addressable. Guard its quota boundary before branch reads or paid-flag mutation. Preserve
PC/gas/source ordering and both-arm refusal. Focused4320cases pass with signed wrap, aliases,
saturation, forward/backward/invalid arms, gas and all quota boundaries. Existing10560entry
cases now also compare independently single-stepped CPU for local quota failures.

Trial7 verdict: retain on experimental branch with explicit tradeoff. Reused init all6pairs
-2.13..-3.94%, median -2.76%(~19ms); small kernels -1.10/-0.46/-0.98/+0.05%. Tick reused
call -0.38%, life -0.26%. Original2cold tick lifecycle pairs +1.55..+2.56% triggered one fixed
4pair confirmation; all208timed samples retained. Six cold tick life pairs now +0.98..+2.56%,
median +1.71%(~0.8ms), call+0.12%. Reset timing explains most of this observed cost; do not
claim a CPU cause from unchanged source paths. First-use frame/plan costs remain explicit.
Keep this startup benefit on the local learning branch; no uniform-win or production claim.
8native/8ASan groups,4320new branch cases plus stronger10560entry quota CPU checks,6fresh
image pairs,208timed/4negative controls and stable seals all pass.

## Trial8 — complete charged register/branch shapes

Separate full-state block trace at34bf60be observes dominant init shapes[200,139,82]21,304,033,
[151,152,173]21,303,767 and[131,88]21,295,001visits. All diagnostic clocks excluded. These
are independently decoded shapes, never input hashes/immediate values or skipped guest work.

Try cold headers that preserve original dispatch until the terminal branch positively caches
both arms. Then use a charged whole-shape worker with shared reservation/arithmetic/branch
equations. Preserve all original nodes/layout; failed prices and other shapes unchanged.
Partial quotas always use original handlers/barriers, before any fused arithmetic. No recursive
block handoffs, native code generation or unchecked memory. Refactor charge prefix once into
inline flatReserve, shared by original and new headers. Focused entry checks pass:4320existing
branch cases gain bounded warm-before-quota runs;3888new three-op cases exercise immediate/
register comparisons, aliases, signed bits, gas, both arms and invalid targets.

Trial8 verdict: reject composition lowering.200timed/4negative and8native/8ASan groups
pass; repeated images/source seals stable. Init reused -0.99%, but tick+3.53%, Pinky+2.07%,
Minimal+2.48%. Actual ARM64 has BL flatReserve in all3hot shape bodies and BL fused-register
worker in2. Static calls do not prove the CPU cause alone. Restore runtime34bf60be; retain
stronger warm-prefix witnesses and block/profile/count evidence. Next bounded variant expands
the same reservation/compute equations through templates; verify actual call removal before
repeating timing. No native code generation or semantic shortcut.

## Trial9 — template-expanded charged shapes

Parent6e312d89(runtime34bf60be). Keep trial8shape/cold-capability/partial-fallback algorithm,
but expand reservation through a statement template with original early exits. Expand the
shared computeRegisterOperands equation inside charged workers rather than composing large
register procs. Ordinary register workers unchanged. No new payload or guest semantics.
Focused entry matrix passes; actual native call removal is a mandatory gate before timing.

Trial9 verdict: keep expanded charged shapes. All6init reused pairs -3.96..-5.35%, median
-4.96%; cold call -5.29%, reusedlife -4.93%. Small kernel medians within0.35%. Tick call
+0.51%, cold+0.95% remain visible; reset-inclusive tick reused/coldlife -0.07%/+0.11%.
200timed/4negative,8native/8ASan and6fresh equal-image pairs pass; source seals stable.
Actual ARM64 hot shapes and ordinary charge omit reserve/register composed calls. No
executed native instruction/counter claim or uniform-win claim. Public/default untouched.

Next count-only question: do these charged blocks branch directly back to themselves? If so,
a bounded nonrecursive interpreter loop could retain every charge/quota check while avoiding
repeat outer dispatch. Count actual destinations before any runtime change; clocks discarded.

## Trial10 — guarded nonrecursive charged-shape cycle

Separate exact15763254diagnostics:63,902,796hot shapes,0self-targets. Destination source
shape matrix(rows131/200/151; columns131/200/151/other):
[0,0,21295000,0];[21294999,0,0,9032];[0,21303765,0,0]. Gameplay has0hot shapes.
Thus test only the measured131->151->200->131shape cycle. Actual runtime handoffs require
exact positive cached handler equality, never a source-graph guess. All exits/wrong orders
return to ordinary dispatch. Every visited logical block repeats original gas/quota checks;
partial quotas use original nodes. Native stack remains bounded by a while loop, not calls.

Shared step template retains original compute/branch equations. Specialized branch workers
need explicit typed locals before template substitution on this pinned compiler; no compiler
changes. Focused entry matrix passes including8640new cases:all3rotations,wrong-order and
2block exits,fresh/warmedgas and quotas across cycles. Local quota failures now also require
remaining==0 alongside independently stepped full CPU. Ordinary payload/cache/memory unchanged.

Trial10 verdict: keep guarded nonrecursive cycles. Init all6reused pairs -2.45..-3.19%,
median -3.06%; coldcall -2.98%, reusedlife -2.98%. Small kernels within0.29%; tick reused
call -0.03%, life -0.38%. Native/ASan8groups,8640new cycle witnesses,200timed/4negative
and6fresh image pairs pass with stable source seals. Actual ARM64 has no composed
reserve/register/branch calls in the3hot workers; loops are native-stack bounded.
Next diagnose exact closure of the3actual records, not just their opcode-shape identity;
run the prepared kernel block counter separately before choosing a next runtime change.
