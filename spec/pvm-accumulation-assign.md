# Accumulation assign host

## Scope and authority

Implement assign (16), Omega_A, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex
assign row and definitions.tex (CgasA=1818, Cauthqueuesize=80).
Charge 1818 before capturing the 2560 bytes at r8. Invalid memory panics
before validating full-width core r7 (CORE), current assigner (HUH), then
full-width proposed assigner r9 (WHO unless uint32). Success returns OK,
replacing the selected core's ordered 80 hashes and assigner together.
Duplicates and zero hashes are valid. Proposed assigners need not exist.

Current C(2), C(12), typed queues and typed privileges form one immutable
version. Preserve other cores, roles, allowances, initial provenance, yield,
provisions and exceptional checkpoint. Publish both serialized entries in one
complete-map store batch; backend/resource failures expose no successor.
The state API independently checks authority and bounds borrowed inputs.
The prepared core layout and fixed queue length must match protocol parameters;
incoherent profiles refuse locally. Input copy policy remains independent of gas.

Completion witnesses cover gas boundaries, memory/type/authority precedence,
ordered queues, untouched cores and prior owners, handoff, checkpoint selection,
coherent serialized and typed state, component/store limits, backend refusal,
guarded extraction, borrowed-input independence and ARC release.

## Boundaries

Heap specification questions and conflicting bless allowances remain gated in
pvm-heap-memory.md and pvm-accumulation-bless.md. This change does not adopt new
pins or resolve them. Persistent publication and remaining accumulation hosts
remain later work; designate (17) is the next bounded host tranche.

## Local verification (2026-10-19)

Ten affected native suites passed: assign, bless, effects, write, info, provide,
dispatch, outcome, provision integration and machine initialization. Each retained
fresh 1,000-cycle ARC release evidence with unchanged occupied memory. Assign
witnesses include exact gas/deficit edges, full-width IDs/credit, readable RO and
cross-page inputs, panic/CORE/HUH/WHO precedence, handoff and reauthorization,
zero/duplicate/ordered hashes, complete typed/serialized coherence, preserved
roles and full-width allowances, caller input independence, yield/storage
preservation, panic/OOG checkpoint selection, component limits and immediate/delayed
Merklization failure without a successor.

All 111 production semantic checks, 26 runtime extraction refusals, nine privacy
rejections, one nominal core-domain rejection and 42 selected discovery/failure/
native-harness Python tests passed. Pinned parser metadata confirms attached docs
for both new public routines and the three changed public fixture routines.
Inventory, pinned Nim/Rust formatting and whitespace checks passed.

Evidence is retained under `build/pvm-assign/`: native.log and
native-consumers.log, modules.log, guards.log, targeted-results.json, selected
Python logs, inventory.log and format-check.log. These are focused local macOS
results; full verification and exact-head Linux CI remain separate. Tests reused
one prepared native library set while retaining fresh per-suite execution and ARC
checks. The selected batch initially named one integration suite incorrectly;
only the remaining consumers were run after correcting it, preserving passing
results without replaying the earlier suites.

The test envelope now encodes its bounded writable length as E3 and permits a
4 KiB payload; the authored initialization envelope ceiling includes this input.
Production initialization limits and the default one-byte fixture are unchanged.
