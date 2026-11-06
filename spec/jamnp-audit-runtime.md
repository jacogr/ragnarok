# Authenticated audit and judgment runtime

Target JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE144/145 and auditor
CE147-to-138 recovery, with Gray Paper `fad0ded4a433052397bf7234352a57fe491883f7`.
This review unit implements genuine canonical audit context, initial-proof authentication,
whole-batch managed receipt and bounded intent retention through ordinary application polling,
plus complete private report evaluation and source-bound judgment signing. Judgment
authentication/gossip, local announcement production and foreground policy activation remain
part of the continuous full-implementation goal.
It follows the durable assurance workflow in PR #1983. No dependency pin changes are implied.

Audit requirements must come from a genuinely retained complete block and its full predecessor,
including the actual committed body. Header-only seeds cannot invent newly available reports.
Replaying the existing authenticated consensus prefix on a private parent fork derives the real
availability output after disputes and Safrole; an assignment disappearing from C10 does not
prove availability or audit completion. Auditors are the block's prior C8 roster, preserving all
original ordinal positions. Header VRF entropy must be the verified output, not raw signature bytes.
Contexts retain source-free immutable reports, complete original credentials and public role/routing
facts with bounded whole input/output policy. They grant no private signing or finality authority.

A received judgment must verify its original epoch/key, report identity and GP signing domain;
a negative judgment must carry two or three original distinct qualified guarantor credentials.
Network timeouts, unavailable history, resource refusal or malformed third-party bundle bytes must
never manufacture a negative judgment. Private judgment signing requires actual bounded work-report
reproduction from authenticated package/extrinsic/import evidence. Conflicting or duplicate claims
cannot silently overwrite obligations, and announcing an obligation commits the local actor to
complete it. Every native and shared-worker token remains exact through cancellation, Done and join.

A completed initial declaration releases its private execution pin once every selected report's
judgment is retained and ready for delivery. Other declarations and explicit host pins retain
their original source. The detached announcement remains available for duplicate suppression. A closing
node returns any remaining declaration pins to Services. A foreign worker keeps its exact
lease and Services releases the abandoned pins after graph access resumes.

## Deferred later tranches

The two pinned revisions are also upstream's latest revisions as checked on November 5, 2026.
JAMNP-S CE144's later announcement is a header hash, validator ordinal, later-intent/core and one
96-byte proof, with its tranche derived from VRF output. It names `S(r)` and `C(r)`. The current
Gray Paper instead signs `jam_audit || header_vrf_output || report_hash || tranche` and describes
periodic no-show selection. That explicit tranche is absent from the current CE144 wire format.

The networking definitions correspond to the unmerged
[Gray Paper proposal #552](https://github.com/gavofyork/graypaper/pull/552), observed head
`4e97e65921bad29edaa45bbf5fd00a62b99061be`. The proposal removes the tranche from the signed
input, derives a fixed report tranche from the VRF and changes tranche progression and audited-report
rules. The maintainer deferred later tranches for this stack on November 6, 2026. CE144 produces and
accepts initial announcements. Receipt rejects later intents as unsupported. CE145 still handles
audits triggered by negative judgments without a CE144 declaration.

Revisit once the Gray Paper and JAMNP-S agree on the signed bytes, tranche derivation and no-show
progression, or the project selects an explicit interoperability profile. Qualify the resumed work
with independent transcript vectors, peer round trips, no-show scheduling, and availability of the
original execution context for newly scheduled duties.

## Completion evidence required

Use genuinely admitted and published blocks with actual availability votes and original report
computation. Cover wrong/unknown/header-only sources, expired assignments, epoch roles and repeated
keys; independent proof/domain/wire expectations; batched/malformed/duplicate/conflicting claims;
real TLS transcripts and both FINs; valid direct bundles and invalid/unavailable CE147 fallback to
authenticated CE138 reconstruction; actual report reproduction and private judgment signing; bounded
retention, source changes, foreign leases, cancellation, joined shutdown and ARC release. Verify
ordinary optional startup and the full native stack before requesting review #1. Do not merge.

Context authentication uses the actual post-disputes availability assignments and full original
guarantees independently from shard acquisition geometry. A malformed availability specification
must remain auditable; acquisition refusal cannot silently discard an audit obligation. The
selection vector has `len(prior_C8)/3` active cores, separately bounded by the configured maximum
core count. Public original-epoch guarantor lookup uses the actual prior C8/C9 populations.

The initial CE144 verifier authenticates the prior C8 Bandersnatch key against the actual
verified header VRF output using ASCII `jam_audit`. Fisher-Yates selects from all active core
positions before empty q entries are filtered. Independent fixed seed vectors cover 17 and 341
cores, including the second entropy group. Whole proof/hash/workspace reservations precede
crypto. Public deterministic selection metadata is not an accepted proof capability. Later
tranches remain explicitly unsupported until the pending source-precedence decision.

## Initial receipt implementation and current limits

The closed shared-worker batch factory captures the actual Services chain and detached finite
bytes. Every record resolves its own header and original ordinal. Structural decoding completes
before body/role/proof work, and whole-batch proof, entropy-hash and retained-context reservations
precede execution. A late unknown header, invalid proof or execution cancellation discards the
entire batch. Up to sixteen independently bounded context executions are permitted per job;
context read/hash/workspace limits apply per occurrence, while proof and retained-output budgets
apply across the entire message. Source-free context metadata records a conservative byte charge.

CE144 is a separate variable upload selector with a hard 2,128-byte ceiling. It remains disabled
until a validator explicitly configures the managed controller. Both authenticated endpoint roles
must be validators; original announcement signers are verified independently of the forwarding
TLS identity. Request FIN precedes managed admission and only whole verified retention permits
the bare response FIN. Generic canonical serving cannot acknowledge these uploads. The normal
application arbitration alternates incoming audits with other managed CPU work.

The finite intent pool reserves all additional entries and context/record bytes before insertion.
Same-message duplicates and retransmissions retain one original header/validator/intent/core
record. Capacity failure never inserts a prefix. Original declarations remain retained until
explicit controller shutdown; positive judgments cannot retrospectively erase an announced duty.
Judgment-based lifecycle retirement, local production, later tranches and complete private audit
execution remain required before this feature or the full JAMNP-S goal is complete.

Local evidence before transport integration: the actual audit-context/initial-proof/whole-batch
suite passed with 1,000 stable ARC cycles (288,848 bytes before and after). The existing assurance
scheduler, managed work submission and work-exchange runtime suites passed. All 576 production
modules and the peer entry point passed semantic checking at that intermediate source tree.
These are local macOS checks, not exact-head Linux CI evidence; final transport/runtime checks
must qualify the completed tree separately.

Final qualification of this initial-receipt review unit:

- `make unit SUITE=jamnp_audit_context`: passed; 1,000 context/native batch, success and completed
  cancellation cycles retained 288,880 bytes before and after.
- `make unit SUITE=pvm_current_block_download`: passed; genuine full-current adoption feeds
  actual CE144 TLS receipt, default refusal, once-only activation, duplicate suppression,
  damaged-proof rejection and foreign Done-lease preservation. Its 1,000-cycle ARC observation
  retained 351,568 bytes before and after.
- `make unit SUITE=jamnp_read_client` and `jamnp_node_service`: passed; bare-FIN upload
  transcripts include empty, initial, later-sized and maximum bounded messages, excess bytes
  and hard-cap refusal. Node lifecycle retained 40,144 bytes across 1,000 cycles.
- Existing `jamnp_assurance_schedule`, `jamnp_managed_work_submission` and
  `jamnp_work_exchange_runtime` consumers passed.
- Both audit-context/batch/pool and full-current/TLS suites passed independently compiled
  checked ARC/Clang ThinLTO builds. Exact source and native-library identities were recorded
  before compilation and rechecked afterward. ARC lowering rejected copying `AuditDispatcher`
  itself with the exact `'=dup' is not available for type <AuditDispatcher>` diagnostic.
- All 578 production modules and the peer entry point passed semantic checking. Inventory
  and pinned source/Rust formatting checks passed. These are local macOS results; Linux CI
  remains a separate exact-head observation.

This unit does not claim later-tranche support, locally produced audit obligations, complete
judgment or bundle-evaluation behavior, or audited-block/finality authority. The normative
later-tranche work is deferred as described above; source and dependency pins remain unchanged.

Receipt policy construction also validates the entire wire schema and requires its core and
original-validator ceilings to agree with the context-capture policy. Missing or contradictory
wire profiles cannot enable the native selector. Focused native refusal cases and both checked
ThinLTO matrices passed after this final configuration hardening.

## Authenticated bundle input boundary under implementation

The private evaluator needs a decoder for GP `makebundle`, since the existing auditable-bundle
module only assembles bytes from completed execution. The new input boundary checks the declared
length and canonical package hash, splits manifest-sized raw extrinsics and fixed 4,104-byte
imported leaves, and authenticates each root-first Merkle path and the complete lookup dictionary
through maintained package/extrinsic/import constructors. All section extents and whole repeated
hash work are reserved before crypto or raw-table copies. Empty and repeated occurrences retain
their original positions; each permitted path has one canonical count byte in 0..12.

This boundary grants verified input commitments only. It does not certify the original erasure
root, historical state or report reproduction, and cannot create a negative-judgment capability.
Direct CE147 candidates that fail it still require CE138 reconstruction before malformed data can
be evidence about the report. Local policy/resource/backend refusals remain unavailable evaluation.
Independent ordinary and mixed-shape wire fixtures cover authentication, malformed boundaries,
wrong package/preimage/leaf commitments, path counts, padding, whole-work reservations, backend
refusal and ARC release. Their native qualification is recorded below.

Private prefix execution also reserves complete sorted-map descriptor tables for retained staged
snapshots and merge scratch. These include unrelated service entries, so chapter-byte budgets
alone cannot bound them. Eight descriptor tables and fixed changed-key/trie scratch are charged
before any private fork or chapter copy, using subtraction/division checks before multiplication.
The genuine context fixture also refuses a workspace that only covers copied chapter payloads.

The bundle decoder's native ordinary, mixed-shape and empty-table cases passed. Whole crypto
counts matched independent expectations (9 and 14 calls); actual authorization and refinement
re-execution from decoded inputs reproduced the original traces, complete item digests and bundle
bytes. Its 1,000-cycle assembly/decoding ARC observation retained 442,608 bytes before and after.

## Private execution origins under implementation

Source-free announcement contexts cannot supply a PVM execution map. A separate opaque private
block origin therefore pins the actual complete predecessor snapshot and its full parameter
profile after genuine context qualification. All reports from that block share this immutable
source; guarded target lookup binds the original report ordinal/hash and prevents replacement.
Independent logical entry, trie-node and total-value ceilings cover the whole map, including
unrelated service entries. Length-only scans avoid copying payloads and preserve execution-only
cancellation. Blocks with no newly available reports create no retained execution origin.

These origins are source-bearing worker objects: every alias remains frozen through exact
collection or joined cancellation. The Gray Paper computation definition says report evaluation
is deterministic using historical lookup within eight epochs of a recently finalized block;
retaining the actual complete predecessor preserves that lookup source while later heads change.
This is distinct from substituting a partial light map or caller-selected code table. Complete original report reproduction and bounded managed registration are implemented below;
private judgment signing and authenticated recovery remain required.


The direct evaluator reuses the actual original full predecessor, core, parameter profile and
availability geometry. It performs maintained authorization, refinement and report construction,
then compares every canonical report byte, including gas, exports, erasure commitments and context.
Only complete equality creates an opaque positive capability bound to the exact original private
target. Copied metadata or a separately captured equal-root origin cannot retag that capability.
Malformed or mismatching unproved CE147 data requests recovery; missing code/history, local limits,
cancellation and backend failure grant no negative judgment.

Services owns an explicitly configured bounded registry with independent aggregate full-map and
source-free context ceilings. Authentic origins may backfill independently trusted canonical
checkpoints, but the actual child header/root, predecessor commitment and entire parameter profile
must match Services' own selected history. A trusted header alone cannot construct an origin.
Duplicate captures preserve the original private source. Host-only namespace/serial selectors
reject foreign or stale lifetimes; evaluation installation requires exact private target identity.

Closed origin/evaluation jobs reuse the single existing fixed-address proof worker and canonical/RPC
lease. Services retains completed capabilities before reopening RPC, returning only detached facts
to controllers. Generic collection cannot expose managed private audit results. Early/foreign/stale
collection, cancellation at Done, proof restart and whole shutdown preserve exact ownership. Proof
stop revokes pending controls; full pins retire only after proof, preparation, checkpoint and disk
borrowers have joined. No optional registry or worker activation follows from defaults.

Native direct reproduction, private registry and managed Services lifecycle checks passed, including
both original reports and 1,000 mixed capture/evaluation/cancellation cycles with 290,160 occupied
bytes before and after. These are local macOS checks; Linux qualification is not implied.

The updated audit/native Services matrix and ordinary two-node TLS suite also passed checked
ARC/Clang ThinLTO. Lowering rejected duplication of both Services and the audit dispatcher with
the expected diagnostics. The existing node-service suite passed with unchanged 40,144-byte
1,000-cycle ARC observations. All 583 production modules plus the application entry point passed
semantic checks; canonical formatting and verification inventory passed.


## Authenticated CE138 recovery and private signing

The fallback boundary accepts only independently verified original-coordinate CE138 transfers
matching every availability field of the genuine private report. Exactly R distinct shards are
required, with whole padded input, recovered output, detached copies and arithmetic work reserved
before reconstruction. Raw CE147 bytes, repeated shards, foreign roots and metadata cannot produce
this evidence. Authenticated nonzero reconstructed padding is a protocol encoding fault, distinct
from local quotas or cancellation. Completed evidence remains bound to its exact private origin;
only the evaluator may translate authenticated faults into a judgment capability.


The authenticated recovery boundary now connects to closed managed recovery/evaluation jobs.
Nine-shard fixtures use the pinned greatest-divisor geometry's four original shards, including
nonconsecutive parity coordinates; fewer or repeated points cannot grant evidence. Every checked
packet must match all six signed availability fields, independently of the Merkle verifier's root
and coordinate checks. Default packets, different metadata, damaged wire, local memory/arithmetic
limits and cancellation expose no authenticated prefix.

Two independently authored dishonest-report cases pass real guarantees, current block admission,
actual five-of-six availability votes and whole current-state publication. One retains a genuine
bundle root while lying about its package identity; the other commits to a consistently encoded
full shard set with nonzero declared padding. Ordinary CE138 proof verification and threshold
reconstruction authenticate those faults. Direct unproved mismatch still grants no negative
capability, while exact authenticated evidence creates a negative evaluation. The padding case
exposes no successful raw-bundle prefix. These are raw dishonest reports signed before admission,
not retagged computed-success owners or fabricated pending assignments.

An independently optional private signer loads a bounded real key/certificate pair and matches
its actual transport identity. Only a completed private registry slot can reach the managed signer;
public validity flags, caller messages and externally supplied evaluation owners are not accepted.
The source's actual prior-C8 ordinal/key is checked independently. Pinned GP signing uses exact
ASCII `jam_valid` or `jam_invalid` followed by the full report hash; unmerged epoch-domain changes
are not adopted. Negative records retain the exact original guarantee slot and two/three qualified
credentials; positive records contain no guarantee. The completed signed owner contains only fixed
public record/fact values, without private key or canonical-state aliases.

Native tests passed direct and recovered positives, both genuinely admitted dishonest cases,
real PEM/certificate imports and independent Ed25519 verification of positive/negative domains and
whole report identities, exact CE145 wire layouts, private managed selection, failed reconstruction,
foreign/generic control rejection, cancellation at Done and joined cleanup. The mixed 1,000-cycle
ARC observation now includes authenticated parity recovery and remained at 308,208 occupied bytes
before and after. All 584 production modules and the entry point passed semantic checking;
canonical formatting passed for 2,469 Nim files and Rust. Network acquisition retries, CE145 receipt/
gossip and local audit scheduling are still required for the full runtime goal.


Intrinsic report faults are checked separately from unproved candidate data. A signed report
claiming a zero-byte bundle cannot represent any canonical work package, while the ordinary
CE138 verifier correctly refuses zero-length availability payloads. Private evaluation therefore
recognizes this authenticated source fault without waiting for impossible shard acquisition.
Unproved empty bytes for a genuine nonzero bundle still request recovery and cannot invalidate it.
Genuinely signed/admitted/assured/currently published zero-length cases and managed cancellation/
signing witnesses passed native checked ARC and Clang ThinLTO. The mixed 1,000-cycle observation
remained at 308,208 bytes before and after. Linux qualification runs on an isolated frozen snapshot;
its verdict is recorded separately from these macOS results.

## Original-identity acquisition integration

Pinned JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE147/CE138 and
Shard assignment, define direct guarantor retrieval followed by proven reconstruction. Detached
routing plans are captured only from genuine private retained origins on the managed worker.
Original guarantee slots select C8/C9 credential keys independently from the audited block's prior-C8
assurance signer roster. Every original assurer ordinal is retained; core/shard coordinates use
`(cR+v) mod N` with the maintained greatest-divisor recovery threshold. No endpoint or compressed row
can substitute a coordinate. A source with incompatible assurer/report populations remains unavailable
for this planner rather than guessing a historical routing table or losing its retained obligation.

Explicit acquisition policy admits one original report at a time. Whole retained packet, raw reply,
proof hashing and reconstruction reservations precede the first request. The initial private empty
candidate probe handles intrinsic authenticated metadata faults; ordinary nonzero reports proceed to
direct retrieval. Full canonical reproduction may accept a direct candidate; malformed or mismatching
unproved content falls back to CE138. Exact two-message shard extents are scanned before the managed
Merkle verifier creates a packet. Only R distinct original-coordinate verified owners reach private
Services reconstruction/evaluation. Exhausted peers, timeouts, quotas, history/backend failures and
cancelled Done output never create a negative judgment. The optional ordinary application node drives
this controller through existing native polling and fair fixed-worker arbitration; omission starts
no acquisition.

The ordinary application node passed real multi-peer TLS retrieval of genuinely available nonempty
reports, including direct success, CE147's maximum 16MiB cap followed by CE138's independent 8MiB
ceiling, corrupted direct content and threshold recovery, one damaged shard proof, one exact native
request timeout, and cancellation. Both failed-peer cases requested a fifth original coordinate to
obtain four independently proven shards, then reproduced the original report. The 1,000-cycle audit
ARC observation remained at 308,208 bytes before and after. Audit and current-block/application-node
suites passed checked ARC/Clang ThinLTO, including exact duplication rejection of AuditAcquisition,
Services and ApplicationNode. All 586 production modules and the entry point passed semantic checks;
formatting and inventory passed. These new integration results are local macOS results. The earlier
Linux/amd64 frozen snapshot through intrinsic zero-length handling passed its regular audit suite;
its ThinLTO compile exceeded the 1,200-second emulation budget and produced no optimized runtime
verdict. A current integration Linux snapshot is qualified separately.

A focused four-variable retirement model checks deferred advancement after an owned peer times out.
The base explores four states; removing the pending-advance assignment yields a four-state repeat
of the exhausted target, and the next-target witness is reachable. Serial/four-worker model runs
agree. This is a design control, not a claim of a reproduced shipped defect; native active-peer/dial
admission, payload verification, slot reuse and worker scheduling remain outside this small model.
The native scenarios additionally exercise genuine direct, reconstructed, damaged-shard and exact
request-timeout paths, with results recorded after execution.
