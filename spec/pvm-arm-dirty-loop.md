# ARM64 guarded dirty-store self-loop

## Scope and authority

This opt-in `pvmArm64Jit` increment starts from master
`7421bef8782cf196d5013c97470b65e5c335d412`. GP 0.8.0 and the existing PVM memory,
gas and source-attempt contracts remain authoritative; pinned PolkaVM is an application
cross-check. The Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, checked release,
ARC and Clang ThinLTO policy is unchanged. X86 lowering is deferred. The implementation does
not select a guest PC and does not change the public backend default.

The only new admission shape is an ordinary charged block containing, in order, register
opcode 198, byte store opcode 120, registers 149/149, and conditional branch 171. All five
source facts must be adjacent in one complete charge span; the branch must have one positively
resolved self-loop arm and one exit arm. The first instruction's destination must differ from
the store address-base register. The existing positive native suffix and checked-prefix
handoff must already be established. Sixty-four observed self-loop backedges within at most
256 completed branch visits justify publication; a cold probe retires to the checked worker.
No other store width, prefix, branch or generic one-block loop is admitted.

## Execution and ownership contract

At every native loop label, whole-source and gas sufficiency checks run without mutation.
Then an invocation-local memory guard computes the store address modulo 2^32 from the current
resident base. It requires the checked protected/top range, a complete writable stack/RW
descriptor, a present bitmap word and an already-set dirty-page bit. A failed guard restores
its live gas, attempt and context registers, exits native execution, and runs the original
charged checked-prefix/store/tail handler for the untouched current iteration. In particular,
the checked store owns clean-page marking, faults, partial reservations, paid-state handling,
source PC and gas-before-partial precedence. The new native path neither sets a dirty bit nor
marks a clean page. If a later dirty-index stack is composed with this change, a set bit must
still imply membership in that stack; first-touch append must precede setting the bit.

Only after all guards pass does native code subtract the exact block gas and five source
attempts, count one complete block, execute opcode 198, write one byte from its then-current
value register, run the positive suffix and branch. A self-loop returns to the top guards,
so a changed address base or a new page is checked again. Every native exit publishes the
thirteen resident registers and the gas/attempt/completed-block context accumulated by prior
whole iterations. The wrapper asserts `consumed attempts == completed blocks * 5`.

Executable code retains sealed scalar source facts and branch destinations only. The fresh
eight-word call context borrows the current frame's private writable descriptors and dirty
bitmap pointer/count for one call. X2 gas, X3 remaining attempts and X17 context are saved in
caller-saved D20–D22 before the guard uses them as scratch; X4–X16 hold guest registers, and
Apple-reserved X18 is not used. `ArenaOwner` keeps its exclusive move/destroy hooks. The new
one-block cache is independent of the useful two/three-block connected-region slot and uses
the ordinary 1023-fragment ceiling, reserving fragment 1024 for that established region.

## Completion checks and measured evidence

The focused ARM witness compares full CPU, gas, remaining attempts, paid state, source PC,
memory bytes/permissions, faults and source accounting to independent `stepOnce` execution.
Its 840 new paid/gas/partial/fault/layout cases include maximum-width gas and budgets. A
two-page first-touch case proves guard rechecks on a changed base; an alias case proves
admission refusal. A published owner is moved through `takeFlatStream` and restored into a
fresh frame with different memory. Foreign-plan restore must refuse without consuming it;
active teardown must release exactly one arena. Normal and forced-refusal builds are required.
The ARM qualifier requires these native receipts, and its Python test rejects missing owner,
nonresident native counts, duplicate receipts and unexpected refusal activity.

Pinned DOOM tick and init must match the independent CPU, complete memory/permissions, source
attempts and ordered host-event fixtures in normal and forced-refusal modes. Public paired
application checks must compare exact source and fixtures to a current-master baseline in both
process orders, with 13 checked samples per role and three warmups excluded. The existing
connected region must retain its init activity. A focused Linux ARM native/microguest/DOOM
cohort against exact current master remains the PR qualification gate; broad CI is not part of
this increment.

The isolated local ARM snapshot passed these functional controls. Public local DOOM tick
candidate/baseline CPU ratios were 0.8071 and 0.8014 in the two orders; init ratios were
0.9949 and 0.9952. Tick native calls fell from 2,003,388 to 1,235,954. Init native
publications, calls, operations and branch/header calls matched baseline exactly. These are
local results; Linux CI and the composed dirty-index stack are not yet qualified. Complete
local receipt and raw logs are under ignored `build/ci/dirty-store-region-prototype/`.

## Limitations and next bounded work

The earlier generic one-block ARM trial regressed DOOM init by 64–65% after taking the single
connected-region slot; it remains rejected. Two isolated native store/suffix variants also
regressed DOOM tick locally and remain rejected. This specialized connected loop keeps both
negative verdicts separate. It does not accelerate clean-page first touches, malformed or
fragmented stores, priced/paid/partial entries, or any other opcode shape; those retain the
checked path. Qualify the exact Linux head before claiming an application gain, and requalify
the actual composition if the dirty-index stack merges before this PR completes.

## Follow-on four-byte native groups

The checked word-loop layer at `59dfedfd2115d449ede9c642dd51f97e520e3726` supplies the
sealed five-role proof. The ARM native loop can group four original byte iterations when its
branch has the self-loop on the unequal arm, all role registers are distinct, twenty source
attempts and four charges remain, the shift is a multiple of 32, and the full-width base
can advance four times without wrapping or meeting the bound early. The effective 32-bit
address must be aligned, inside one writable descriptor and page, and already dirty. All
conditions are checked on the current invocation before writing. A failed word preflight
continues in the original native byte loop; its existing checked fallback still handles a
failed byte preflight. A successful group writes the low 32 source bits in little-endian
order, publishes the final byte register, advances base by four and shift by 32, subtracts
four original charges and twenty attempts, and counts four completed blocks. The native
cache retains only sealed role coordinates and a cumulative group count, never frame or
memory pointers.

On macOS ARM64 with the pinned checked-release ARC/Clang ThinLTO profile, the composed
`59df...` baseline and native candidate passed a 1,616-case independent single-step
private witness, existing native and forced-refusal witnesses, and complete-state public
DOOM controls. The native witness observed five groups after first touch and checked owner
move, reuse and teardown. Replacing only the generated four-byte store with a NOP made the
full-state byte comparison fail. Five paired 13-sample DOOM tick CPU ratios were 0.91229,
0.91655, 0.91279, 0.91149 and 0.91263 (median 0.91263); the direct stream executed
255,728 word groups. Init had zero groups and median ratio 1.0021. Three paired microguest
controls had zero groups and matching native code bytes/counters: Pinky median 0.9960,
long sieve 1.0102 and minimal-100000 1.0168. Those last two are preliminary upward costs
for Linux qualification, not accepted as neutral. The minimal-1000 timings were too short
and noisy for a verdict. Local logs and source identities are retained under ignored
`build/ci/arm-word-batch-prototype/`; exact-head Linux ARM qualification remains pending.

The combined word-loop qualification retains a maintained698-case gas/partial/fault/shift/bound
matrix and110 role-alias declines in the actual ARM performance witness, not only its ignored
initial proof. An aligned cross-page case requires a real committed native word group before
a later byte fault. See [the shared projection proof](pvm-checked-word-loop.md).
