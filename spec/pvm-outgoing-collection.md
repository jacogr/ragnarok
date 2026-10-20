# Terminal-selected outgoing transfer collection

## Scope and authority

GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex equation `accpar` concatenates each selected service's deferred
transfer sequence in service traversal order. The transfer host appends ordered
records; identical records remain separate debits and deferred inputs.

Collect only actual `AccumulationOutcome` owners produced by terminal
normalization. Preserve supplied outcome order and each selected sequence's
append order, including duplicates, zero amounts, self transfers and full-width
gas. Retain the exact outcomes and copy complete fixed transfers. No caller
buffer, alternate X/Y context or count can replace an outcome's selected effects.
The supplied source order is explicit: this helper does not certify unique
service membership, canonical round order or a shared prior state. Repeated
outcomes are charged and collected repeatedly.

Independent source-count, transfer-count and aggregate memo-byte ceilings bound
traversal and storage. Check all owners/counts and native allocation extents
before copying transfers. Memo accounting is exactly 128 bytes per record,
including duplicates. Defaults and failures contain only reasons; copied info,
transfers and retained source access use guarded results and nominal ordinals.
Preparation performs no hashing, state writes, gas summation or destination
credit. Retained outcome provenance outlives caller arrays and this plan.

Completion witnesses: halt/hash return select X; panic/fault/OOG select Y;
checkpoint before a later append retains only the prefix. Cover empty/default
owners, late invalid input, exact/short ceilings, huge indices, ordered duplicates,
opaque memos, full-width gas, source-array replacement, detached sources and
1,000 ARC cycles. Add strict runtime extraction and privacy/nominal guards.

Outgoing account projection and transfer-aware recursion remain separate work;
existing `UnsupportedAccountEffects` and `UnsupportedTransfers` gates remain.
M1 framing is complete; full state serialization remains open. Pins are unchanged.

## Local verification (2026-10-19)

The native `accumulation_transfers` suite passed through the supported runner
with existing prepared pinned libraries. Its fresh 1,000-cycle ARC observation
was 311,376 occupied bytes before and after. Eight strict runtime extraction
checks, three privacy checks and one nominal-index rejection passed. Inventory,
pinned formatting and whitespace checks passed. No existing production consumer
changed; unchanged lower-layer execution/normalization evidence is retained.

Native evidence is in `build/tests/native/selected/accumulation_transfers.log`
and `build/pvm-outgoing-checks.log`; successful runtime/privacy observations are
in `build/pvm-outgoing-guards.log`, and the corrected nominal fixture's result
is in `build/pvm-outgoing-nominal.log` and `build/pvm-outgoing/nominal.json`.
Earlier failed compiler/probe attempts remain diagnostic history. These are
local macOS results; exact-head Linux CI is separate. Prepared dependencies
were reused without running unrelated setup.

Next bounded work: publish only the invoking service's selected transfer debit
with common-source account provenance before admitting transfer-bearing batches.
Then bind the collected transfers into recursive input/gas preparation.
