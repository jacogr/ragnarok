# Validator topology projection

Scope: immutable roster membership, advertised endpoint candidates and grid relationships from a
selected complete `BlockSnapshotResult`. Pinned JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`,
`simple.md` grid structure. Caller establishes canonical provenance; structural capture alone does
not establish consensus or finality. This layer does not activate connections or epoch transitions.

Previous/current rosters are C(9)/C(8); next is C(4) pending, never C(7) staging. All chapters must
exist and decode exactly under a matching chain profile and explicit resource ceilings. Copies
are bounded before extraction. Each roster keeps its own population and every ordinal, including
null records and aliases. Null Ed25519 identity 02 followed by 31 zero bytes is not a participant.
Unavailable metadata routing does not remove an authenticated membership.

Within each epoch the grid width is integer floor(sqrt(population)); across epochs equal indices
are neighbours. Aliased identities match any retained position; a node never neighbours itself.
Neighbour queries use bounded linear roster traversal with fixed scratch masks. No mutable roster
storage is exposed, and failed/default results contain only a reason.

Completion checks: `make unit SUITE=jamnp_topology`, exact chapter refusal, C(4)/C(7) separation,
unequal populations, aliases/nulls, independent grid oracle, endpoint availability and snapshot
ownership. Runtime admission, epoch/finality gating and UP0 scheduling remain subsequent work.

Local verification: `make unit SUITE=jamnp_topology` passes with checked ARC/release lowering.
The fixture compares every pair against a separate quadratic oracle for 6/9/12-member grids,
then checks ordinal 1022 and the final partial row of the maximum 1023-member grid.
