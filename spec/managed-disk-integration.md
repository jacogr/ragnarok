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

## Opaque canonical maintenance

`prepareDiskMaintenance` checks that the exact public disk snapshot is canonical, its selected
context equals the encoded canonical history at the admitted generation, and managed usage is
available. It captures only the bounded rolling roots plus explicit finality. The opaque request
binds the snapshot, context, generation and physical epoch. It does not choose finality or touch
files. `commitDiskMaintenance` rechecks every binding before physical compaction; reuse after an
ordinary commit or prior compaction refuses. Default requests grant no operation authority.

The maintenance plan suite provisions an unselected old map, restores the exact canonical context,
then checks reclaimed records, all rolling roots/finality after restart, unchanged public identity,
context/generation preservation and stale generation/epoch refusal. No canonical successor is
installed by physical maintenance. Callers must run IO on the excluded storage worker or startup
owner, keeping all shared ARC aliases stable throughout that lease.

## Single-slot maintenance worker

The existing fixed-address DiskPublicationWorker accepts either an opaque publication or maintenance
request in the same capacity slot. Capacity is checked before touching any possibly leased graph.
Done retains the lease until collection or joined close; maintenance has its own guarded receipt
kind and never grants a canonical publication result. Queued-only shutdown reports NotExecuted;
an entered operation retains its actual maintenance/cleanup/error receipt. The host freezes all
ARC aliases and pauses RPC just as for publication. No second worker thread or cancel-as-rollback
path is introduced. Native tests cover collection, joined completion, shutdown race, cross-operation
Busy refusal, stale tickets and stale maintenance requests, followed by durable history restart.

## Explicit application layout policy

`--state-layout managed` opts an already selected disk backend into the managed directory format;
omission or `journal` preserves the existing single-file default. Layout controls require disk
mode and never trigger path probing or migration. `--state-compact-bytes` is managed-only, defaults
to 64 MiB, accepts explicit zero to disable automatic maintenance and is capped at 128 MiB to leave
journal headroom for a bounded publication. It does not widen write-count/value-byte defaults or
complete-map/physical/file budgets. Invalid, duplicate, unknown and overflowing controls clear the
entire parsed configuration. Full/light node mode remains separate from physical layout selection.

## Opt-in Services startup

Services dispatches disk initialization/open through the explicitly selected layout after deriving
the same configured chain identity. Managed mode uses the same inherited graph, physical-record,
journal and context ceilings, a bounded nine-root union and a bounded snapshot file. Normal local
restart validates canonical context/history; imported startup still creates exclusively and never
falls back to a local head or genesis. An existing wrong-layout path or corrupt CURRENT refuses
without migration, overwrite or older-head fallback. The managed startup suite checks actual
Services create/restart, lock competition, wrong-layout refusal, unchanged corrupt bytes and
successful restart after an explicit test-owned restoration of the exact original manifest.

## Managed checkpoint import trust

The managed checkpoint import suite starts from a separately supplied exact checkpoint identity
and sealed header, creates a fresh managed destination, and compares every imported state entry.
It refuses repeated import into an existing path and missing external trust without selecting the
already valid local database. A subsequent normal local restart resumes that previously admitted
imported head with finality unset. This keeps local durable-head resumption distinct from external
checkpoint authority; physical layout never supplies missing import trust or execution provenance.

## Services maintenance lifecycle

Services pauses RPC, stages an opaque maintenance request in a separate activation, retires all
host temporary aliases, then borrows its stable disk/request fields through the existing native
slot. Every existing publication exclusion gate remains active. Physical completion preserves
canonical/RPC identity and the last ordinary publication receipt; actual maintenance, cleanup,
preparation and worker admission reasons are retained separately. Entered IO is joined on shutdown,
and queued-only shutdown remains explicit NotExecuted. Cleanup refusal does not undo confirmed
selection; it disables further mutation until restart/operator recovery.

Automatic maintenance runs only in the existing confirmed-adoption publication barrier. While its
lease remains active, `accumulationStage` continues to report Publishing, so producers cannot take
the graph-bearing completed adoption early. It does not start spontaneously in an idle download or
preparation phase. Due retained history is instead compacted during synchronous startup before
listeners or worker borrowers exist. A header-only journal never triggers repeated replacement.
Explicit zero disables these automatic paths while retaining the explicit maintenance API.

The Services maintenance suite uses a real RPC listener, observes pause/resume, checks unchanged
public snapshot identity and publication outcome, and verifies retained maintenance receipts across
joined shutdown and strict local restart.

## Genuine execution and automatic policy evidence

`managed_automatic_maintenance` executes the existing signed two-guest fixture against an actual
Services owner, prepares an independent in-memory chain update, then enqueues the certified child
through normal durable publication. A one-byte threshold forces maintenance before acknowledgement;
the publication generation stays two, maintenance changes only the epoch, and every complete state
entry matches the in-memory candidate. Public adoption readiness remains Publishing while either
IO lease is active. Explicit zero suppresses automatic maintenance; enabling the threshold at the
next local restart reclaims during startup before listeners. Both cases retain exact history/maps,
and header-only journals do not repeatedly compact. These are checked local integration witnesses,
not full JAM/STF parity, power-loss simulation or exact-head Linux CI evidence.

## State-owner migration

The explicit source-preserving migration now accepts a managed file facade destination as well as
the original raw managed owner. Both capture the same live legacy chain/schema/revision/context
and root union before destination creation; managed sources are refused as unsupported migration
inputs. DiskStateStore migration forks the exact selected immutable public state, preserving its
inherited policy, while the physical copy preserves generation and selected context. Source and
destination may later publish independent successors. Existing targets never reset, and no step
renames, truncates or rewrites source bytes. The state migration suite checks source-byte equality,
retained historical map access, contextual publication requirements and independent durable forks.

## Explicit migration startup intent

`--state-migrate-from LEGACY_PATH` requires a distinct destination selected with disk/managed mode.
It is unique, never inferred from an existing path and cannot be mixed with external checkpoint
import controls. Missing/duplicate/NUL-containing sources, in-place requests and unselected backend
controls refuse atomically before IO. Failed/default Options expose no migration source authority.

## Explicit application migration

Services validates the local legacy source with the configured chain/profile and full canonical
history before copying its exact generation, selected context and rolling/finality root union.
`--state-migrate-from` always targets an absent managed destination; it never resumes an existing
target, creates a missing source, falls back after source refusal or rewrites source bytes. After
confirmed copy and source retirement, the managed owner becomes canonical. A valid destination
may remain after a later retirement/startup failure; retries never overwrite it. Omit migration
intent for subsequent ordinary managed restarts. Tests compare all state entries, preserve the
legacy bytes, refuse existing targets/corrupt sources and independently reopen both databases.

## Maintenance failure and confirmed progress

Services separately retains actual maintenance preparation, worker admission, IO and cleanup
failures. Joined queued nonexecution is not failure or rollback. The download command reports
`StorageMaintenanceFailure` only after preserving any confirmed installed child count, including
an outstanding child confirmed during joined teardown. An uninstalled/uncertain publication is
never counted. Ordinary memory/journal behavior and network/ancestry contracts stay unchanged.

The failure suite injects a real CURRENT.next exclusive-create collision after genuine child
publication and separately runs a forked writer with a real zero RLIMIT_FSIZE. It checks the
confirmed child remains canonical, exact nested failure reasons, mutation refusal, preserved
CURRENT, explicit no-maintenance restart and kernel retirement of abruptly abandoned locks.
Fork occurs before any parent Services worker starts. No production fault hook or power-loss
claim is introduced. The existing real TLS download-progress consumer remains passing.
