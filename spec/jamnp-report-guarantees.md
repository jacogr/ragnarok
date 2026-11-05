# Source-eligible work-report guarantees

Target JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE134/135, and Gray Paper
`fad0ded4a433052397bf7234352a57fe491883f7`, reporting/assurance and work-report computation.

This feature must authenticate the original package's complete recent-anchor tuple, lookup-anchor
identity/slot/posterior root and inclusion-age window before granting any signing or sharing
capability. The candidate next block uses the current head's actual complete posterior root to
correct the latest C(3) record. Older lookup roots require the retained child-header commitment;
the current head's lookup root can be checked directly against its trusted complete map. A header
hash alone cannot authenticate a substituted posterior state.

Historical code lookup remains the GP historical-availability mechanism, using a recent complete
view and the declared lookup time. Work-report computation explicitly supports this mechanism;
this feature must not silently replace it with a different execution-state model. Context validation
alone proves neither authorization, package/dependency eligibility, successful computation nor
credential authority. Private immutable capabilities must retain their exact original header and
source identity under the managed worker lease.

Completion requires real local Ed25519 signing bound to TLS identity and current duty, source-bound
eligibility before signing, acceptable shard populations across the anchor's inclusion window,
CE134 same-input execution and returned hash/signature checks, third-guarantor grace, and CE135
verified distribution to the required current/next recipients. Omission remains disabled. Supporting
code, negative/source/lifetime tests, real multi-peer TLS evidence and ordinary activation belong
in the same coherent feature group. No report signature or complete runtime guarantee flow is
claimed by an anchor-only component.

## Implemented foundations and evidence

`work_anchors.nim` qualifies the exact original decoded header and posterior source map using
bounded corrected C(3), the shared reason-only GP anchor tuple/age rule, and retained sealed
child-header commitments. Current-head lookup roots use the trusted complete posterior map.
This qualification remains separate from package/pipeline eligibility and credential authority.
The new native suite and existing signed-report anchor suite pass;1000 success/refusal cycles
retain86848 and79792 bytes respectively, with equal before/after observations.

`work_signer.nim` loads only a bounded unencrypted PKCS8 Ed25519 private key matching the configured
leaf certificate. Paths are bounded before conversion. A maintained TLS parser never prompts,
rejects malformed leading framing, non-whitespace suffixes and duplicate keys, and commits seed
output only on complete success. Native scratch is wiped. Private file bytes go directly into
caller-wiped storage so read/limit failures create no intermediate secret heap copy. The opaque
owner exposes public identity only; no mutable seed alias or arbitrary-message signing API escapes.
Managed integration must load and retain this owner privately and freeze every alias until the
exact worker collection/join. Actual transport identity and duty must still be checked when used.
The native signer boundary suite passes, including late refusal without seed output, key mismatch,
path/file limits, malformed/encrypted/duplicate inputs and1000 cycles retaining87856 bytes.

The existing bounded-file consumer suite, application build, formatting and inventory checks pass.
Linux-target semantic checking of both new modules passes; this is not native Linux CI. Report
policy/pipeline eligibility, acceptable shard counts and typed local signing are implemented below.
Managed signing is implemented below. CE134/135 exchange and ordinary startup activation remain unfinished. These foundations stay in the guarantee feature branch;
they are not a separate helper PR and do not establish full JAMNP-S completion.

## Candidate-header inclusion correction

The pinned header definition includes the current candidate in the ancestor set. The prior report
validator excluded it, so a valid lookup naming the parent could not use the candidate's prior-state
commitment as its child proof. Ordinary block-bound completion and missing-header discovery now
capture the actual admitted candidate and parent together, with whole-input count/byte preflight.
Trusted older subsets continue to prove older lookups. A candidate lookup still lacks a newer child;
a future header or the lookup header's own prior-state root cannot substitute.

The regression uses distinct prior/posterior roots and genuine signed reports. The normal staged
coordinator, missing-context plan and atomic report publication accept a parent lookup without any
older-header fetch. Existing report-anchor, report-admission and report-transition suites pass.
This fixes the on-chain counterpart of current-head work-context qualification; it does not by
itself activate signed CE134/135 streams.

The candidate-inclusive correction also passes the managed worker ancestor discovery/resume/
cancellation suite, including1000 cycles retaining222336 bytes. The latest anchor and admission
cycles retain82080 and398592 bytes respectively, unchanged before/after. The production build,
formatting and Linux-target admission semantic check pass. No native Linux CI verdict is claimed.

## Shared pre-signing report rules

Unsigned report inspection now shares the block validator's exact authorizer, service/code,
minimum gas, aggregate gas/load, package uniqueness, dependency and segment-root rules. The
state-backed pipeline inspector derives its existing-package set from bounded exact C(10),
C(14) and C(15) decodes. Raw/default report owners fail, and report/index cardinalities are
checked before traversal or allocation. These inspections return reasons only; admission owners
still require genuine verified credentials and their preceding certified stages.

Unsigned/signed policy agreement covers inclusive gas and refinement load boundaries and overflow
fields. Package tests cover the shared relation implementation and compare unsigned/state-backed
inspection on successful and later dependency-refused paths. Native policy, package and signed
admission suites pass; package/admission1000-cycle retained bytes remain156544/398592 before
and after. The application build and format check pass. This supplies the report-rule boundary
for the upcoming source-bound signing flow; no signature authority is granted by these helpers.

## Original report and assignment binding

Managed report staging now requires the session's actual authorization context. Before encoding,
it follows the refinement's original authorization and checks the exact package owner, core and
complete execution map. The worker also checks the computed transcript's retained provenance
before returning Reported. A separately authorized equal-byte package, independently published
equal-root map and default owner cannot substitute. Execution provenance remains distinct from
requalification against a later canonical inclusion view.

The copied duty now retains the actual original roster ordinal selected by the GP assignment
planner. A credential must use that nominal index, rather than its shuffled permutation position.
Native report, assignment and managed-session suites pass, with1000-cycle retained bytes unchanged
at286800,58864 and40816 respectively. The managed regression uses genuine equal-byte separate
authorizations and complete PVM/input/report execution. Production build and format check pass.
Full eligibility, acceptable shard populations, signing and CE134/135 remain required.

## Anchor-window populations and qualified contributions

`work_population.nim` derives acceptable shard populations from the H slots strictly after the
authenticated anchor, including the Hth slot. Its current population is the anchor's exact C(8);
when the interval reaches the next epoch, its next population is the anchor's exact C(4) pending
roster. Each count is accepted only when at least one candidate slot lies in that roster's epoch.
Missing retained anchor state, malformed/nonexact chapters, resource ceilings and slot overflow
produce typed refusals. A window reaching beyond the next established roster is explicitly
uncertain. The pinned Full/Tiny profiles have H=8 and E>=12, so their interval crosses at most
one boundary. No unavailable roster or future staging mutation is guessed.

`work_eligibility.nim` creates a private signing capability only after checking the original
computed package/core/map and complete parameter profile, fresh anchor/lookup context, acceptable
shards, actual local assignment and the shared GP service/authorizer/gas/pipeline rules. The
corrected C(3) used by anchor qualification is retained for exact pipeline inspection. Consensus
gas and geometry must match the selected profile; independent local decoder/copy ceilings remain
explicit. The execution map and fresh inclusion map are separate, so historical deterministic
execution can be requalified without replacing its provenance. This capability does not fabricate
credential-backed report admission or promise an immediately vacant core.

`signWorkContribution` accepts only this private capability, checks its assigned identity against
the privately imported TLS key, and signs the exact GP guarantee message. Its opaque result binds
one actual credential and original roster index to the checked report and computed bundle chain.
It is one contribution, not a fully guaranteed report. Defaults and a separately valid mismatched
TLS signer cannot sign. No seed alias or arbitrary-message API is exported. Runtime integration
must qualify and sign under the same managed graph lease, freeze all aliases until collection/
join, and check actual host identity/freshness at use.

The native signer suite now performs genuine original package authorization, authenticated import
inputs, PVM execution, report/availability composition from a parent map, and qualification against
its actual child view. Fresh wrong-code and duplicate C(15) changes refuse eligibility. Signatures
verify with the matching public key and fail for altered messages; a distinct valid TLS key is
refused. Successful signing and later policy refusal repeat1000 times with196768 bytes retained
both before and after, including the precomputed fixture owners. Population/anchor cycles retain
87456 bytes unchanged; report and managed-session consumers retain286800/40816 bytes unchanged.
All four native suites pass, as does Linux-target semantic checking of the signer and its new
module dependencies. The production build, formatting and verification inventory also pass. This evidence does not
establish CE134/135 network execution or native Linux CI.

## Managed private-key lifetime and contribution collection

Services now imports its work signer privately from certificate/key paths only while full-state
access and an empty work session are available. The supplied actual transport identity must match
the imported key. Setup returns reasons, never a signer alias. Cached public identity/readiness
are scalar observations; configuration cannot inspect or replace key ownership during a foreign
worker lease. Omission remains disabled. Ordinary CLI work-policy v1 does not yet invoke this setup.

The closed contribution job retains original execution provenance, a fresh canonical view and
explicit limits. It qualifies and signs on the same managed CPU turn, returning either a genuine
contribution or the precise eligibility/signer failure. Done continues to occupy the exact lease.
Foreign collection, cancellation and joined close cannot expose a result early or release a key
while the worker may use it. Services delegates the new owner through both aggregate hooks and
retires its private signer after worker join. Actual ARC lowering rejects copying Services.

Collected contributions preserve fixed report metadata and the original availability source. CE147
bundle serving remains available after signing, with exact original package, extrinsic, imported
segment and proof bytes. Signing does not create a new assurance retention promise.

The new native managed-signing suite obtains a real TLS-framed CE146 header, then drives genuine
Services authorization/body/refinement/report/signing and exact contribution collection. It checks
private-path setup refusal, mismatched identity/key, foreign controls, Done cancellation, joined
close and post-signing managed bundle readback. A separate real CPU worker qualifies the older
execution against its child view and repeats success, Done cancellation and late key refusal1000
times, retaining173376 bytes before and after. The existing proof-worker, managed submission,
network dispatcher and signer suites pass. These tests establish managed signing and lifetime
boundaries; automatic CE134 exchange, multi-guarantor assembly/grace, CE135 distribution and strict
versioned startup activation remain required before this feature group is ready for publication.

Final managed-signing verification also passes production build, formatting/inventory and Linux-target
semantic checking of the closed contribution job and its dependencies. This is not native Linux CI.


## Same-core sharing receiver

The CE134 receiver now has a dedicated, default-disabled native route. It admits only actual
local/peer validators, bounds the two E4 messages, requires exact request FIN, and returns only
one E4-framed96-byte report-hash/signature response. Native callbacks copy bounded raw bytes;
they never inspect canonical state, sign, or run guest computation. Physical stream and global
input/reply credit remain charged through native retirement.

A distinct Services sharing namespace leases the same managed CPU without replacing a waiting
builder session. Capture detaches raw request ownership before admission. Both authenticated
identities must have the requested current-core duty; the declared shard count must be acceptable
for the original anchor window. Complete bundle proof validation, original package authorization,
refinement, report preparation, fresh-source eligibility and private TLS-key signing all occur on
that single lease. Failed/cancelled collection yields no response signature. The most recent
successful shared contribution retains its original bundle for CE147 after primary retirement;
this bounded cache does not establish an assurance-retention promise.

The new native sharing suite passes real TLS requests, withheld FIN, suffixes,
truncation, unknown peers, wrong cores, unacceptable shard counts, invalid mappings/proofs,
Done cancellation, primary-session isolation and post-primary CE147 readback. Outgoing CE134,
unique peer contribution assembly, third-guarantor grace, CE135 and normal startup integration
remain outstanding. No full sharing or full JAMNP-S completion verdict is claimed yet.

Upload framing also uses the pinned GP auditable-bundle ceiling,13,904,950 bytes, rather than the
previous200 KiB cap. GP work_packages_and_reports.tex input/bundle limits permit larger payloads;
explicit local package/input/execution policy and global transport credit still apply. A decoder
regression uses a valid262,144-byte payload, plus explicit local-limit and protocol-limit refusals.


Receiver verification: genuine success/proof-refusal computation cycles retain215808 bytes before
and after1000 repetitions. Upload decoding and real CE133/146 TLS header tests accept valid
262,144-byte payloads; the latter preserve complete header ownership while body admission remains
paused. Existing network dispatcher and managed signing suites pass. Upload, staged transport and
managed signing ARC cycles retain921088,21712 and174096 bytes respectively, unchanged before/after.
Actual Services ARC lowering still rejects duplication. Linux-target worker and native-node
semantic checks pass; this is not native Linux CI. The earlier new upload regression lacked a
required direct Gas import; that test-only compile failure is corrected and the suite passes.


## Source-bound sharing cohort

Work duty retains all three original same-core roster positions and their full copied validator
records from the exact observed assignment. GP-null offender records retain their positions; they
cannot become valid signing identities. Qualification binds this fixed cohort alongside the
original transcript and fresh-source report checks. A signed contribution can expose only that
bound cohort, so sending and signature assembly do not derive peers from an older computation
snapshot, packet claims, or unbound public eligibility metadata. This is a dependency of actual
outgoing CE134 and assembly, not a separate helper PR.


The native duty suite checks all three original positions against an independent GP shuffle,
full metadata, out-of-range/default access, independently mutable copies and an offender's exact
nulled position. The signer suite binds the retained cohort to the fresh head's complete root and
observed signing slot. Native duty, signer, managed signing and real CE134 sharing suites pass;
1000-cycle ARC observations are58864,204480,175104 and215808 bytes respectively, unchanged
before/after. Cohort-shape refusals have a separate local reason, rather than inventing a failed
state-chapter decoder. These source-bound facts do not yet establish outgoing exchange or assembly.

Final cohort verification also passes Linux-target signer/dependency semantics, formatting, inventory
and the production build. The final native duty run includes the separate cohort-shape reason.
These checks do not constitute native Linux CI or outgoing CE134/135 completion.


## Outgoing preparation and credential assembly

Outgoing CE134 preparation must serialize the signed transcript's exact original auditable bundle
and verified package/root dictionary, with the report's selected shard count. The local byte
ceiling is checked before copying bundle bytes. Sealed peer targets bind an original assigned
ordinal, full validator record, report signing message, slot, core, qualification head and complete posterior source root.
Assembly must check actual authenticated transport identity, exact96-byte response, original
report hash and ordinary Ed25519 signature, and reject repeated validator indices. Immutable
collection versions preserve earlier rounds on any refusal. Only two/three verified credentials
can produce a private collected guarantee and canonical standalone CE135 payload. Original
indices are sorted before the existing guarantee codec. Output budgets and codec failures grant
no credential authority. Actor grace timing, native sending, fresh distribution and ordinary
startup activation remain required before this feature is complete.


The new native assembly suite uses three real TLS fixture keys. Both peers independently execute
and sign the outgoing exact bundle. It verifies two/three thresholds, reverse arrival and strict
original-index ordering, byte-budget refusal, immutable copies, defaults, wrong transport keys,
truncated/suffixed replies, wrong report hashes, invalid/mismatched signatures, repeated indices
and cross-slot targets. A same-head/same-report test replaces the complete posterior cohort map;
the root binding rejects its otherwise matching target. These checks run real signature
verification over1000 assembly cycles with542368 bytes retained before and after.
The production GP credential verifier also cross-checks emitted payloads against the actual
canonical roster/entropy/dispute chapters. This verifies credential compatibility, not complete
block admission, network sending, grace timing, or runtime distribution.

Existing duty, signer, managed signing and real-TLS sharing suites pass after outgoing preparation;
1000-cycle retained bytes are58864,204480,175120 and215808 respectively, unchanged before/after.
Linux-target assembly and preparation semantic checks pass; no native Linux CI is claimed.


Shard acceptability also checks the requested report core against the selected population's
active-core domain, count/3. A count present in the anchor window cannot make a higher core active.
Both pre-signing eligibility and CE134 basic verification apply this check before signing or
refinement. The primary rule is GP reporting_assurance.tex active-core assignment (near the
scaling discussion and R/P functions); the independent production credential verifier already
rejects such reports as InactiveCore. Source-bound population boundary tests cover both6/9-member
rosters, a configured third core, following-slot boundaries and defaults.

Final assembly verification also passes formatting, inventory, the production build, and refreshed
Linux-target assembly/preparation semantics after the population/core eligibility correction.
The native anchor/population suite retains87456 bytes across1000 cycles, unchanged before/after.


## Native outgoing CE134

The native sharing client reserves complete request output credit before allocation, writes at
most4096 bytes per callback, and requires E4(96), the complete fixed response and exact FIN.
All bytes remain untrusted until managed credential verification. Closing/queued/completed client
frames retain their reservations through native retirement or exact host collection. Public
queued-open cancellation suppresses delayed fulfillment before reuse. Actual peer generation and
a nonwrapping serial bind each outbound ticket; response bytes do not choose their TLS identity.

Outgoing sharing uses two dedicated global slots independently from the two incoming work slots,
while all ephemeral families still share64 global slots and two physical directions per peer.
One incoming and one outgoing sharing direction can therefore coexist on each pair. This avoids
three guarantors occupying all work slots with their own requests and deadlocking each other.
Both endpoints must be actual validators and sharing remains explicitly disabled by default.
The new native suite checks literal malformed/FIN framing with the existing raw TLS harness,
large multi-callback requests, and six simultaneous directions between three actual node owners.
Managed job/actor integration, grace and CE135 handling remain outstanding.


Pinned LSQUIC permits zero-progress writes when its send buffer/flow credit is exhausted
(include/lsquic.h write contract and src/liblsquic/lsquic_stream.c stream_write_to_buffer).
The large native request exposed treating zero as a fatal error. Sharing and ordinary read
clients now retain their exact unsent offset and write subscription on zero/-2; only other
negative returns fail. No vendor source, native ABI or dependency pin changes are needed.
The same raw TLS harness covers both client families, preserving exact first-error/FIN behavior.


Clean native verification passes every truncated response extent, malformed low/high E4 lengths,
suffixes, exhausted response credit, withheld FIN and a262,144-byte multi-callback request.
Three actual authenticated node owners simultaneously hold two outgoing and two incoming sharing
routes each, then collect all six replies and assemble genuine three-credential guarantees with
the exact ticket TLS identities. Default-disabled activation, invalid requests, queued and active
cancellation, stale/foreign tickets, physical quota release and complete-reply expiry are checked.
A complete uncollected reply survives the queued-open deadline and expires at the ordinary read
lifetime while its authenticated peer remains connected. All temporary trace output is removed.
One thousand large client snapshot release cycles retain549296 bytes, unchanged before/after.

The existing raw read-client, native node-service, staged work-stream and managed receiving suites
also pass. Their observed ARC release baselines are39664,21712 and215808 bytes for the latter
three suites, unchanged before/after1000 cycles. Linux-target node/client semantic checking passes;
this is not native Linux CI. Closed-worker preparation/response/collection, runtime grace and
CE135 receiving/distribution are still required for the complete guarantee feature.

Final native-client verification passes formatting, inventory and the production build. Actual ARC
lowering rejects duplicating NodeService with the added client buffers; the checked probe retains
the exact expected unavailable-dup diagnostic. All native callback owners retire before their buffers.


## Managed outgoing exchange

Closed worker factories prepare the exact request/targets/initial round, verify an actual peer's
fixed response, and collect the final canonical guarantee. No caller closure or native handle
crosses the CPU boundary. Services retains its original signed outcome separately from exchange
progress; rejected peers and output budgets preserve every accepted credential. Prepared raw
bytes and fixed targets are cached independently from the worker-owned round graph, so native
I/O can continue while verification borrows canonical state. Complete payload bytes are detached
from the collected guarantee graph before transport access. Both aggregate hooks and joined
teardown/reaping cover the new owners. Actor grace, CE135 and startup integration remain required.


The native managed-exchange suite starts from a real TLS CE146 header and drives actual Services
authorization/refinement/report/signing, exact exchange preparation, independently computed peer
responses, recoverable hash/identity/duplicate/budget refusals and final three-credential payload
collection. An incoming sharing job preserves the waiting primary round. Independent raw caches
remain readable through the leased graph, and CE147 returns the original exact bundle after
collection. Tests cancel each new phase after Done, retain a retired round through an unrelated
reader, and join an active verifier on close. One thousand real worker cycles cover complete
exchange, signature refusal, insufficient credentials and Done cancellation, retaining336192 bytes
before and after.

Existing managed signing, receiving, application proof-worker, managed submission and ordinary
dispatcher suites pass. Signing/submission/receiving retain175744,40816 and215808 bytes across1000
cycles respectively, unchanged before/after. The genuine TLS/Services test setup is shared between
signing and exchange suites. Actual Services ARC lowering still rejects duplication with the new
round/result/raw owners. Linux-target closed-job semantics pass; no native Linux CI is claimed.
Runtime grace, both CE135 directions and strict optional startup remain unfinished.

Final managed-exchange verification also passes formatting, inventory and the production build.
All required worker/source owners remain private until exact collection or joined shutdown.
