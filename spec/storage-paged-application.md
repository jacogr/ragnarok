# Paged application context and startup

## Authorization and order

The maintainer authorized db #5 on2026-10-24 to continue the remaining paged application
integration, then hardware/filesystem power-loss qualification, then complete JAM serialization,
in at most15 further PRs. This explicitly authorizes the storage/state/application boundary for
this tranche. Preserve existing checkpoint trust, canonical ownership and asynchronous workers;
no partial light mapping may enter complete-map execution APIs. Merged storage-only V1 formats
and the full StateStore/light ProofView SDK consumers remain the baseline.

## Atomic context format

An application selection must authenticate its exact context in the same immutable paged artifact
as its state graph or proof inventory. Publishing CURRENT then selects both together. A second
independently selected sidecar cannot supply application head/history/finality authority. The
context remains opaque to storage; the application validates its existing bounded chain context,
full parameter profile, header/state bindings, retained roots and explicit finality. A locally
checksummed context is not an independently trusted checkpoint import.

V2 uses distinct full/light header and CURRENT labels of the same fixed widths as V1. Header,
index and payload offsets remain unchanged. Full header bytes136..143 and light header
bytes120..127 hold E8 context length. The context starts on the next4096-byte boundary after
payload padding, followed by zero padding to the next page. These physical pages participate in
the existing mode-specific page tree before its postorder digests. The unchanged V1 hash-domain
labels identify the page-hash algorithms; the distinct V2 header bytes and physical page ordinals
bind this format. Full retained-root slots remain at144 with at most64 exact56-byte claims.

V1 has no context section and retains its exact previous bytes and geometry. Context-required
selection is explicit: positive context limit requires V2 with nonzero length within that limit;
zero context limit requires V1. There is no automatic version fallback, format inference or
implicit database migration. Header and CURRENT versions must agree. Dataset bytes include the
entire padded context and tree, independently of the context byte ceiling. Overflow, hostile
lengths and exact/one-short physical ceilings must refuse before allocation or cryptography.

The initial codec layer does not enable native application startup. Unsupported native paths explicitly refuse V2 until their bounded context implementations land;
the following sections record each enabled implementation.
Later native authoring must require exact caller-supplied context, charge its IO/hash work,
authenticate every context byte, preserve it exactly in compaction and bind native replay cleanup
to the whole artifact. Context extraction returns owned bounded bytes, without file/pin aliases.

## Application and completion gates

Full startup restores every context-selected complete root through the existing independent
StateStore reconstruction, then reconstructs canonical history/finality under the configured
chain identity. Publication preserves the host sequence: private successor/context staging,
worker exclusion, native durable receipt, then canonical/RPC installation. Uncertain IO retains
the old in-memory head and requires fresh recovery; bootstrap remains exclusive and forensic.

Light startup has distinct storage and in-memory authority. Trusted root/head selection remains
separate from proof availability. Unknown evidence stays MissingWitness, authenticated absence
stays absent, and no partial ProofView can authorize a full-node transition. Mode, memory/disk
backend and physical layout remain separate choices; incompatible paths refuse without repair.

Required qualification includes independent V2 byte/geometry witnesses, V1 regressions, tampering,
truncation, exact/one-short quotas, owned snapshots, native IO failures, process-death publication
boundaries, unchanged canonical/RPC consumers, explicit startup mode/layout refusal and real
Linux native checks. Hardware/filesystem power-loss evidence requires a named target, actual
power interruption and externally retained before/after oracle; SIGKILL is separate evidence.
Complete JAM serialization remains a later ordered item under the pinned Gray Paper and exact
single-schema interpretation, rather than a claim inferred from transport or M1 framing.

## Observed codec qualification

Pinned checked ARC/Clang release passes the independent V2 context codec suite, including
whole-header/CURRENT byte equations, empty/nonempty graph geometry, context page boundaries,
exact/one-short physical and context ceilings, hostile lengths, malformed empty V2 context,
truncation, V1/V2 mismatch and native callback-dispatch refusal controls.1000 codec cycles retain
192 ->192 occupied bytes. Both original V1 codec suites pass unchanged byte witnesses. Full
build/graph and light streaming regressions pass, including their1000-cycle release controls.
All419 production modules and the peer entry point pass local semantic Smoke; source-owned
inventory and separate stable pinned formatting checks pass. Native V2 context IO and application
startup remain subsequent layers.

## Full native V2 context

FullPagedStreamLimits.contextBytes now selects full V1 at zero or requires full V2 under a finite
positive opaque-context cap. Both ordinary CURRENT and explicit old-epoch readers enforce that
choice before complete graph admission. Bootstrap and replacement require exact stable borrowed
context bytes, validated before candidate acquisition; unsupported bootstrap context refuses before
creating its directory/LOCK. Context and record/graph byte ceilings remain independent.

Construction appends separately padded context before the existing page tree, accounting every
write/hash/read. Complete admission authenticates all physical context pages and checks payload
and context padding independently. Compaction copies authenticated source pages exactly, preserving
opaque context without a resident context-sized buffer, producer or alternate context source.
Header, CURRENT, root union and context are selected by the existing one-file publication barriers.
V1 retains its previous bytes and construction IO schedule.

readContext on a selected reader or writer returns an immutable FullPagedContext. It owns its exact
captured manifest and opaque bytes, with no file, pin or callback alias. The guarded bytes getter
returns detached mutable transport. Per-call work can only tighten captured admission policy.
Extraction preflights a conservative four-context-transport working reservation before allocation,
matching full-value reservation discipline. Failed/default captures expose no partial prefix.
Application interpretation and independent checkpoint trust remain separate.

Candidate cleanup/bootstrap replay receives exact independently supplied replacement context and
reproduces the whole artifact before comparing every present forensic prefix. Source-derived
compaction cleanup accepts no caller context substitution. Reclamation receipts bind all16
admission-policy scalars, including the context cap; a mismatched policy remains InvalidCandidate
under the existing contract. Old-epoch context captures survive native close and reclamation.

The storage_full_paged_context suite passes on macOS ARM64 and Linux amd64 under Docker emulation
with pinned checked ARC/Clang. Independent byte/tree oracles cover context lengths1,31,4095,4096,
4097,65,537 and4,194,304 under cache0/1, retained complete roots, compaction, exact/one-short context/
working/work limits, inherited-budget refusal and detached mutation. Native controls cover all
observed context read and candidate write failures, unchanged CURRENT, unresealed corruption,
resealed noncanonical padding, explicit replay with wrong/correct context, bootstrap resume,
retained old-epoch reopen and exact context-policy reclamation.1000 successful captures plus late
private-prefix IO failures and fresh close/reopen cycles retain83,888 ->83,888 occupied bytes on
both platforms. The private context-backing compiler guard passes. Existing V1 publication,
recovery, old-epoch, compaction and StateStore transport suites pass. All419 production modules
and the peer entry point pass local Smoke, with stable pinned formatting and source inventory.
Light native V2 and application startup remain the next integration layers.

## Light native V2 context

PagedStreamLimits.contextBytes selects V1 at zero or requires V2 under a finite positive cap.
Construction, ordinary readers, replacement and explicit root advancement require that physical
format without inference or fallback. Bootstrap validates context presence and its ceiling before
creating the namespace. Complete admission authenticates all context pages and independently
checks proof payload padding and context padding. V1 bytes and construction IO remain unchanged.

readContext returns an immutable owned PagedContext with its exact captured manifest. Detached
bytes outlive reader retirement and reclamation; no file, pin or callback escapes. Extraction
preflights four context transports plus fixed workspace before allocation and can only tighten
all captured work limits. Context is opaque application metadata; it supplies no additional proof
availability, complete-state authority or external checkpoint trust.

Compaction copies all authenticated source data pages, including context, and preserves ordinary
sequence. Replay of a same-root/same-sequence compaction requires exact proof knowledge and opaque
context equality. Admission folds already visited context leaf digests under a separate local
domain, with charged hash work and constant memory, so even a forensic prefix ending before the
first context page cannot authorize substitution. Independently requested replacements and root
advancements instead bind the caller's exact target context through complete replay and prefix
comparison. Reclamation binds the additional context policy scalar with the existing policies.

The storage_paged_context suite compares independent whole-artifact and CURRENT bytes at context
lengths 1, 31, 4095, 4096, 4097, 65,537 and 4,194,304 with cache zero/one. It covers empty knowledge,
exact/one-short work and working ceilings, inherited-budget refusal, detached getter mutation,
retained readers, root advancement, compaction/replay, corruption and independently recommitted
padding, bootstrap resume, V1/V2 refusal and all observed native context read/candidate write
failure boundaries. The state ProofView bridge retains present-empty, authenticated absence and
MissingWitness distinctions on V2. Checked macOS ARC/Clang passes 1,000 successful capture plus
late private-prefix read failure and fresh close/reopen cycles with 35,504 -> 35,504 occupied bytes.
The same suite passes on Linux amd64 under Docker emulation with the same 35,504 -> 35,504
ARC result. The private backing compiler guard, affected V1 streaming/native/cleanup/compaction,
context codec and state ProofView suites pass. Source inventory, stable pinned formatting and
all 419 production modules plus the peer entry point pass local semantic Smoke. Application
startup and actual device power-loss qualification remain separate completion gates.

## Local complete-map restoration under the writer lease

openLocalFullPagedWriter is an explicit V2-only local restart entry point. Its arguments select
chain, admission/construction limits and replay allowance; it acquires the stable exclusive lease
before reading CURRENT and discovering the local posterior root. Fixed-size metadata is bounded
before access, then the ordinary selection checksum, header/manifest binding, complete graph and
unchanged CURRENT checks all run. The returned storage owner grants no application header,
profile, finality or external checkpoint trust. Application startup must finish those bindings
before publishing a canonical view. openFullPagedWriter retains its independently expected root
contract and remains the entry point for explicitly expected or imported state.

Complete-map entry traversal and root claims can be borrowed synchronously from the writer's
already admitted immutable selected head. This avoids a second admission/pin during local history
restoration. The state SDK reconstructs each complete root under ordinary StateStore limits and
independently recomputes its JAM root. Shared bounded staging and completion checks serve explicit
reader and writer entry points; neither callbacks nor native retirement authority escape. Context
arguments on StateStore initialization/replacement forward exact stable borrowed bytes to native
V2 authoring without changing complete-map transport ownership.

The paged_state_context suite qualifies current and retained complete roots, exact owned snapshot
values, context publication, strict-root rejection after a selected-root change, local restart,
writer lease exclusion, wrong-chain and V1 policy refusal, state quotas, unknown roots, all
observed native reconstruction read failures and closed-owner refusal. Its 1,000 complete-map and
context capture cycles retain 45,632 -> 45,632 occupied bytes with checked macOS ARC/Clang.

The same checked native suite passes on Linux amd64 under Docker emulation, with 1,000 ARC
cycles retaining 45,632 -> 45,632 occupied bytes. Existing StateStore transport, full V2 context
and old-epoch reader regressions pass. Source inventory, separate stable pinned formatting and
419 production modules plus the peer entry point pass local semantic Smoke.

## Complete disk-state facade

DiskStateStore now owns exactly one explicitly selected physical backend, including a full paged
writer and ordinary immutable resident StateStore. Exclusive contextual initialization publishes
current plus independently supplied retained complete roots in one artifact. Local reopening first
admits the complete selected V2 graph under its writer lease, then reconstructs the selected full
map through the independent StateStore commitment check. Application history/profile/header and
checkpoint trust validation remain the caller's following startup step.

Native ordinary generation zero maps to application generation one; every later replacement
advances both once. The facade checks overflow before addition or publication. Commits preserve
exact expected snapshot identity and inherited state policy, stage bounded complete retained maps
and opaque context, then expose the exact target owner only after confirmed native publication
and usable retirement. A failed final directory barrier leaves the old memory owner private;
fresh close/reopen resolves the actual selected old/new state and matching context together.

Context, fresh synchronization and managed-usage queries use DiskIoResult with guarded payloads
and the existing FileError domain. Other facade failures retain exact native or paged-state causes.
Native synchronize confirms fresh selected-file and directory barriers; uncertainty poisons the
writer. Failed construction/initialization retires every acquired descriptor without removing
forensic bytes. Existing retained state snapshots remain usable after close or uncertainty.
Managed maintenance, cleanup and migration explicitly refuse a paged owner; paged reclamation
continues to require its distinct exact receipt/replay contract.

The paged_disk_state_store native suite qualifies exact target-owner adoption, same-snapshot
preconditions, context-required refusal, generation mapping, native lease exclusion, retained
complete roots, local restart and the existing disk-history reconstruction over eight rolling
headers plus an older finalized anchor. It checks byte-identical re-encoded application context,
exact current snapshot ownership, native rename/fresh-barrier/final-directory-barrier uncertainty
and closed-owner retirement. Its 1,000 historical-map/context capture cycles retain
12,480 -> 12,480 occupied bytes with checked macOS ARC/Clang. Source-owned compiler guards reject
private native owner replacement and forged successful IO result payloads.

The existing disk_services_boundaries suite currently terminates on macOS with SIGBUS in the
PVM preparation worker's decodeInstructionMiss stack guard, before disk publication. An isolated
archive of published parent PR #1548 (991a530caf2c534bb2a261314cf93b018be4bd5a), using identical
generated build/UI inputs, pinned compiler, foreign libraries and static fixture, reproduces
the same runtime exit 138. This is a baseline limitation outside the paged storage change; it is
not counted as a passing service regression. Journal disk-state, application history, managed
disk-chain and local paged reconstruction regressions pass.

The full paged disk facade suite also passes on Linux amd64 under Docker emulation, including
nine-root history/finality and early/late durability failures. Its 1,000 ARC cycles retain
12480 -> 12480 occupied bytes. Private compiler guards, source inventory, stable pinned formatting and
419 production modules plus the peer entry point pass local semantic Smoke.

## Full application startup and publication

--state-layout paged is an explicit disk-only full-state layout, independent of memory/disk and
node-mode selection. It retains default journal behavior and rejects managed migration/maintenance
controls. Its finite policy tightens existing dataset/export/context ceilings, permits at most nine
complete roots, and adds independent fixed workspace/scratch and operation ceilings. There is no
implicit migration, format inference or corrupt-selection fallback.

Paged application bootstrap captures the exact current and retained complete snapshots plus the
existing full header/profile/history/finality context, and publishes all of them in one V2 artifact
at application generation one. Ordinary local restart uses exclusive native V2 admission, independent
complete-map reconstruction for each context-selected root, and the existing application history
restoration. Imported checkpoint startup keeps its independent trusted identity/header recovery path
and exclusive destination creation; subsequent local startup restores that imported header rather
than substituting configured genesis. Persistence never infers finality.

Both legacy and current prepared application publication objects carry the exact target view's
retained complete snapshots, excluding its separately supplied current snapshot. The existing
one-slot joined native worker performs actual root-union authoring/publication. The host adopts the
canonical/RPC candidate only after its confirmed usable receipt, with unchanged graph exclusion and
shutdown ownership. No new worker lifecycle or thread-per-operation path is introduced.

A private owned metadata cache keeps dispatcher snapshot, generation and context reads passive.
Context copies are bounded before allocation and detached from caller transport. Startup authenticates
and captures context; confirmed publication updates cache and state together. Actual commit,
historical reconstruction and fresh synchronization remain excluded IO operations with native
source checks. Failed native authoring/publication/barriers quarantine the facade's cache; retained
external immutable snapshots survive. Pure pre-native policy/staging refusal does not adopt a prefix.

Checked macOS native tests pass full paged bootstrap with eight rolling roots and older finality,
profile/chain refusal, actual Services locking/restart/wrong-layout/corrupt-selection refusal,
independently trusted checkpoint import/local restart/no overwrite, and both genuine application
update families through collect/join/immediate-shutdown worker modes. The cache fault control leaves
a native read failure pending through passive metadata reads, then consumes it at the actual commit
fence and exposes RecoveryRequired afterward. The facade's updated 1,000-cycle allocation result
is 12,816 -> 12,816 occupied bytes. Separate stable formatting and all 420 production modules plus
the peer entry point pass semantic Smoke. This evidence does not turn the separately reproduced
macOS PVM preparation-worker stack-guard baseline failure into a passing check.

The full disk facade's native opaque context has an explicit application envelope:
`RAGNAROK-STATE-PAGED-CONTEXT-V1\n`, E1 predecessor tag (zero/one), E8 exact nonempty inner
context length, optional exact 192-byte full V2 predecessor manifest, then the unchanged
application history bytes. Its maximum fixed overhead is 233 bytes, reserved before application
encoding or copying. Generation zero requires no predecessor; each ordinary successor requires
an older physical epoch and exactly the preceding ordinary generation. Source chain, manifest
checksum and geometry are checked before retaining that descriptor. There is no raw opaque-context
fallback. The descriptor identifies an independently expected retirement target; actual deletion
still requires complete old-artifact admission, identity/pin checks and the current writer lease.
Independent tests compare native envelope bytes against literal framing plus captured old CURRENT,
and reject authenticated-but-malformed magic, tags, huge lengths, trailing bytes and storage-only
opaque context without mutating the selected namespace.

The same final-envelope tree passes all six scoped Linux amd64 suites under Docker emulation:
paged_disk_state_store, paged_disk_chain, paged_services_startup, disk_worker,
pvm_current_disk_worker and managed_layout_options. Linux allocation evidence is also
1,000 cycles at 12,816 -> 12,816 occupied bytes. The preserved qualified image is
sha256:49fe620c081b9d0fc090f70b27bc54758c7cc3bd6a34268d36167b4e5bc525f4;
its source hashes and native evidence are recorded under build/storage-db5-app-full-linux.json.
These are process/filesystem checks, not physical power-loss qualification.

## Bounded application predecessor retirement

The full paged facade reconstructs one pending predecessor from the authenticated application
envelope on local startup. A prepared retirement job contains private passive current/previous
manifest metadata and an incarnation identity; it owns no native pin or writer lease. Default,
foreign, stale-generation and reopened-incarnation jobs cannot authorize IO. Reusing an old job
after a newer publication refuses passively without quarantining that valid newer source.

After confirmed publication the facade admits no further artifact authoring until that predecessor
is retired. The selected root union still contains every retained complete historical map.
Normal authored storage therefore has at most the current artifact and its one pending predecessor;
failed forensic candidates require the separate explicit recovery contract. Unrelated foreign
namespace contents are never swept or included in an authored-file bound.

Retirement uses the existing capacity-one excluded disk worker, with an explicit fourth operation
and guarded `Retired` completion carrying the actual DiskStoreResult[FullPagedReclamation].
Collection and joined Done shutdown move that exact result; only queued shutdown may report
NotExecuted. Every new borrowed pointer and result participates in start/reset/collect/close/move/
destruction ownership. Native and canonical/RPC graph aliases remain excluded until collection
or joined shutdown, and retirement never grants an ordinary publication or adoption receipt.

Services gives pending retirement priority before staging another paged publication. Busy from a
foreign old reader retains the descriptor and backpressures authoring, with automatic retries at
most once per monotonic second. Explicit retry uses the same slot. Resident application snapshots
hold no old native pin. Other cleanup uncertainty stops future writes until a fresh startup, while
the confirmed canonical identity and independent memory snapshots remain available after the
lease ends. Cleanup receipts remain separate from completed core publication receipts.

Checked native tests cover passive backpressure/stale jobs, collect/join/immediate close across
success/Busy/IO failure, continued historical reconstruction after actual predecessor removal,
and real Services restart/automatic cleanup/foreign-pin retry/IO refusal/joined shutdown without
changing CURRENT or canonical identity. Both genuine legacy and current publication worker
regressions remain required. The facade's 1,000-cycle ARC evidence remains 12,816 -> 12,816
occupied bytes after predecessor deletion. Two compiler guards reject access to job incarnation
and raw retirement completion payloads.

The existing seven-variable disk lease/join model remains unchanged: its base explores 25 safe
states, all three guard mutants fail, and the uncertain joined-receipt witness is reachable, with
serial/four-worker agreement. It abstracts IO payloads and does not prove format/deletion safety.
The new deterministic completion routing is checked by native tests rather than a larger model.
No new concurrency defect is claimed from this review.

The final application retirement facade/worker suite and actual Services startup/retirement
suite pass checked Linux amd64 under Docker emulation, including the same 1,000-cycle
12,816 -> 12,816 ARC result. Qualified image:
sha256:567bff7089e2ed900cee527b898f2a4172b7518c32934bf18af5ee7ed42be5ff.
Frozen source hashes and native evidence: build/storage-db5-app-retirement-linux.json.
Both genuine publication worker regressions and all 420 production modules plus the peer
semantic entry point pass locally; separate stable formatting and both privacy guards pass.
