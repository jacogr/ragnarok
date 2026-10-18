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

## Next bounded work

Connect standard accumulation machine entry to the prepared invocation/context boundary, then add
execution outcomes and host effects in bounded slices as the PVM execution interfaces become ready.
