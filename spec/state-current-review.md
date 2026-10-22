# Targeted review under original current parameters

Pins: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Scope is a read-only continuation of
[state current serialization](state-current-state.md).

`reviewCurrentState` accepts only the qualified original current state and explicit review limits.
It derives the economic profile internally from the original full child Parameters, completes
existing hash-free bounded preparation and then executes the frozen targeted predicates. Neither a
caller-supplied economic profile nor an equal-root replacement inventory can enter this adapter.
Success retains both original current serialization and the same-inventory review. Defaults and
failed profile/preparation/execution selections expose only guarded original reasons.

The existing footprint, preimage content/linkage, supervisor and deposit meanings are preserved.
Undercoverage remains a successful economic observation. This is not full state semantic validity,
code availability, upstream full-block STF parity, root discovery, installation, or finality.
Producer-owned complete logical manifests remain a separate gate. No worker, Services, RPC, producer
or storage changes. The canonical ARC host gate applies to creation, copying and retirement of all
source aliases: before enqueue or after collection/join, never merely after cancellation/Done.

Verification covers genuine signed ordinary/disputed/ticketed/epoch complete authored successors,
exact full parameter and inventory identity, four bounded preparation stages, hash-free no-preimage
review, default rejection, ARC retirement and strict runtime/privacy/nominal guards with signed control.

Observed locally: selected native suite and 1,000 ARC cycles passed at 1,693,184 bytes
before/after; seven runtime and nine exact compiler guards plus signed positive control passed.
Inventory and pinned formatting passed with checked ARC/Clang release on macOS ARM64.
