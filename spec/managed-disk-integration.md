# Managed disk backend adoption

The maintainer authorized a fresh storage tranche after native stack516 merged, capped at twenty
open stacked PRs. Storage owns `FileRepository`, `DiskStateStore`, managed maintenance and focused
application backend wiring. State #5 continues independent local-ancestry work; shared app additions
must preserve its startup, download and checkpoint trust interfaces.

The first boundary keeps `FileRepository.opened` a scalar lifecycle observation for worker polling.
An explicit managed initializer takes a complete nonzero-generation seed, and explicit managed
open/recovery chooses the layout. Existing single-file entry points and bytes stay unchanged; no
path probing grants migration or checkpoint trust. The facade translates only actual guarded
managed results into its existing error domain. Composite native owners still require explicit
close, reject ARC copies and preserve held immutable views.

Initial completion checks: managed facade lifecycle/publication/retention and 1,000 ARC reopen
cycles, legacy file repository regression and actual composite owner copy rejection. Subsequent
layers add managed DiskStateStore creation/restoration, context/history, maintenance and worker
boundaries before opt-in application wiring. Complete maps, inherited ceilings, exact parent
identity, explicit IO uncertainty and external trust for checkpoint imports remain mandatory.

## Explicit managed state owner

Managed DiskStateStore create/open/recover entry points keep all legacy entry points and ordinary
StateStore APIs intact. Creation builds a complete admitted generation-one seed before creating
the directory. Trusted open still compares independently supplied exact root/generation; normal
local open requires contextual schema and resumes its admitted local head. Application history
binding remains a separate check. Empty context cannot publish a full-state revision.

`compactDiskStateStore` requires the exact public snapshot and explicit roots. It changes the
private physical owner without changing public snapshot identity, root, generation or context;
ordinary commit still fetches the newly selected physical parent internally. Selected usage is
available through the same owner. None of these operations chooses block/finality authority or
runs synchronously inside dispatcher callbacks.

`managed_disk_state_store` checks public identity, retained values, compaction, context, exact trust,
narrow restore policy, inherited explicit zero-write policy and 1,000 composite-owner ARC cycles.

## Recovery boundary evidence

`managed_disk_recovery` exercises the complete state facade with actual torn/modified journal
bytes. It refuses cross-layout/schema opens, wrong exact prefix tokens, complete visible successors
and complete corrupt frames without fallback. An independently authorized tail repair may become
durable before a subsequently narrower map policy refuses restoration; that refusal still releases
the owner. Successful read-only restoration preserves explicit zero-write limits. Already retained
public snapshots remain readable after repair, refused startup and owner close.

## Atomic retained-root bootstrap

Managed creation optionally accepts bounded older snapshots with the same exact StateStore policy.
It admits them in caller order and the selected source last into an independent memory repository,
then publishes one snapshot containing their complete root union and the supplied selected context.
No intermediate bootstrap context or head is ever durable. There are `history.len + 1` admitted
state generations; this ordinal remains independent of block slots and physical epochs. All
history slots count against the root ceiling before graph/export work, including duplicate roots.

`managed_retained_bootstrap` restores an eight-block rolling history and a separated explicit
finalized root from one epoch, compares every complete retained map and checks that the journal
contains only its paired header at creation. Insufficient root capacity refuses before IO. The
fixture's modified seals exercise local capture/history structure, not execution authenticity.

## Canonical managed startup

`initializeManagedDiskChain` collects the same rolling history and separated explicit finality as
the legacy initializer, binds their final generation in the canonical context and publishes one
managed seed. `openManagedDiskChain` applies the same chain/profile/history/full-map binding as
legacy local startup after physical admission. There is no checkpoint-import fallback and no
implicit migration, repair or overwrite. Existing `initializeDiskChain`/`openDiskChain` contracts
remain unchanged. The managed chain suite checks selected context, all retained root identities,
finality, exclusive creation, chain refusal and absence of intermediate bootstrap frames.
