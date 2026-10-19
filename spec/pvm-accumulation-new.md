# Accumulation service creation host

## Scope and authority

Implement new (19), Omega_N, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex new row
and eq:newserviceindex, accounts.tex eq:deposits and definitions.tex CgasN=3855.
The preamble defines code hash c and gratis offset f; these are the same aliases
used in the row. Charge 3855 before requiring r8 to fit uint32 and reading the
32-byte code hash at full-width r7. Invalid input panics. Nonzero gratis r11
requires the current manager (HUH); funding failure returns CASH before any
reserved-ID collision can return FULL.

The child has one empty code request (hash, advertised length), no preimages or
storage, two footprint items and 81+length footprint bytes. Its balance equals
its exact minimum balance. Preserve all 64 bits of r9/r10 gas limits and r11
gratis; derive creation time and parent from invocation provenance, with last
accumulation zero. Debit the creator while retaining its own minimum balance.
The current registrar may request a free ID below 65536 using r12, leaving the
allocation cursor unchanged. Other full-width desired values use the current
public cursor and advance by 42 modulo [65536,2^32-256), with bounded check(i).

Version current nextService independently of initial provenance. Publish creator
metadata, child metadata and its request in one atomic complete-map batch, with
the cursor in the same immutable successor. Preserve queues, staging, privileges,
yield, provisions and exceptional checkpoints. State API repeats authority,
funding and collision checks. Local copy/probe/store/backend refusals publish no
successor and never impersonate a guest resource code.

## Allocation and existing boundaries

The pinned check(i) definition consults invocation-start account membership;
retain that projection explicitly when selecting the successor, rather than
silently changing it to current membership. Actual creation also refuses locally
if a supposedly free automatic ID already has a current account: never overwrite
an existing service or fabricate FULL for that invariant failure. Reserved IDs
use current account membership and the current registrar. No fallback allocation
policy or pin update is adopted.

Exact two-limb deposit consumption compares against creator balance plus child
gratis, so even an unencodable mathematical child threshold returns CASH without
overflow or saturation. The existing funding predicate checks the remaining
creator balance. Request-length namespace questions remain parked under the
existing 0.8.0 codec contract; no new reserved-length restriction is invented.
Heap, conflicting bless allowances and signed-gas/provision gates remain unchanged.

Completion witnesses cover gas/input/authority/funding/FULL ordering, full-width
fields and funding arithmetic, automatic/reserved allocation, collisions and
probe limits, versioned cursors/checkpoints, exact metadata/request encoding,
current account consumers, later effects, prior owners, atomic store/backend
refusal, guarded APIs and ARC release. Next bounded host: upgrade (20).

## Local verification (2026-10-19)

Twelve affected native suites passed: new, designate, assign, bless, effects,
write, info, provide, dispatch, outcome, provision integration and machine
initialization. Each retained fresh 1,000-cycle ARC evidence with unchanged
occupied memory. Creation witnesses cover exact funding/CASH boundaries,
full-width deposits/gratis with carries and products, input/gas/authority/FULL
ordering, automatic and registrar allocation, initial/current membership,
collisions/probe exhaustion and public-interval wraparound, repeated creations,
metadata/request footprints, absent storage/preimage, current info/provide,
current-role handoff, preservation through other state effects, panic/OOG
checkpoint selection, inherited write/item policy, immediate/delayed hashing
refusal and unchanged prior owners/cursors.

All 111 production semantic checks, 29 runtime extraction refusals, nine privacy
rejections, two nominal-domain rejections and 42 selected inventory/failure/native
harness Python checks passed. Pinned parser metadata confirms attached docs for
creation/allocation routines, the changed public execution/fixture routines and
all proposed/result/cursor fields. Inventory, pinned Nim/Rust formatting and
whitespace checks passed. Final field-documentation refinements preserve the
same public field types and executable behavior; completed consumer results
were retained.

Evidence remains under `build/pvm-new/`: native.log, modules.log, guards.log,
targeted-results.json, selected Python logs, inventory.log and format-check.log.
These are focused local macOS results, separate from complete verification and
exact-head Linux CI. The maintained native driver and prepared library set were
reused while retaining fresh per-suite execution/output/ARC checks. The new pure
allocation helper is exercised in the creation suite; unrelated bound block
admission setup was not rebuilt merely to exercise that helper.

Authored fixtures now accept initial registrar, three-write capacity and bounded
bootstrap probes. Existing defaults remain two writes/one probe. Automatic host
creation independently requires its explicit serviceProbes ceiling; the omitted
zero default allows no automatic successor probing, while registrar creation
needs no probes. Neither fixture policy changes production store ceilings.

A repeated-work hotspot is mechanical preservation of every field across all
EffectData constructors. A controlled successor helper is a candidate for a
future focused cleanup as additional state mutations are introduced.
