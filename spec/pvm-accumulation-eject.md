# Accumulation eject host

## Scope and authority

Implement eject (22), Omega_J, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex eject row,
accounts.tex footprint and serialization.tex account maps. Base gas is 458.
Charge before reading the full 32-byte hash at r8; unreadable memory panics
without changing r7. Full-width r7 must identify an existing other current
service whose code hash is the caller's E32 service identity, otherwise WHO.
Require items=2, a request at (hash,max(81,octets)-81), and exactly two history
slots with removal strictly before invocation slot minus expunge period;
otherwise HUH. Expunge period is maxLookupAnchorAge+4800. Compare using widened
unsigned addition to implement the mathematical subtraction without underflow.

A valid account has one request and no storage under these footprint conditions;
delete its metadata, that request and the corresponding retained preimage,
credit its entire balance to self and publish at most four writes atomically. Inherited
store write ceilings remain explicit local policy. Reject unrepresentable balance
addition locally as InvalidState, without inventing a guest verdict or wrapping.
Length outside the E4 request domain cannot name a request and returns HUH.
Malformed canonical metadata/history is a local state refusal. Preserve all other
implication fields and initial/exceptional versions through the existing private
successor helper. No mutable backing escapes the guarded public mutation result.

Completion witnesses cover memory/WHO/HUH ordering, full-width identifiers,
E32 caller identity, exact history shape/consumption, strict expiry boundaries,
pre-genesis subtraction, full-width length/balance arithmetic, four-write atomic
removal including retained preimages, current-state readers, repeated eject,
normalization/checkpoints, prior nonempty transfer/provision/yield preservation,
resource/backend refusals, default/failed extraction and fresh ARC release.
Existing specification gates and pins remain unchanged. If the pinned request/
preimage namespaces select one physical key, delete it once without imposing an interim logical-length restriction or changing pins.
Next bounded host: query (23).

## Local verification (2026-10-19)

Nine affected native suites passed: eject, transfer, upgrade, new, provide,
effects, dispatch, outcome and accumulation machine. Every suite retains fresh
1,000-cycle ARC evidence with unchanged occupied memory. Eject covers exact
expiry/gas/deficit boundaries, full-width IDs/amounts/footprints/profile ages,
all request-history shapes, malformed/trailing histories, missing accounts and
maps, exact E32 ownership, readable RO/cross-page hash input, copy/store limits,
no work on OOG, immediate/late hashing refusal, retained nonempty transfer/
provision/yield owners, current transfer lookup, repeated ejection and panic/OOG
checkpoint selection. The default fixture slot remains 128; the optional nominal
header slot permits real invocation-owned age witnesses.

The two changed production modules passed standalone semantic compilation.
Thirty-four runtime extraction refusals, ten privacy rejections, one nominal
eject-target rejection and sixteen inventory/failure Python tests passed. Pinned
parser metadata confirms attached documentation for recordAccumulationEject
and both fixture APIs. Inventory, pinned Nim/Rust formatting and whitespace
checks passed. Evidence is under `build/pvm-eject/`: regression.log, guards.log,
targeted-results.json, effects-semantic.log, dispatch-semantic.log, inventory.log,
Python logs and format-check.log. These are local macOS results; full verification
and exact-head Linux CI remain separate.

Efficiency: reuse of the existing successor helper avoided editing every older
mutation again. Prepared libraries and native/guard drivers were reused; this
localized tranche did not repeat the full production-module sweep. The reused
guard driver also ran unchanged privacy probes; future additions with no layout
change can select only new boundary checks. Existing gates and pins remain
unchanged. Next bounded host: query (23).
