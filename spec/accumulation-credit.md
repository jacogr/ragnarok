# Incoming accumulation transfer credit

## Authority and scope

Gray Paper 0.8.0, commit `07f041dabd073f9018b418e9ee72e79dd2185401`,
`overview.tex` balance domain, `accumulation.tex` single-service input filtering, and
`pvm_invocations.tex` `Psi_A`/`I` define this bounded slice. Existing authority pins remain unchanged.

Credit the selected service's incoming transfers before either the code-unavailable outcome or
initial execution-context construction. Preserve filtered transfer order, all other account fields,
and every unrelated serialized entry. Bootstrap arguments count transfers plus operands. Outgoing
transfers, checkpoint/host execution, recursive rounds and block-wide publication remain future work.
The current authenticated initial round has no incoming transfers; explicit pure input planning is
not proof that transfers were produced by a previous execution round.

Balances are naturals below `2^64`. The specification uses ordinary addition here, with no modulo
or saturation rule. Refuse an out-of-domain aggregate with a typed preparation error before writing;
this is defensive validation of explicit inputs, not a new consensus overflow transition.

## Ownership and completion tests

Preparation will retain both original and credited complete-map snapshots. A store fork must retain
its originating complete map and resource ceilings, sharing immutable owners only. Failed hashes,
limits or additions publish no credited service. Repeated extraction/bootstrap/skip must not apply
credit again; caller source stores remain unchanged.

Native completion tests will compare literal independent metadata bytes and full-map roots, cover
multiple destinations and transfer ordering, zero/exact-maximum/overflow amounts, all code gates,
bootstrap input counts and both initial context dimensions. Include backend/resource rollback,
source/child retention, store-fork limit inheritance, selected-result guards and ARC release.
Published vectors will be used only for projections their inputs/outputs actually expose; no claim
of full accumulation STF or PVM execution will be made.

## Implemented contract and evidence

`prepareAccumulationService` filters through its immutable prepared input group and proves each
amount fits before adding. It replaces only the selected C(255, service) metadata on a private
`forkStateStore` branch. Forks inherit the complete source map and its write/trie ceilings, including
across later publications; no public policy override or partial-map reconstruction is accepted.
`BalanceOverflow`, backend and resource refusals carry no service payload. Zero aggregate credit
retains the original snapshot and requires no write allowance or additional hashing.

`servicePriorState` retains the source; `serviceState` and copied account metadata expose credited
state. Code lookup still uses the source code hash/preimage. Skip outcomes retain credit with zero
gas and no outgoing effects; ready-code bootstrap counts both input kinds and both initial `I`
dimensions observe matching credited self/account backing. Reusing these immutable handles never
credits twice. Supplying a credited snapshot as a new explicit invocation is a new invocation, not
an exactly-once replay certificate; future recursive-round orchestration must own that boundary.

Native `test_accumulation_credit.nim` compares independent fixed metadata bytes and complete
embedding-map roots for 36 deterministic authored cases and two published balance projections.
`test_accumulation_context.nim` checks paired initial dimensions and mixed transfers/report operands.
Existing store tests cover historical forks, independent publication and inherited refusal policy.
The strict runtime suites add default pre-credit extraction and failed-fork extraction probes.

Published `transfer_for_live_service-1` tiny/full JSON blobs are hash-pinned at existing vector
revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`. The test reads literal recipient/amount fields
from that scenario's bootstrap-service command bytes and checks the independently published
recipient balance `227714 -> 227814`. This is a balance projection: it does not execute the command,
model sender debits or reproduce the vector's storage/timestamp effects. Metadata outside balance
is retained from the source; full-map roots belong to authored two-entry embeddings, not published
complete JAM roots. Pin-checked Python prepares independent transport only; native tests own behavior.

## Local verification

The affected run used
`make check-inventory format-check check-modules check-unit check-failures check-guards check-python`.
All 99 source modules, 113 native suites, 41 corpora and runtime/compiler checks passed. Python
initially found the store harness's old nine-probe expectation; updating it to include the new tenth
probe and rerunning complete discovery passed 406 tests with three existing skips. The final
focused credit rerun also covers the two long-value payload hashes through the last root hash.
Inventory and formatting were checked again. No production behavior changed after broad native
verification. The credit ARC witness retained 12,048 occupied bytes before and after 1,000 cycles.

Evidence is in `build/accumulation-credit/verification.log`, `final-credit.log`, `final-tooling.log`
and `build/tests/{modules,runtime,failures,guards}/results.json`. The first log retains the corrected
Python harness failure rather than claiming that initial command exited successfully. E2E networking
behavior is unchanged and was not rerun locally; Linux CI validates the pushed revision separately.

## Next bounded work

Connect standard accumulation machine entry to the prepared invocation/context boundary, then add
execution outcomes and host effects in bounded slices as the PVM execution interfaces become ready.
