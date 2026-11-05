# Source-bound assurance acquisition, retention and distribution

Target JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, shard assignment and CE137/141,
and Gray Paper `fad0ded4a433052397bf7234352a57fe491883f7`, `assurance.tex` and
`reporting_assurance.tex` equations `assurancesig` and the pending-assignment bit rule.
This is one coherent feature layer; its source qualification, durable storage, signing,
network lifecycle, startup policies, tests and documentation belong in the same PR.

An assurance's anchor is the actual selected parent block. Its fixed bitfield is signed as
`ASCII(jam_available) || Blake2b256(anchor || fixed_bitfield)`. No validator ordinal is carried
by CE141. All original roster positions sharing the actual TLS public key must therefore have
verified assigned shards before that identity claims a core. Do not discard repeated keys or
compress null positions. Assignment is `(core * recoveryThreshold + validatorIndex) mod V`,
using the actual greatest-divisor erasure geometry, including valid non-optimal populations.

Acquire only descriptors from complete selected-parent C10 and the actual C8 parent roster.
Registration/evaluation slots, report core, full six-field availability specifier and profile
must agree. Bound whole chapter reads and all planned requests before exposing a plan. Recheck
anchor and complete posterior root before signing or publishing; network replies cannot select
their own expected roots or replace canonical assignments. A cleared/replaced assignment cannot
reuse a previous bit. Cryptographic shard inclusion alone is not a signing capability.

The existing `AvailabilityStore` is a bounded evicting read cache and cannot back assurances.
Durable storage must commit verified bundle and all exported/proof shards, with the exact
specifier/shard identity and retention obligation, before any possession bit is signed. Defaults,
partial/invalid responses, capacity exhaustion, failed writes and visible-but-unsynced writes
must not grant a possession receipt. Preserve existing promises on refusal. Restart must retain
and reverify committed data before it can serve requests or support another signature.

The GP requires exported shards for **28 days**, independent of profile epoch length. The
usual production conversion to 672 one-hour epochs must not shorten Tiny-profile retention.
Bundle shards remain until authenticated audit completion; timeout or disappearance from C10
alone is not audit completion. Retention metadata cannot shorten an existing promise. Safe
pruning must keep both independent obligations and authenticated audit evidence.

The ordinary node uses bounded managed jobs for state, cryptography and storage I/O. Native
callbacks only detach raw frames. Acquisition retries genuine guarantors with exact request
ownership and validates every CE137 component. CE141 has the exact anchor/bitfield/signature
wire form, authenticated validator handling, two-way FIN, bounded duplicate/cancellation and
source refresh. Schedule near two seconds before slots and implement the distinct assurer and
possible-author epoch cutovers from the pinned source; uncertain authority does not justify
inventing a future roster. No file/policy enables this implicitly.

Completion evidence must include genuine canonical assignments and source changes, every local
repeated-key position, non-optimal geometry, corrupted/partial/wrong-root responses, complete
preflight and capacity refusal, real durable restart and I/O failure, 28-day boundaries across
profiles, proof serving after session retirement, exact independent signing/bitfield vectors,
real TLS acquisition and CE141 delivery, epoch timing, cancellation/Done/join ownership and
explicit optional foreground activation. Full JAMNP-S still needs audit/judgment lifecycles and
CE147-to-138 auditor fallback. This feature is in progress and is not yet publishable.

## Assignment qualification evidence

`assurance_duty.nim` now captures complete parent C8/C9/C10/C11 under independent per-chapter
and aggregate read limits. It checks exact chapter consumption, C11/header time agreement,
actual local C8 indices, pending report/core/population/registration consistency and the whole
acquisition-request ceiling before publishing an immutable plan. C9 supplies the independent
prior credential bound for decoding canonical assignments. Null positions remain in the geometry;
every repeated local identity position is retained. A changed anchor or complete posterior root
revokes a previously captured plan, even when the sealed header is unchanged.

The checked native suite passes six-, twelve- and 1023-validator source/coordinate witnesses,
including three repeated local positions and a null predecessor. The twelve-validator threshold
is four, since 2052 is divisible by four; a naive threshold of five gives different coordinates.
It also covers exact/minus-one whole input and request limits, malformed C10 tails, future
registration, population mismatch, absent/invalid coordinates, default policy and non-validator
refusal. Its 1,000 success/late-refusal cycles retain 122128 occupied bytes before and after.
Pinned formatting, verification inventory and all 556 production modules plus the application
entry point pass. These are local source/API results, not native Linux CI.

The erasure sources are genuinely executed. The registration maps in this focused suite are
independently trusted structural fixtures with placeholder guarantee credentials; they do not
establish GP block admission. Genuine admitted assignments, durable possession, signing, CE137/141
runtime and optional activation remain mandatory completion evidence. The feature stays in its
unpublished assurance layer until those parts are implemented and verified.

## Per-shard persistence record

The `RAGAS001` format stores one complete verified CE137 distribution. Records do not require
an archive-sized in-memory table or rewrite unrelated payloads. The forthcoming namespace owner
will enforce chain identity, aggregate disk/count budgets, single-writer exclusion and successful
file/directory synchronization before granting any durable possession. The record codec alone
confers none of those capabilities.

All integers below are fixed little-endian. Hash/key fields retain their complete 32 bytes.

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 8 | Exact ASCII `RAGAS001` |
| 8 | 32 | Independently expected configured chain identity |
| 40 | 104 | Package hash, E4 bundle length, erasure root, E2 shard count, segment root, E2 export count |
| 144 | 2 | Original assigned erasure-shard index |
| 146 | 8 | Promise time in whole seconds since the GP Common Era |
| 154 | 8 | Export retention deadline in the same time domain |
| 162 | 12 | E4 byte lengths of bundle shard, all segment shards and justification |
| 174 | 32 | Blake2b-256 of the preceding 174 metadata bytes |
| 206 | Variable | Exactly the three payloads, in their declared order, with no trailing data |

The deadline is at least 2419200 seconds after the promise time. Arithmetic refuses overflow;
renewal cannot move time backwards or shorten an existing promise. Both bundle and exports stay
in the complete record; the record's existence or deadline alone does not certify that a report
has completed auditing. No timeout or absent pending assignment grants deletion authority.

Directory accounting may check only the fixed header checksum and exact file extent. Before
serving or considering possession, full restore verifies all three CE137 payloads against the
record's precise root/coordinate. A self-rooted persisted descriptor still cannot substitute
for independently canonical metadata: `recordMatches` compares all six fields and the requested
coordinate. Construction detaches incoming verified data; serving extraction returns another
private copy. The signing path must still establish durable publication, fresh duty and every
original local index.

`availabilityVerificationInfo` supplies bounded expected extents and exact real proof work
without granting data or authority. Record restore charges the metadata checksum and all payload
verification before even its first hash. Exact file size, geometry and work deficits refuse
without hashing. The native record suite confirms empty, ordinary and proof-page distributions,
metadata/payload corruption, wrong chain, truncation/trailing data, exact/minus-one aggregate
budgets, actual immediate and delayed backend refusal, recovery, renewal and full-width time
boundaries. The actual primitive call counts match the preflight, and 1000 create/restore/serve/
refusal cycles retain 71344 occupied bytes unchanged.

The duty suite also now uses the actual GP null-validator record (`02` followed by zeros for its
Ed25519 key) and rejects that identity as well as an all-zero key. Its 1000-cycle result remains
122128 bytes unchanged. The existing availability suite passes with 714816 bytes unchanged.
Pinned formatting and verification inventory pass. Actual disk publication, restart I/O,
non-evicting capacity, managed acquisition and CE141 remain in progress; no durable assurance
promise or complete runtime flow is claimed by these record tests.

## Durable per-shard namespace

`AssuranceStore` now owns one explicitly created private directory with 256 lower-case
hexadecimal buckets. Each record is named by its complete erasure root, a fixed four-hex-digit
original shard index and `.shard`; its bucket is the first root octet. Header metadata and file
names must agree exactly. A fixed 72-byte `IDENTITY` contains ASCII `RAGAF001`, the independently
expected 32-byte chain identity and Blake2b-256 of those first 40 bytes. The sibling identity
writer lock remains held until explicit close. Creation never overwrites an existing directory;
opening never recreates missing identity or adopts another schema or chain.

Only count, logical serialized-record bytes, maximum promise time, policy and the owned path/lock
remain resident. Startup walks the complete namespace with public POSIX `DirStream`, preserving
negative error results separately from EOF. It checks fixed record headers and exact regular-file
sizes without retaining or reading all payloads. Missing buckets, symlinks, unknown entries and
incomplete scans cannot become a valid empty history. Separate scan-work admission includes the
fixed namespace, configured record capacity and an interrupted writer sibling. Only exact regular
unpublished atomic siblings may be reclaimed; cleanup synchronizes their directory. Startup
refusal preserves published records and releases the writer lease.

Creation synchronizes each new bucket, the identity file/root and the root's parent. New records
are precharged against count and serialized-byte capacity before copying or encoding; no old
promise is evicted. Duplicate coordinates must retain all six exact specifier fields and are
fully restored before renewal. Successful atomic file publication includes file and bucket sync
before updating counters or exposing `StoredAssuranceShard`. Data-sync refusal before publication
preserves the previous usable prefix. Visible-but-unsynced publication faults the owner and bars
all new receipts/publication until close and verified reopen. Full restored record verification
and another actual file/parent synchronization precede a restored receipt. Failed restore cannot
bypass the fault gate. Header accounting alone grants no possession or signing authority.

`AssuranceStore` has its own unavailable copy/dup hooks and explicit closed-only destruction/move
contract, delegating its writer and owned string hooks. Callers must retire any managed I/O borrow
before close. A retained data receipt owns detached immutable bytes and exposes only fixed
metadata or another private serving copy; the namespace keeps no shared payload cache. Actual
ARC/Clang lowering rejects duplication of the composite itself, independent of its child's hooks.
This registered guard protects single-writer exclusion and consistent capacity/promise clocks.

The native store suite passes real creation, contention, close/reopen, exact byte accounting,
count/byte refusal, same-root metadata conflict, monotonically extended promises, preserved
restart clock, wrong-chain/no-overwrite checks, header/payload corruption and bounded cleanup.
The existing OS observer injects actual file-sync and directory-sync failures without replacing
protocol or persistence logic. Both ordinary and visible-but-unsynced cases retain their distinct
outcomes, and actual restore synchronization refusal cannot return a receipt.

A separately supervised child baseline reaches both real publication sync barriers. Witnessed
stops followed by SIGKILL and exact reap after data-file sync and after directory sync preserve
the original committed record. The former leaves only an unpublished sibling, which startup
removes; the latter leaves a complete visible record that is fully verified and synchronized
before use. These are process-death and successful-OS-barrier witnesses, not a simulated error
or a claim of independently tested physical power loss. A whole-scan cap and a missing bucket
also refuse without accepting a prefix or losing the old record. The expanded 1000 real
read/proof/sync/serving cycles retain 14848 occupied bytes before and after in the selected native
profile. Formatting, inventory and the observed composite ARC rejection pass.

Managed I/O cancellation/startup scheduling, source-fresh possession and private signing,
CE137 acquisition, CE141 handling/timing and optional foreground activation remain in progress.
Large histories must not move an archive-sized graph into memory or perform scans in a native
callback; the worker integration must qualify bounded/cancellable scan progress and shutdown.
Safe pruning still needs authenticated audit completion plus the independent export deadline;
this store currently retains complete records conservatively and never infers audit completion
from timeout or disappearance from C10.

Final local qualification of this file-owner increment also passes the complete store suite
under checked ARC/Clang thinLTO, including the witnessed child deaths, real sync failures and
1000-cycle release (14848 bytes unchanged). All 558 production modules and the application entry
point pass semantic compilation. The ordinary registered ownership-guard build rejects the
actual composite duplication at ARC lowering. These are scoped local results, not native Linux
CI, managed-worker integration or complete assurance-runtime evidence.


## Managed namespace ownership and cancellation

`app/proof/assurance_storage.nim` captures only an explicit create/open operation, bounded
independently owned path, expected full chain identity, policy and borrowed fixed-address
namespace. Capture performs no filesystem work. Its staging helper retires capture wrappers and
path aliases before `StateProofWorker.submit` moves the job into the existing single bounded
slot. There is no arbitrary queued I/O callback. The synchronous scan receives a non-owning,
non-raising cancellation view of the live worker; that view is never retained in a job or store.

Existing-namespace accounting polls before directory/entry work and before publishing opened
state. Cancellation refuses without accepting a scanned prefix or deleting published records.
Fresh creation completes its fixed 256-bucket/identity initialization before scanning, so
cancellation does not deliberately strand half of that fixed initialization. Individual OS
operations retain their existing blocking semantics; this is cooperative cancellation between
bounded operations, not preemption of an OS call. The worker releases its mutex before execution
and before joining, allowing the scan to observe cancellation/stopping without a lock-held join.

Queued, Running and Done all retain capacity and the entire mutable namespace borrow until exact
collection or joined close. Neither cancellation nor observing Done permits host access to store
fields. A cancelled already-completed open cannot undo its native descriptor side effects; the
host must explicitly close that owner after collection/join, even though the cancelled completion
exposes no result payload. A foreign/stale ticket cannot collect, cancel or release this lease.

Services now owns that stable namespace and delegates its native destruction/move hooks. Explicit
`beginAssuranceStorage` derives the complete original genesis hash from the already captured
configuration; callers cannot choose a chain identity or substitute a current best head. Full
state, idle shared capacity and the exact RPC pause token are required. Default/ordinary startup
opens no assurance namespace. Light mode cannot admit this complete-state work. Only successful
exact collection publishes host-owned cached counts/bytes; status polling never reads fields of
the store being mutated on the worker. Cancelled/failed collection and joined startup stop close
the actual namespace before resuming RPC. Unrelated idle proof stop preserves installed storage;
Services shutdown joins before closing its native gate. No public namespace alias escapes.

The selected native worker suite uses 1023 genuine independently verified shard records and
byte-limited real reads. It observes Running, rejects foreign cancellation/collection, confirms
scan cancellation stops before all headers are read, distinguishes completed-open cancellation,
and joins during a live scan before restarting. Disabling the actual polling hook makes the
suite fail its first cancelled-archive early-stop/closed-owner assertion; restoring the exact
source passes. Its 1000 moved-job/failure/Done-cancellation cycles retain 720 occupied bytes.
The genuine complete-state Services suite checks actual independent lock contention/release,
canonical/RPC exclusion through Done, stale-ticket refusal, completed cancellation cleanup,
uncollected Done join, close/restart and 1000 alternating I/O-failure/cancellation cycles with
8848224 occupied bytes unchanged. These local witnesses establish managed namespace lifetime,
not source-fresh possession, signing, network acquisition/delivery or complete validator startup.


The scan policy now requires enough work for the entire configured record capacity, all 258
fixed namespace names and one interrupted writer sibling before any filesystem admission.
An undersized policy previously allowed fresh creation but could refuse reopening the same
namespace at its promised capacity. The native regression first reproduces that admission;
the corrected boundary rejects one-work-unit deficits and the uint32 maximum-count/overhead
case before creating a namespace. The same path then creates successfully with the exact
minimum budget. Extra unexpected debris remains bounded by the existing whole-scan refusal.


Final qualification of the managed namespace increment passes both selected native suites,
the existing proof-worker/Services/consecutive-download lease consumers, the exact registered
Services ARC duplication rejection, and the real Services lifecycle under checked ARC/Clang
thinLTO (1000 cycles, 8847040 bytes unchanged). After the scan-policy correction, the selected
store, Services and worker suites pass again. The corrected complete store suite also passes
checked ARC/Clang thinLTO, including real sync faults, supervised process deaths, scan-cap
boundaries and 1000 release cycles (14864 bytes unchanged). The Services owner/callback ABI
is unchanged by that pure policy predicate correction. These are local macOS results; no native
Linux CI or full assurance signing/network/startup completion is claimed.

Pinned formatting (2416 Nim sources and Rust), verification inventory and the complete final
source graph (559 production modules plus the actual application entry point) pass after the
policy correction. The assurance layer remains unpublished until its full scoped feature is ready.


## Canonical acquired-shard retention work

The next managed operation binds a complete selected source, configured full chain identity,
local parent-roster identity and original local ordinal/core to one detached CE137 response.
The worker derives the expected six-field descriptor and exact assigned shard from fresh C8/C10
qualification. Three exact E4-framed extents, full payload geometry, suffix absence, incoming
proof work and aggregate raw/verification/duplicate-restore/encoding buffer bounds precede
verification. Aggregate transfer workspace reserves raw wire plus four payload copies and two
record headers; canonical chapter reads and store-internal record work retain independent caps.
Only successful actual synchronized retention returns fixed progress facts. The result is not
signing authority: final possession/signing must requalify source and re-open/verify every required
local stored shard. Cancellation may leave correctly retained data but cannot expose a completed
acquisition result or a possession bit. Tests must use genuinely computed and admitted pending
reports, verify raw-owner independence, empty exports, exact/malformed frames, wrong coordinates,
workspace/hash deficits, chain mismatch, real sync faults, native Done/cancel/join and ARC release.


The canonical acquisition operation is now connected to the ordinary `StateProofWorker` and
Services. Admission stages only detached raw bytes and the actual best complete source; all
capture/source aliases retire before moved submission. The worker derives duty/coordinates,
checks the namespace's full independently configured chain identity, validates all three message
extents and verifies the complete transfer before `rememberAssuranceShard` crosses actual file
and directory barriers. The completion owns only fixed duty/record progress metadata. No raw
received specifier, peer-selected source, mutable archive alias or signing capability escapes.

Services keeps opened/faulted/count/byte/chain observations in a separate host-owned cache.
Queued/Running/Done and cancellation retain the global canonical/RPC lease. Only exact collection
or joined stop refreshes actual mutable archive counters and its fault gate. A cancelled completed
write remains retained but exposes no acquisition metadata; acquisition stop preserves the healthy
installed namespace. Failed durability updates fault status without discarding earlier promises.
A faulted namespace refuses subsequent acquisition. Full Services close still joins before native
namespace destruction.

The native acquisition fixture follows original report execution through profile/transition,
roster, guarantor credentials, envelope/batch inclusion, report admission, publication, accumulation
and complete computed-chain advancement. Original erasure data is extracted only through those
sealed provenance getters. Its C10 assignments and credentials are genuinely produced; they are
not manually replaced structural fixtures. The Services component test explicitly configures that
actual complete computed child as its trusted seed. It does not establish network bootstrap or
adoption from a different configured genesis, which remain runtime integration requirements.

Observed checks cover independent raw-owner mutation, literal original-index coordinate, real
retained restore, namespace mismatch, malformed lengths/truncation/suffix, exact/minus-one
aggregate workspace, verifier hash deficits before the first primitive, corrupted bundle data,
actual crypto refusal, cancellation before execution, full 28-day promises and a second genuine
coordinate refused by actual archive capacity. Real data-sync and directory-sync refusal retain
their ordinary/visible-unsynced distinctions, with full verified restart. An injected managed
restore-sync refusal refreshes Services' actual fault gate and bars another acquisition. Native
Done cancellation, stale/foreign collection, joined stop and 1000 actual duplicate read/verify/
renew/encode/sync cycles retain 93504 occupied bytes before and after.

The existing assurance startup-worker, namespace-Services, selected proof-worker and proof-Services
consumer suites pass with the new job family and ownership fields. The ordinary registered Services
copy guard rejects the exact aggregate duplication at ARC lowering. The entire expanded acquisition
suite also passes checked ARC/Clang thinLTO, including genuine source construction, sync faults,
managed lifecycle and 1000 release cycles (93504 bytes unchanged). All 560 production modules and
the actual entry point pass semantic compilation. These are local macOS results, not native Linux
CI or completed CE137 network acquisition, fresh all-local-shard possession/signing, CE141 transport,
clock/epoch cutovers or optional foreground activation. The coherent assurance feature stays
unpublished until those remaining runtime requirements are implemented and verified.

Final formatting (2419 Nim files plus Rust) and source-owned verification inventory (1072 native
suites) pass for this acquisition increment. Supporting source, tests and evidence remain in the
same unpublished assurance feature layer.


## Fresh stored-possession signing work

The signing operation will select only requested canonical pending cores and verify every original
local roster position for each selected core. Missing or metadata-conflicting data clears that
core; hard I/O, verification, resource or durability failure refuses the whole signature. Whole
selected read/write/hash work and maximum per-record workspace must be precharged before the
first record hash. Stored renewal will restore exact data without granting an early receipt,
then atomically extend the full 28-day promise before a private signature is attempted. The
private TLS-matched signer will invoke this check directly in the same managed operation; no
caller-supplied reusable possession flag or arbitrary signing message will be accepted. Expected
coverage includes partial/all-local possession, repeated keys, source changes, real sync refusal,
whole-work deficits before hashing/signing, exact GP transcript/CE141 bytes and cancellation/join.


Fresh stored-possession signing is now implemented. `qualifyStoredAssurance` preflights every
selected core and original local index, including aggregate read/write bytes, actual proof and
metadata hash work, final transcript hash and maximum per-record workspace. Only one record
graph is resident at a time. Missing or metadata-conflicting coordinates clear that entire core;
other fully possessed selected cores remain eligible. Hard storage, verification, resource or
renewal failure refuses the whole signature with its actual selected child reason. Every complete
core requires independently verified and durably renewed bundle/export/proof data for all original
positions sharing the local TLS identity.

`renewAssuranceShard` restores a verified record without constructing an early stored-data receipt.
It atomically republishes the complete record with a monotonic promise of at least 28 days from
the supplied GP Common Era time. Actual file and directory synchronization precede the receipt.
A prepublication refusal preserves the old usable promise; visible uncertain renewal faults the
namespace until verified reopen. Ordinary existing restore still synchronizes before granting a
receipt. This separates proof verification from the persistence capability without retaining an
archive-sized in-memory index or payload cache.

The existing private TLS-matched `WorkSigner` performs fresh qualification directly in the same
closed native operation before its sole assurance signature attempt. It accepts a requested core
selection, never a caller-provided possession flag or arbitrary signing message. The signature
uses the established `jam_available || Blake2b256(anchor || fixed_bits)` constructor. Its opaque
source-free result retains only copied duty/bit facts and the real signature; it retains neither
private key nor stored payload graphs. CE141 encoding checks the current anchor and full posterior
root and emits exactly 32 anchor bytes, ceil(C/8) LSB-first bytes and 64 signature bytes, without
an ordinal. A changed complete map revokes encoding even with an identical sealed header.

Services explicitly imports a separate private assurance signer only after archive setup and
checks it against the actual bound TLS public identity. Ordinary startup still enables neither
archive nor signer. The shared worker freezes source/key/archive aliases through Queued, Running,
Done, cancellation and joined close. Every signing collection refreshes actual archive accounting
and faults, including already completed cancelled renewals. Only its latest uncancelled collected
signature may pass the Services publication gate. Beginning another signing turn, cancellation or
Services close revokes that publication owner. The signature cache holds no key alias, and an old
result cannot revive after restart even when the new signature's deterministic wire bytes, key,
anchor and map are identical. A future network actor must use this gate before sending.

The native signing suite uses genuinely computed/admitted/published pending reports and an actual
TLS certificate/private key for the original roster's known test seed. Independent literal
transcript construction and maintained Ed25519 verification check the exact 97-byte three-core
CE141 body. Observed real signature-attempt counts prove zero attempts for missing shards,
invalid high bits, aggregate deficits, incomplete repeated-key possession and failed sync barriers;
complete success attempts exactly one signature. The test observer's copied attempt counter is
atomic, while fault controls retain their existing quiescent test contract.

A separately labelled independently trusted structural roster variant gives the same real local
key two original positions while preserving the sealed header. It requires both assigned shard
proofs and renewals before signing and proves full-root publication revocation; this variant alone
is not evidence of GP admission. Real data-sync/directory-sync refusal, verified restart, actual
signing-provider failure, foreign/stale collection, Done cancellation, joined cleanup and Services
restart revocation also pass. In particular, identical deterministic wire bytes do not replace
this Services lifetime's actual latest collected signature owner.

Both selected native and checked ARC/Clang thinLTO signing runs pass 1000 complete proof/renewal/
signature/collection cycles with 93488 occupied bytes unchanged. The existing Services aggregate
copy guard rejects exact duplication at ARC lowering. Existing archive, acquisition, assurance
startup worker/Services, proof worker/Services and managed guarantee-signing suites pass after
the renewal/refcount changes. All 562 production modules and the actual entry point compile.
These are local macOS results, not native Linux CI or completion of live CE137/141 transport,
peer validation, pool/inclusion behavior, slot/epoch timing or optional foreground activation.

The final read-budget audit found that a record's own declared extent could exceed the smaller
canonical expected extent. Store restoration now derives its read ceiling from the independently
expected descriptor and request before reading payload bytes. A regular file larger than that
ceiling refuses before the first payload read. After the metadata checksum, restoration compares
all six descriptor fields and the exact shard request before performing any payload proof hashes.
A checksummed descriptor conflict is unavailable possession, rather than permission to verify an
unrelated record. The aggregate signing I/O budget includes the bounded reader's one-byte EOF
probe in addition to its complete read and atomic renewal write.

These regressions observe actual public SDK `read` calls. The pinned stdlib's assembler alias
bypassed the existing C test redirection, so a zero counter previously could not establish zero
reads. The bounded file reader and namespace header reader now bind the maintained public SDK
symbol with its declared ABI. An uncancelled 1023-record startup under one-byte short reads must
observe at least every one of the 206 fixed header bytes per record; the same instrumented path
then proves cancellation stops before a whole scan. The signing test independently reproduces
an oversized archive refusal before any payload read, and a same-size checksummed canonical
metadata conflict after only its metadata hash and before any payload proof or Ed25519 attempt.
The original record is restored before reporting the corruption-test result. These checks use
real filesystem I/O and production restoration; no replacement protocol or storage path supplies
the verdict.

## Managed CE141 receipt and bounded candidates

The ordinary read transport now recognizes CE141 as one E4-framed upload of 97–139 bytes,
followed by the sender's FIN and a bare receiver FIN. The selected profile determines the exact
bitfield width during verification. The separately optional selector stays disabled by default;
activating CE135 does not activate it. Both endpoints must have actual validator transport roles.
Native callbacks only retain bounded detached raw bytes. Neither a response body nor a validator
ordinal is accepted as part of this exchange.

`qualifyAssuranceDistribution` checks the exact selected-parent anchor, complete source, unused
tail bits, actual authenticated peer's C8 membership and current pending assignments before the
single real Ed25519 verification. It retains every original C8 position sharing that key, including
null gaps. Its private source-free result exposes independent GP assurance candidates with those
original indices. It grants no block-inclusion authority: a block builder must still sort indices,
exclude duplicates and validate every signed bit against its actual post-judgment assignments.
A signature's bitfield cannot be altered to remove a subsequently invalid core.

The closed managed receipt operation reuses the existing bounded worker slot. Services stages
and retires source/capture aliases before moved submission and keeps canonical/RPC exclusion
through exact collection or joined stop. A synchronized exact-ticket membership check covers
Queued, Running and uncollected Done; a stale/foreign ticket or a later worker generation cannot
be cancelled or joined by this controller. Incoming receipt requires neither local shard storage
nor a private signer. The host obtains the peer key from the actual live native request ticket.

`AssuranceDispatcher` admits one FIN-complete claim under its original native deadline. Only an
uncancelled successful collection, a still-live native claim and a fresh complete-source comparison
allow retention and acknowledgment. Source changes require requalification rather than an old
success stamp. The source-free pool has explicit distinct-key and expanded-original-index caps,
with fixed maximums of 1023 each, so a production quorum of distinct identities can fit. Default capacity is zero. Whole repeated-key
capacity is checked before replacement, same-key updates never append duplicate positions, and
refusal evicts no unrelated candidate. Head or full-root changes remove stale retained candidates
when canonical access is available. Ordinary reads skip dedicated CE135/141 consumers while
weighted admission preserves opportunities for other CPU work.

The native receipt path has passed between two ordinary TLS-authenticated `ApplicationNode`
loops. An actual Services-collected durable-possession signature reaches another independently
decoded instance of the genuinely computed complete parent. This parent is explicitly configured
as the trusted seed; this test does not claim bootstrap/adoption from another genesis. The peers'
real certificates/private keys match their actual parent-roster identities. Default receipt
refuses; an uncollected foreign Done result keeps canonical exclusion while UDP progresses;
matching collection permits fresh retention before the bare-FIN acknowledgment. Repeated valid
uploads stay within one retained identity row; a modified signature cannot replace it. Closing
the receiver preserves another controller's exact worker lease for its owner to retire.

Independent component checks cover wrong anchors, high bits, exact profile-width suffix refusal,
actual bad signatures, default/non-validator keys, original repeated positions and whole-index
capacity refusal. The empty-C10 case is explicitly an independently trusted structural variant,
not a fabricated GP-admitted transition; the genuine computed fixture has all its cores assigned.
Both native signing and receipt cycles preserve 93488 occupied bytes across 1000 cycles. The
shared crypto observer now counts Blake2b attempts atomically for concurrent node/worker use;
delayed fault selection remains quiescent and serial. Protocol verification still calls the
unchanged maintained primitive implementation.

These results establish receipt and candidate retention. Timed automatic outgoing CE141,
network-driven CE137 acquisition/retries, durable post-session shard serving and explicit
foreground assurance policy remain required before publishing this feature layer. Audit-backed
release of retained data and the broader audit/judgment lifecycle remain separate unfinished
parts of the full JAMNP-S objective.

Final receipt qualification also retains 683 distinct genuinely signed candidates from an
explicitly structural 341-core/1023-validator parent. Every candidate is independently verified
against its actual original roster key and a literal zero-bitfield transcript; the test does not
claim actual availability or GP block admission for that structural source. A 684th valid identity
refuses the configured expanded-index budget without evicting any earlier candidate. The fixed
row ceiling is 1023, supporting a production supermajority rather than an arbitrary 64-peer cap;
ordinary iteration is bounded by the explicitly configured row limit.

A second real TLS run observes the receipt controller's own worker at uncollected Done. Closing
that controller joins its exact borrow, releases canonical exclusion and clears candidate storage
without acknowledging the uncollected result. The sender cannot collect a successful reply. Its
route retires under the existing 30-second idle policy, exercised by advancing the explicit host
monotonic clock and sweeping bounded physical slots. This is a local deadline witness, not a
claim that a disconnected peer observes remote teardown instantaneously.

The complete expanded signing/receipt suite passes checked ARC/Clang thinLTO, including both real
TLS close variants, production-sized candidate capacity, exact durable signing, cancellation and
1000 cycles with 93488 occupied bytes unchanged. Actual ARC lowering rejects duplication of both
Services and the new receipt controller with their exact registered diagnostics. All 565 production
modules plus the actual entry point compile. Formatting and verification inventory pass. The read
client, sharing client, native node service, application node, generic read verification, managed
guarantee exchange and its full TLS runtime pass; application-node and guarantee-runtime consumers
also pass after enlarging the pool. A retained incremental cache still emitted an old 64-entry
initializer after that layout change; a fresh profile build passes without compiler or production
workarounds. These remain local macOS results, not native Linux CI or complete assurance activation.

## Canonical CE137 planning boundary

CE137 request planning must return bounded source-free metadata: exact parent/full-root facts,
all original local positions, canonical pending-core descriptors and the actual two/three
credential positions' validator records. Guarantor keys come from C8 for the guarantee's evaluation
epoch and C9 for the immediately preceding epoch, preserving original indices rather than a
shuffled position or compressed non-null list. Unknown epochs/indices cannot invent a key. Null
records remain unavailable targets; repeated keys may retain distinct routing metadata.

Planned output storage must be charged in full before allocation independently of canonical
chapter/read budgets. Do not allocate the core/local-position Cartesian product; keep per-core
facts and original local positions separately and derive exact coordinates on demand. The
managed plan freezes the actual selected source through matching collection/join and exposes
no canonical graph, private key or possession capability. Completion witnesses include genuinely
computed C10 credentials, exact current/prior-epoch roster selection, null/repeated original
positions, output-budget refusal, source-root revocation, native exact-ticket cancellation and
real FIN-complete CE137 retries before durable acquisition. The planning boundary is now implemented; network acquisition remains in progress.

`AssuranceFetchPlan` now contains only copied source facts, fixed per-core descriptors/guarantor
records and the original local-index vector. Coordinates are derived in O(1) without allocating
one object per core/index pair. A conservative owned-output reservation includes fixed metadata,
actual native row storage, per-row headroom and local-index storage, all checked before output
allocation; the private vectors move into the immutable result. C8/C9 owners stay private inside
canonical qualification and do not escape in the plan. Unknown epochs and out-of-range indices
return their actual selected failures rather than falling back to another roster.

The closed managed planner shares the existing exact worker/canonical/RPC lease. Services
captures its actual best complete source and retires staging aliases before submission. Planning
needs neither an opened namespace nor a private key. The same guarded `AssuranceWorkStart` serves
planning and receipt; shared private input and admission cleanup retain one actual slot through
Done/cancellation. A host must compare the full source again before using the detached plan.

Native witnesses pass genuine computed C10 targets, independent raw C8/C9 lookup, literal
nine-validator/repeated-key coordinates, full-root revocation and exact/minus-one output bounds.
Explicitly structural epoch fixtures distinguish C8 from C9, allow original C9 tail indices that
cannot fit the current roster, and reject both wrong-current-population fallback and older
unknown history. Null targets are skipped without renumbering; repeated keys retain distinct
original routing metadata, and returned copies cannot mutate a plan. These structural fixtures
do not assert changed credentials have GP admission. Native success, late target failure and
completed-cancellation jobs retire all canonical/input/output owners across 1000 cycles with
119168 occupied bytes unchanged. Checked ARC/Clang thinLTO passes the same planner cases and the
complete managed planning/signing/TLS receipt suite (93488 bytes unchanged across 1000 cycles).
The current Services aggregate still rejects exact ARC duplication. All 566 production modules
and the actual entry point compile; formatting and inventory pass. These are local macOS
results. The actual CE137 request/retry actor, durable serving, timed outgoing CE141 and explicit
foreground policy remain unfinished; this feature branch remains unpublished.

## Existing-coordinate acquisition preflight

The acquisition actor must first probe its exact canonical assigned coordinate through the
managed namespace owner. A successful probe re-verifies the full record and crosses the actual
restore sync barriers, then returns fixed metadata only; it does not renew a promise or grant a
signature capability. Missing data permits a bounded network attempt. Corruption or failed
restore durability retains the actual namespace fault gate. The canonical source and mutable
namespace stay leased through Done/cancellation until exact collection or joined stop.

Raw CE137 capture must also reserve both the caller's original transcript and its private copy
before cloning, even for a malformed large transcript rejected later by exact framing. The
private byte vector must move into the closed job. Completion witnesses include absent/present
probes, unchanged promise time, exact/minus-one record workspace, real sync refusal and fault
recovery, native cancellation/restart, default-off Services, and raw-copy workspace admission.

The closed existing-coordinate mode is now implemented in `AssuranceAcquisitionJob`, with
`captureAssuranceProbe` and Services `beginAssuranceProbe`. It derives the complete expected
specifier and assigned shard from the actual current source, precharges record/verification
workspace, then calls full `loadAssuranceShard`. Missing coordinates return their actual Missing
child while preserving a healthy namespace. Success returns only actual stored metadata after
proof verification and file/directory restore synchronization. Probe time cannot move the
stored promise clock; later private signing still performs its own fresh verification/renewal.

Capture reserves `2 * transcript_length` before copying any received bytes and moves the private
vector into the job. Exact/minus-one clone reservation is tested independently of the later
larger proof/storage workspace. The existing full-workspace admission remains in force before
verification or publication; malformed inputs cannot consume an unreserved second raw buffer.

Native checks pass absent/present probes, exact/minus-one record workspace before hashing,
observed complete metadata/payload proof counts, unchanged promise time, actual restore sync
failure/faulted-owner refusal, verified reopen and ordinary worker restart with retained data.
Moved native probe jobs, stale/foreign collection and Done cancellation retain the exact source/
namespace lease; cancelled results expose no record prefix. The expanded acquisition/probe suite
also passes checked ARC/Clang thinLTO and 1000 interleaved cycles with 93504 occupied bytes
unchanged. The complete signing/TLS receipt suite passes, all 566 modules and the actual entry
point compile, and pinned formatting/inventory pass. This establishes local lookup for the
forthcoming network acquirer; it is not yet a live CE137 retry scheduler or complete foreground
assurance activation, and remains local macOS evidence rather than native Linux CI.

## Network acquisition actor contract

The optional acquirer must serialize source planning, exact existing-coordinate probes, genuine
guarantee-target selection, FIN-complete CE137 replies and managed verified retention. It owns
only source-free plans, detached raw bytes and exact native/worker tokens. Recheck the full source
before each new request or worker admission; an unavailable foreign canonical lease alone is not
evidence of a source change. A cancelled or stale result cannot count as acquired data.

Per-round admitted requests, owned dials and reserved response bytes, plus per-peer/job/round
deadlines and retry delay, must be explicit. Budget backoff preserves coordinate progress rather
than repeatedly starving later cores. Request only the independently expected complete payload
ceiling, including all three E4 prefixes. Try only actual C10 credential records; use existing
pinned peers first, then their validated numeric metadata endpoints. A local guarantor may use
ordinary managed availability reading, followed by the same acquisition verifier. Normal owned
dial retirement keeps its physical demand until the native owner retires it and does not close
pre-existing connections. Successful probes skip network fetches; only missing/failed transfer
coordinates need further attempts. Namespace faults bar new acquisition without evicting promises.

### Implemented acquisition host and local evidence

`app/assurance_acquirer.nim` now implements this traversal as an explicitly configured,
noncopyable foreground owner. Its closed jobs share Services' existing worker with receipt,
signing and ordinary reads. Collection preserves exact ownership through `Done`, cancellation
and joined shutdown. Each original local coordinate is probed before fetching; a successful
probe counts only actual full verification and restore synchronization, without renewal or
new-retention authority. Missing coordinates try only the copied canonical guarantor records.
Network replies become retention input only after the ordinary client observes both FINs.
Invalid proofs advance to another target. Request reservations and backoff preserve that target
and coordinate rather than restarting the pass. Owned closing dials remain charged; the round
deadline can close that owner's dial even if unrelated streams keep it busy. Pre-existing
connections never acquire that cancellation token.

ApplicationNode delegates ownership hooks, foreground progress, fair shared-worker admission and
shutdown. Its existing slot-clock polling API admits no new acquisition work. An overload requires
explicit `AssuranceTime` in Common Era seconds, independently of `StateTime` slots, before new
planning/probe/retention jobs may start. Configuration neither opens an archive nor imports a key.
It requires an already installed healthy namespace and an actual validator transport. Cached
counts distinguish restored proofs, new retention and admitted remote requests. Namespace faults
bar new work; foreign worker exclusion alone never invalidates a source-free plan.

The native signing suite now includes two ordinary application-host witnesses against independently
decoded complete trusted seeds. The first checks default refusal, missing-archive refusal,
clock-free polling, real existing-coordinate probes without network requests, unchanged promise
times, preservation of a foreign `Done` lease, owned-probe shutdown and a reopened host's foreign
lease preservation. The genuine fixture has three pending cores and retains original erasure data
for core zero; these checks do not claim possession of the other pending cores.

The second opens real bundled-TLS guarantor endpoints whose public keys are the original canonical
credential targets, and a distinct actual parent-roster client. One serialized native read worker
constructs genuine original CE137 evidence. The first target sends a framing-valid transcript with
a corrupted proof byte. With only one request permitted per round, the client must reject it,
enter actual backoff, advance to a different canonical credential/TLS identity, verify its real
reply and durably acquire exactly one record. It makes exactly two admitted requests. Independently
owned pre-existing connections remain present, acquisition owns no demand connections, and no
private signer is configured. This witness uses pre-existing authenticated peers; it does not
claim native coverage of metadata-driven owned dialing or continuously busy retirement.

The expanded native signing suite passes with 93488 occupied bytes before and after 1000 cycles.
Checked ARC/Clang ThinLTO passes the same suite and the exact controller copy-rejection diagnostic.
The affected application-node and work-exchange runtime suites pass. All 567 production modules
and the real entry point pass semantic checking; formatting and verification inventory pass.
Logs, source identities and optimized build/run/copy results are retained under ignored
`build/jamnp-implementation/assurance-acquirer-*`. These are local results, not Linux CI evidence.
Durable serving, timed outgoing CE141 and explicit foreground startup activation remain required
before this grouped assurance feature is ready for review.
