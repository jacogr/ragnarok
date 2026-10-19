# Accumulation transfer host

## Scope and authority

Implement transfer (21), Omega_T, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex transfer row,
accounts.tex deposits and definitions.tex CgasT=575/Cmemosize=128.
Read the 128-byte memo at full-width r10 before checking full-width destination
r7 (WHO), current destination minimum-transfer gas against r9 (LOW), then the
creator's r8 debit and own funding threshold (CASH). Success appends one ordered
fixed deferred transfer, debits only the creator and returns OK. Destination
credit occurs in a future invocation; self and zero-value transfers are valid.

The fee is 575+t, where t=r9 only for a valid transfer and zero for memory/WHO/
LOW/CASH refusals. Pure validation therefore determines the conditional fee
before charging, including when initial credit is below 575. OOG wins over the
row verdict once that fee is known and retains its exact deficit, original r7,
memory and implication versions. Costs above uint64 and signed-debt limits keep
the existing explicit representation gate. Local copy policy may refuse pure
input capture; outgoing-item/store limits are checked only after funded gas.

Prepare an immutable plan bound to the exact source effects without writes or
hashing. Commit publishes one creator-metadata replacement and the appended
transfer sequence as one successor. A plan cannot be spliced onto another
version; it never credits or changes destination metadata. Preserve all other
metadata/mappings, current allocation cursor, queues, staging, privileges,
provisions, yield, initial provenance and exceptional checkpoint. Normalization
retains the selected outgoing sequence through its existing context handle.

## Bounded work and ownership

Use nominal full-width destination, transfer index, amount, gas and memo domains.
Outgoing capacity is explicit; an omitted zero capacity authorizes no append.
Default/failed plans and results contain no mutable or partial state. Fixed
transfer extraction copies its entire memo; borrowed caller storage never enters
a published owner. Reusing a plan creates independent successors of the same
source, not repeated appends to an ambient mutable state.

A private unpublished successor constructor centralizes preservation of frozen
components. Existing state operations replace only their selected fields before
publishing. This removes the repeated per-operation field-preservation edits
while retaining immutable public snapshots and independent checkpoints.

Completion witnesses cover conditional fee/debt and refusal ordering, full-width
IDs/amounts/gas, exact memos and ordered duplicates, current account consumers,
zero/self transfers, exact funding, destination non-credit, immutable plans,
resource/backend refusals, checkpoint selection, preservation through existing
mutations, guarded APIs and ARC release. Existing specification gates and pins
remain unchanged. Next bounded host: eject (22).

## Local verification (2026-10-19)

Thirteen native suites cover transfer, upgrade, new, designate, assign, bless,
effects, write, info, provide, dispatch, outcome and provision integration. Each
retains fresh 1,000-cycle ARC release evidence with unchanged occupied memory.
Transfer witnesses include a successful full-uint64 balance debit, malformed
current destination metadata, conditional-fee borrowing across 64 bits, exact
signed-debt representation edges and all prior mutations retaining nonempty
outgoing sequences.

All 111 production modules passed semantic compilation because this change adds
an effect field/error alternative and centralizes existing successor construction.
Thirty-three runtime extraction refusals, ten privacy rejections, two nominal
rejections and sixteen selected inventory/failure Python tests passed. Pinned
parser metadata confirms attached public documentation for all three new
transfer routines and the execution capacity parameter. Inventory, pinned
Nim/Rust formatting and whitespace checks passed.

Evidence is retained under `build/pvm-transfer/`: regression.log,
transfer-final.log, modules.log, guards.log, targeted-results.json, inventory.log,
Python logs and format-check.log. These are local macOS checks; complete
verification and exact-head Linux CI remain separate. Prepared libraries and
existing native/guard drivers were reused. The new private successor helper
removes repeated field-preservation edits for future effect additions; the broad
semantic group was justified by this shared layout change. Transfer alone was
rerun after adding its final boundary witnesses. Existing specification gates
and dependency pins remain unchanged. Next bounded host: eject (22).

Efficiency note: the pinned formatter repeatedly indented a standalone private
comment following a variant object's final branch. Attaching that comment to the
next type declaration avoids the repeated formatting pass. Runtime checks were
not repeated for this comment-only adjustment.
