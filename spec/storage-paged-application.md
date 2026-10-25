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

## Explicit interrupted-operation replay

Ordinary startup and publication continue to preserve forensic candidates and staging files.
The full paged facade exposes `retryPagedCommit` only for an independently prepared complete
target snapshot, retained history and exact context. It reconstructs the expected next header
and application envelope from the checked current source and guarded next counters, builds
exact replay bytes within inherited native/replay ceilings, and asks native cleanup to compare
every present candidate/staging prefix before either is removed. Wrong complete target,
history, equal-sized context and zero replay allowance refuse without changing forensic bytes
or CURRENT. There is no directory scan, guessed target, fallback or unbounded retry loop.

Matching candidate/staging cleanup precedes predecessor retirement: after restart, the envelope
can name an already absent old artifact while CURRENT.next still blocks ordinary reclamation.
Explicit replay resolves the matching immediate candidate and staging first, qualifies any
pending old descriptor, then attempts ordinary authoring/publication once. Success adopts the
exact independently supplied target owner; native uncertainty still requires fresh startup.
A late publication failure that already selected the complete new pair is resolved by strict
startup, without automatically committing the same input a second time.

`resumePagedStateInitialization` and `resumePagedDiskStateStore` provide explicit bootstrap
replay against independently supplied complete genesis/import state and the exact initial
context. Existing CURRENT always refuses bootstrap replay. The application exposes this
authority through `--state-paged-resume`, accepted only with enabled state, disk backend and
explicit paged layout. Fresh exclusive initialization is attempted first; only this explicit
mode plus AlreadyExists may invoke bootstrap resume. Trusted import retains its independent
identity/header validation and exact write policy. Wrong imported headers with the same
complete map/root cannot authorize cleanup of a different application context.

For an existing selected database, explicit resume mode waits for an independently prepared
application update before cleanup rather than attempting ordinary predecessor retirement first.
Both legacy and current prepared publication families carry that explicit choice through the
same excluded, joined disk worker; the dispatcher performs no replay IO. Completed core
publication receipts and subsequent retirement receipts retain their existing separate meanings.
An operator can return to ordinary startup after successful recovery. Corrupt selected heads
are not repaired or replaced by this flag.

Checked native tests cover every observed publication write/sync/rename failure ordinal,
strict forensic-preserving reopen, complete target/history/context mismatch and inherited
replay denial, restart with a retired predecessor plus staging, and bootstrap resume/no
selected-head overwrite. Exact-child supervision additionally measures positive completion
controls, stops after each selected successful write/barrier/rename/unlink boundary, verifies
SIGKILL/reap, and requires the corresponding old/new complete state/context pair before
explicit recovery. It covers ordinary publication, replay and bootstrap resume; unrelated
sibling bytes survive. These process controls do not qualify device power loss.

Actual Services tests cover interrupted configured-genesis and independently trusted import
startup, ordinary startup refusal, explicit correct resume, wrong equal-sized imported-header
context refusal, fresh explicit destinations and existing-CURRENT protection. Both genuine
publication worker families exercise explicit replay through collect/join/immediate shutdown.
The historical reconstruction ARC control remains 1,000 cycles at 12,816 -> 12,816 bytes;
this allocation measurement is not a new claim of 1,000 replay or process-kill cycles.

All five final replay suites also pass checked Linux amd64 under Docker emulation:
paged_disk_state_store (including witnessed process crashes), paged_services_startup,
disk_worker, pvm_current_disk_worker and managed_layout_options. The same historical
reconstruction allocation result is 12,816 -> 12,816 bytes over 1,000 cycles. Qualified image:
sha256:fee07467694b2f0e3b5a861a78d7d65584ecc4b2ae58b3eeb041a5fcef7c8da6.
Frozen source hashes and native evidence: build/storage-db5-replay-linux.json. Existing journal
facade regression, separate formatting and all 420 production modules plus peer semantic Smoke
also pass locally. The previously documented macOS PVM preparation-worker baseline is unchanged.

## Trusted light application heads

`LightApplicationHead` owns immutable partial ProofView evidence and at most eight directly
linked sealed-header snapshots. It exposes no complete-map execution snapshot. Its posterior
root comes from an independently captured ApplicationCheckpointIdentity/header trust input;
the sealed header's prior root remains a distinct parent binding. Present, present-empty,
proven absent and unknown/MissingWitness retain their existing ProofView meanings. Explicit
metadata-only initialization knows a root and zero facts.

Capture checks exact bounded canonical header consumption, sealed hash, identity slot and
configured profile. Header core/epoch geometry matches the fixed fetch parameters; the active
author-validator population is selected independently by the caller's chain profile. It is
not inferred from fetch parameters, an author index or partial evidence. Enrichment admits
only genuinely verified matching-root facts under tightened view quotas. Trusted advancement
requires an unchanged parameter profile, strictly greater slot, exact parent hash and the
parent posterior root in the child's prior-state field. It starts a fresh explicitly supplied
proof collection under the successor posterior root and retains a bounded newest-header window.
Old immutable heads and proofs remain independently readable. These structural bindings do
not authenticate consensus, execute a state transition or infer finality.

Local header metadata has one exact schema: `RAGNAROK-LIGHT-HEAD-V1\n`, E2 author-validator
population, E1 nonzero count (at most eight), then repeated 238-byte canonical checkpoint
identity, E4 exact nonempty sealed-header length, and sealed bytes. Each header remains bounded
by the existing 256 KiB trust transport ceiling plus caller per-header/aggregate limits. Output
extents, input fields, aggregate sums and narrowing are checked before copying or allocation.
No raw opaque-context, complete-map or alternate-version fallback is accepted.

Restoration requires an independently supplied current trusted identity/header and matching
partial view. It validates every record's identity checksum, header hash/slot/profile, direct
parent/prior-root links and exact final current identity. Older records are anchored by the
next sealed header; no stored bytes are converted into an operator trust capability. The
header transport API copies private sealed bytes into independent caller buffers only after
full capacity admission. Failed/default results expose no partial head or encoded prefix.

The native suite covers immutable input/output transport, empty evidence, genuine present/
empty/absent facts versus unknown keys, wrong-root or over-budget evidence, profile/population/
slot/parent/prior-root failures, exact context framing and independent trust, bounded rolling
history, strict per-field limits and 1,000 ownership round trips. This is the application head
contract; the light paged owner and usable mode/runtime integration follow in this stack.

The final light_application_head suite passes checked macOS ARM64 and Linux amd64 under
Docker emulation, with 1,000 capture/enrichment/advancement/context ownership cycles at
76,160 -> 76,160 occupied bytes on macOS and 70,288 -> 70,288 on Linux. The existing state_checkpoint_trusted suite also
passes with 1,000 cycles at 3,488 -> 3,488 bytes. Two private owner/result guards, separate
stable formatting and all 421 production modules plus peer semantic Smoke pass locally.
Qualified image: sha256:30e6e2f121c6f9a1f3089f2ae608e6b4b7504b746f121dd1c7dbbb4dc903090c.
Frozen inputs and native evidence: build/storage-db5-light-head-linux.json.

## Light restart lifecycle

Light restart can enumerate the **stored proof-query keys**, rather than guessing keys from a
complete map. `readPagedQueries` authenticates the captured header and every index descriptor
against the admitted manifest with one cumulative, inherited-and-requested minimum work budget.
It checks both initial and final extents. Its opaque `PagedQueryInventory` owns detached keys;
no callback, mutable backing buffer, file descriptor, complete-state root computation or successful
prefix escapes. Before dispatch or allocation, the operation reserves the fixed stream workspace,
256 bytes of metadata, and four key transports (`4 * 31 * queryCount`), checks host/address
arithmetic, and enforces the caller's separate maximum-key limit. Empty valid inventories remain
distinct from default values. Failed native IO poisons its reader; a pure quota refusal does not.

`readAllPagedProofView` requires an independently expected root and separate inventory work limits.
After complete enumeration it uses the existing per-query native extraction and state-layer proof
verification/capture path under independent proof, batch and view limits. Inventory does not imply
complete-map coverage: present-empty, proven absence and an unrecorded missing witness remain
three distinct outcomes. Its output is an ordinary immutable partial `ProofView`.

Light `reclaimExpectedEpoch` accepts independently retained exact previous/current manifests after
restart. It requires the configured chain/schema/caps, an older physical epoch and a non-newer
ordinary sequence. Different-root advancement preserves the ordinary light delta sequence; it
must not inherit the full store's generation-increment rule. Under the writer lease, deletion
checks the exact current selection and pending-candidate absence, acquires an exclusive old pin,
fully validates old proof content/context, fences the current source and inode/name again, then
unlinks and synchronizes the directory. Already-absent expected content still receives a fresh
source fence and directory barrier. The existing captured receipt additionally requires its original
inode, namespace and policy; equal-byte inode replacement remains a refusal for that API. A busy
old reader prevents deletion. Final close uncertainty remains separate from successful unlink
and directory durability. `synchronize` performs actual selected-file and directory barriers;
uncertainty quarantines the writer until explicit close/reopen.

The `storage_paged_restart` suite qualifies cache-disabled/enabled 130-query capture against a
two-entry complete-map oracle, detached key ownership, every observed logical callback failure,
exact and one-short cumulative budgets, pre-dispatch allocation/quota refusal, authenticated page
corruption, strict expected-root materialization, missing witnesses, V1/V2 restart retirement,
foreign pins, equal-byte inode replacement, corrupt old content preservation, every reached native
retirement read/lock/close/sync/unlink failure, and both fresh synchronization barriers. Repeated
inventory and state proof-view capture must release all activation-owned allocations over 1,000
checked ARC cycles. Native evidence is recorded separately for each qualified platform.

Qualification for this increment: the final restart, light context, native lifecycle, compaction,
cleanup and paged proof-view suites pass on checked macOS arm64 and checked Linux amd64 under
Docker emulation. Restart capture/release is stable at 3,552 -> 3,552 occupied bytes over 1,000
cycles on each platform. The inventory privacy rejection, stable pinned formatting and semantic
Smoke for 421 production modules plus the peer entry point pass locally. Linux image:
`sha256:42f20f9303986c59cb0117b3b6ae675b29639667a9eb995f4d35a1ff312b258c`.
Frozen inputs and exact native verdicts: `build/storage-db5-light-restart-linux.json`; local record:
`build/storage-db5-light-restart-local.json`. These are process/IO fault controls, not physical
power-loss qualification.

## Distinct light application paged owner

`LightPagedStore` owns a separate move-only native light writer and a private passive cache of
`LightStorageSnapshot` objects. Each immutable snapshot owns its trusted `LightApplicationHead`,
partial `ProofView`, exact physical manifest and inherited finite policy. It retains no complete
`StateStore`, complete-map commitment calculation or native reader pin. Snapshot/header/proof
reads and prepared-job admission perform no native IO; already retained snapshots remain usable
after publication, quarantine and close. Initialization, strict restart, authoring, publication,
retirement and synchronization belong on startup or the excluded IO owner.

Bootstrap accepts an independently captured trusted head and an explicitly matching native root.
Strict restart requires independent **current** identity/header trust and configured header
geometry before opening the native store. A separately pinned reader must select the writer's
exact manifest. Complete context capture, stored-key enumeration, state-layer proof verification
and strict header-window restoration all succeed before cache adoption; both native owners retire
on every failed startup path. No mode, backend, schema, root or recovery fallback is inferred.

The light envelope is `RAGNAROK-LIGHT-PAGED-CONTEXT-V1\n`, followed by E1 predecessor presence,
E8 inner length, an optional exact 193-byte V2 light manifest, then the strict light-head codec.
Only physical epoch 1/ordinary sequence 0 may omit a predecessor. A successor embeds its immediate
physical predecessor: same-root replacement increments ordinary sequence, while a different-root
advance preserves it. This facade exposes no context-changing compaction. Native context,
inner metadata, retained proof, inventory and total file bounds remain separate. Preparation
preflights complete native geometry, overflow-safe proof/payload sums and a workspace reservation
for context transports, key transports and the largest detached proof before native mutation.

`prepareLightProofMerge` accepts a genuinely verified same-root batch. `prepareLightHeadAdvance`
requires independent successor trust, linked-header validation and an explicit fresh-root view.
Both retain the exact source snapshot incarnation and a private immutable target. Publication
rejects default, foreign and stale jobs before native dispatch. It selects native replacement or
root advance according to the trusted roots, publishes one metadata/proof pair, and adopts the
prepared target only after confirmed usable native success. Native authoring/publication/close
uncertainty quarantines subsequent facade operations until independent reopen; retained old
snapshots remain readable. No failed native candidate is automatically retried or removed.

A separate passive retirement job binds the cache incarnation and exact current/previous
manifests. At most one predecessor may await retirement; the next publication receives explicit
backpressure. Native expected-content retirement confirms old-content absence, then clears the
pending cache flag without changing the adopted application head. Foreign old-reader `Busy`
retains a retryable pending job; other uncertainty quarantines the owner. The durable predecessor
descriptor survives restart even after successful retirement, so a fresh idempotent absence barrier
is required again. Fresh synchronize uses both actual native barriers. Worker/runtime integration
follows this ownership contract; this increment does not itself expose a light CLI mode.

Focused light-owner controls also cover every observed startup read failure, both synchronization
barriers, same-root trusted header advancement, independently tightened query/proof/context/view/
workspace quotas before native dispatch, and fully native-authenticated malformed application
contexts. Raw head bytes, unknown tags, trailing bytes, wrong current trust and a successor without
its predecessor descriptor never grant a usable facade. Publication fault controls cover every
observed write, synchronization, rename and close ordinal and re-admit only a coherent old or new
metadata/proof pair against independent current trust.

Final light-owner qualification: the checked native suite passes on macOS arm64 and Linux amd64
under Docker emulation. Its 1,000 fresh open/restore/prepare/close cycles are stable at
35,696 -> 35,696 occupied bytes on macOS and 30,288 -> 30,288 on Linux. Four owner/snapshot/
prepared-target/result privacy checks, pinned formatting and semantic Smoke for 422 production
modules plus the peer entry point pass locally. Qualified Linux image:
`sha256:6b89bc2a069bb4ea4111d40989ad25f15d1c430e2baf8c202281974a6478655f`.
Frozen inputs and exact native/platform evidence: `build/storage-db5-light-store-verification.json`.

Light facade startup refusal correction: failed initialization/open closes only an actually acquired
native writer. An already-existing bootstrap namespace preserves NativeFailure/FileFailure/AlreadyExists;
a missing open preserves its native file failure. Closing a default unopened writer would instead
return Uninitialized and must never overwrite that original refusal. Repeated initialize followed
by independently trusted strict reopen is covered by the native facade suite.
