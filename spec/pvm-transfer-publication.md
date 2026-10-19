# Terminal-selected transfer debit publication

## Scope and authority

The next layer implements [completed-round transfer continuation](pvm-transfer-continuation.md).
The publication contract below remains unchanged; its local verification records
retain the prior layer's initial-continuation gate as historical evidence.

GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex `accpar` projects each participant's own final account and
pvm_invocations.tex transfer debits only the invoking service while appending
one deferred transfer. Vectors remain
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`; pins and wire formats are unchanged.

Certify a successful transfer commit as a self-metadata mutation: its source-bound
plan supplies the invoking identity and complete canonical metadata, and commit
writes exactly that one record. Preserve existing self-entry/creation/deletion
proofs and sticky unsupported ancestry. Zero transfers still retain mutation
provenance, even if final metadata equals the source bytes. No root-equality or
whole-map-diff heuristic replaces this proof.

The existing batch checks exact common input/prior owners, unique services,
terminal-selected scope/accounts, slot, account budget and physical-key conflicts.
It copies each participant's own selected record from its credited map. A sibling's
stale view cannot overwrite another debit or incoming credit. Destinations receive
no new outgoing credit in this round; self transfers remain deferred too. Each
selected outgoing transfer remains in its normalized outcome, available to the
bounded collector added in the preceding layer. This does not certify recursive
transfer processing or final block completion.

Completion witnesses cover independent full-map roots for both service orders,
zero/self/duplicate transfers, incoming credit exactly once, checkpoint prefix
selection on panic/OOG/fault and regular selection on hash return, unsupported
ancestry before/after transfer, supported metadata/self-key composition, exact
account budgets, stale/source substitution refusals, early/late backend rollback,
retained owners and 1,000 ARC cycles. Check that continuation still refuses
selected transfers until recursive input/gas integration is implemented.

M1 framing remains complete; full state serialization remains open. Next bounded
work: bind terminal-selected collection to common-source completed rounds and
prepare recursive transfer inputs/gas without discarding outgoing contributions.

## Local verification (2026-10-19)

Seven native suites passed: `pvm_transfer_publication`,
`pvm_accumulation_integration`, `pvm_accumulation_transfer`,
`pvm_account_publication`, `accumulation_batch`, `accumulation_complete_batch`
and `accumulation_transfers`. Each retained fresh 1,000-cycle ARC evidence
with unchanged occupied memory; the expanded publication suite stayed at
674,000 bytes. Its independent complete-map roots include transfer before/after
upgrade, bounded self storage, creation and eligible ejection. A zero-credit
zero-amount transfer still consumes one metadata-write budget.

Thirty-nine effects and fifteen batch runtime extraction checks passed, together
with thirteen privacy rejections. Five downstream modules passed semantic
compilation: execution, outputs, continuation, continuation execution and reentry
execution. The continuation source retains its explicit nonempty-selected-transfer
refusal; this layer does not remove `UnsupportedTransfers`. No admitted-round
native Bandersnatch setup was needed for these focused checks.

Inventory, pinned formatting, local feature links and whitespace checks passed.
Evidence is in `build/pvm-transfer-publication-unit-final.log`,
`build/pvm-transfer-publication-regressions.log`,
`build/pvm-transfer-publication/results.json` and the runner's per-suite logs.
The expanded ejection fixture uses slot 50,000 so its literal expired request
satisfies the lookup-age-plus-4,800-slot maturity requirement; an earlier
immature fixture failure is retained as diagnostic history. Existing passing
consumer checks were retained after the final test-only extension.
These are local macOS results; exact-head Linux CI remains separate. Native
libraries were reused and vendor sources/toolchains/pins remain pristine.
