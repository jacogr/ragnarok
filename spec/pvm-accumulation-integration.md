# Accumulation host integration and publication boundaries

## Scope and authority

Master b954efd combines the merged PVM host stack through forget with the state
batch, execution, continuation and reentry certificates. Keep GP 0.8.0
`07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` pinned. This tranche adds native
cross-host/PVM-to-batch integration witnesses, not a generic state-effect merger.

Execute authored request lifecycles and retained-transfer/upgrade mutations
against genuine common-source inputs and prior maps. Check gas and actual guest
terminals, current request/metadata readers, selected checkpoint owners, exact
incoming-credit balances and terminal provision fulfillment. Selected account
mutations without a supported provenance proof remain UnsupportedAccountEffects;
equal map bytes do not replace that proof. The later bounded publication layers
support self metadata/entries, creations, deletions and selected transfer debits. Mutations discarded by an uncheckpointed panic
must permit the supported batch, without publishing their requests or transfers.
Pending provisions at a pre-mutation checkpoint must survive rollback and be
fulfilled exactly once from the supported common-source batch.

Use one shared authored envelope builder and extend existing batch fixtures with
optional copied envelopes and explicit execution policies, retaining all defaults.
No new production API, wire format, runtime policy or dependency is introduced.

[Grow_heap integration](pvm-accumulation-heap.md) now follows the explicitly adopted
merged #533 gas/result ordering and #538 stack reservation with unchanged pins.
Preserve AmbiguousPrivileges, exact
gas-debt representation and parked request-namespace boundaries. Refused plans
must publish no credits, request changes or pending provisions. Test stale prior,
backend refusal, immutable retained sources and fresh 1,000-cycle ARC release.
These are local integration witnesses, not complete Psi_A, block publication,
transfer-aware recursion or whole-STF parity. M1 framing is complete; full state
serialization/accumulation parity remains open.

[Outgoing collection](pvm-outgoing-collection.md) now retains terminal-selected
transfer sequences under independent source, transfer and memo-byte ceilings.
It preserves ordered duplicates and source ownership. [Transfer debit
publication](pvm-transfer-publication.md) now projects only each participant's
selected own record; recursive transfer execution retains its existing gate.

Next bounded work: bind outgoing collection to completed common-source rounds
and prepare recursive transfer inputs/gas. Unsupported account ancestry and
participating-target deletion conflicts retain their existing local gates.

## Remaining boundaries after the merge

| Boundary | Preserved behavior and next prerequisite |
| --- | --- |
| grow_heap (1) | Implemented under the maintainer-adopted merged #533/#538 fixes; see [heap integration](pvm-accumulation-heap.md). |
| Selected account effects | Bounded self metadata/entries, creation/deletion proofs and [transfer debits](pvm-transfer-publication.md) publish through common-source batches. Unsupported ancestry and participating-target deletion conflicts remain gated; equal roots alone do not permit substitution. |
| Transfer-aware recursion | UnsupportedTransfers in report-only continuation; bounded outgoing collection is implemented, while completed-round binding and recursive input/gas integration remain open. |
| Conflicting bless allowances | AmbiguousPrivileges; pinned set-to-dictionary semantics remain unresolved. |
| 32-byte halt return with provisions | Implemented using the adopted [regular X projection](pvm-hash-return-provisions.md); the historical AmbiguousProvisions value is no longer emitted. |
| Negative host-gas debt outside the signed domain | GasRangeExceeded; no truncation or clamping. |
| Request namespace adoption | Preserve the parked 0.8.0 behavior and pending compatible pin review; no interim length bound or alternate format. |

These are distinct from completed M1 framing; none establishes full state
serialization, whole-STF compatibility or production-validator completeness.

## Local verification (2026-10-19)

Local master was fast-forwarded from e210988 to b954efd after confirming all
thirteen native PVM PRs were merged. New work is an ordinary PR from that master;
the merged stack and its branches were preserved without pruning.

Six native suites passed: pvm_accumulation_integration, accumulation_batch,
accumulation_complete_batch, pvm_accumulation_forget,
pvm_accumulation_solicit and pvm_accumulation_dispatch. Each retained fresh
1,000-cycle ARC evidence with unchanged occupied memory. The integration loop
executes a real guest, prepares complete common-source coverage and applies the
supported batch anew each cycle; occupied memory stayed 147,360 bytes.

Three additional direct fixture consumers passed semantic compilation:
accumulation_continuation_inputs, accumulation_continuation_invocation and
accumulation_reentry. Their unrelated bandersnatch native setup was not rebuilt.
Nine Python inventory tests, source-owned inventory validation, pinned formatting
and whitespace checks passed. Pinned parser metadata confirms attached docs for
guestEnvelope, guestProgram, batchFixture and batchExecution. Production source,
native bridges and vendor gitlinks are byte-for-byte unchanged from master, so
existing runtime result/ownership guards and the full production-module sweep
were not repeated. These are focused macOS results; complete Linux CI remains
separate.

Evidence is retained under `build/pvm-integration/`: regression.log,
native-final.log, consumer semantic logs, docs.log, inventory.log,
python-inventory.log and format-check.log. The final integration-only rerun adds
zero-value outgoing transfer coverage while reusing the five unchanged passing
consumer runs. No gate or production behavior was changed.

Efficiency: sharing the existing envelope builder removes another copy of
bytecode framing. Prepared libraries and existing batch fixtures avoided signed
report/native dependency setup. One compile retry came from the generic Nim
skill's doAssert suggestion; this pinned Nimony uses the project's supported
assert contract. A wrapped empty argument list caused non-idempotent formatting;
named call inputs and targeted formatter checks resolved it before final runs.
Use pinned project conventions ahead of generic Nim 2 examples. Next bounded work
is a service-scoped account-effect publication contract and conflict/provenance
proofs; grow_heap remains gated.
