# Qualifying an authenticated current successor

Use this read-only path after the existing candidate producer has returned a successful
`PreparedCurrentChainUpdate`. It preserves the original block/report/execution/composition chain,
physical snapshot identity and full child Parameters. It does not rerun guests, replace a map,
install state, select root trust or infer finality.

Run all operations, handle copies and alias retirement on the stable host before proof enqueue or
after matching collection or joined shutdown. The fixed-address one-slot proof worker keeps its
canonical ARC graph lease through cancellation and Done. Read-only access still retains/drops ARC
aliases and cannot bypass that lease. Existing generic Services `ViewFailure`/`viewError`, service
overload errors and RPV1 transport are unchanged.

## Choose the evidence required by the consumer

| Input and operation | Successful evidence | Explicit policy and work |
| --- | --- | --- |
| Prepared update, `captureCurrentProfile` | `DerivedCurrentProfile`: original update, cardinalities and full Parameters | Prior C9 extent/roster limits; hash-free exact previous-roster decoding |
| Derived profile, `qualifyCurrentGlobals` | `CurrentGlobalSerialization`: all sixteen globals on that update | Global per-chapter/item/aggregate byte limits; cached full preflight; hash-free |
| Qualified globals and full supplied service declarations, `qualifyCurrentState` | `CurrentStateSerialization`: exact complete service matching and compact inventory | Manifest service/map/key limits plus compact fact/descriptor limits; mandatory bounded matching hashes |
| Qualified current state, `reviewCurrentState` | `ReviewedCurrentState`: original state and same-inventory targeted review | Frozen review limits; original full child Parameters choose deposit profile; preparation before content hashing |
| Qualified current state and full supplied declarations, `captureCurrentLogicalState` | `CurrentLogicalState`: original current provenance plus retained supplied raw keys | Independent compact and extra raw-key descriptor/count/byte limits; mandatory complete revalidation |
| Retained logical companion, `copySuppliedServices` | Detached mutable complete service declarations | Whole service/child descriptor/fact/per-value/key/payload budget preflight; hash-free |
| Prepared update, `captureCurrentUpdateCheckpoint` | Original-source checkpoint capsule and copied fixed context | Explicit V1 byte limit; bounded detached export; hash-free serialization |

Inspect each result's error before extracting `.value`, and select nested reason accessors only for
their actual failure stage. Defaults and refusals never mean successful empty inventory, key or
report. Complete-source absence, missing partial witness, malformed value and resource refusal have
different meanings. Partial proof views remain in the separate [proof API](state-global-proofs.md)
and cannot enter this complete-map qualification path.

The four `StateProfile` cardinalities are not a complete chain configuration. Current/core/epoch
values come from the same original child; the previous population comes from its exact C9 bytes,
with no current-population fallback. Keep the full original Parameters where configuration matters.
`reviewCurrentState` selects those internally; callers cannot inject a replacement economic profile.
Undercoverage remains a successful observation rather than a new global funding rule.

`CurrentLogicalState` retains two compact captures: the original current state's inventory and the
new raw-key companion's revalidated inventory. They bind to the exact same physical snapshot but
have different compact owner identities. Do not join same-inventory predicate certificates across
them. The higher original current owner supplies profile/full-Parameters provenance; the companion
supplies original raw storage keys, fixed preimage/request identities and original source payloads.
Copy-out arrays/bytes are detached and mutable; modifying them creates no certificate.

The child's header root names its **prior** state. Use the original successor snapshot commitment
for posterior serialization observations; it is not an independently published posterior golden.
C15/C16 completion is state processing, not chain finality. The checkpoint capsule preserves actual
view finality separately and reports `NoFinality` when the retained view has none. Installation
remains with existing application/PVM APIs that check exact original parent state and full prior
view/Parameters/finality, rather than root equality alone.

## Interpret the available evidence

The [source audit](../spec/state-current-source-audit.md) records fourteen published pre/post maps
from seven exact pinned trace blobs. Their twenty-six metadata rows are 89 bytes, while current
metadata is 105 bytes. Native decoding refuses unmodified release rows; explicit test-only expansion
changes every selected map root. Expanded metadata and opaque hashed keys do not establish an
unchanged complete current-pin corpus or a full logical source manifest.

Independent authored current-schema maps now qualify complete serialization, refusal categories,
service ordering, account audits, whole reviews and lossless raw-key/service reconstruction. The
review corpus has 192 schedule/order cases, including exact whole-report arithmetic refusals.
These are schema/predicate witnesses, not published full valid-state/STF vectors.

The opt-in complete signed current fixtures author canonical C16 before the parent root and block
signatures, rather than repairing a completed map. Their actual ordinary/assured/disputed/ticketed/
epoch successors match supplied declarations. Existing default rollback-sentinel fixtures are
unchanged and still refuse complete typed matching. This is supplied-and-validated inventory;
`PreparedCurrentChainUpdate` does not export a complete producer-owned logical manifest.

See the source contracts for [current globals](../spec/state-current-globals.md),
[current serialization](../spec/state-current-state.md),
[current review](../spec/state-current-review.md),
[raw-key retention](../spec/state-supplied-logical-inventory.md),
[detached reconstruction](../spec/state-supplied-services.md) and
[current-bound logical provenance](../spec/state-current-logical.md).

## Continue an unchanged logical identity set

A configured selected parent can now seed the same complete logical description used by a completed
current successor. This path consumes the existing successful producer; it never executes guests
again or edits the producer's snapshot. Keep the host ARC gate open throughout construction and
retirement, including temporary aliases.

| Step | Input and operation | Bounded result |
| --- | --- | --- |
| Original configured seed | Full selected `ChainView`, `captureParentProfile`, `qualifyParentGlobals`, then `captureLogicalParent` with complete supplied declarations | `SelectedLogicalParent` retains the exact physical selected state, whole view, full Parameters and original raw keys |
| Preserve identities | Configured seed or prior `CurrentLogicalState`, actual next update, `preserveCurrentIdentities` | Exact original physical parent and whole prior view must match; every physical namespace identity must remain present and no new identity may appear |
| Cache request keys | `captureCurrentRequestKeys` | Independent service/request/native-descriptor limits precede one key derivation per request; the immutable companion retains those original keys |
| Freeze reconstruction | `planCurrentRefresh` | All service/child descriptors, raw keys, actual target payload extents, metadata/request wire bytes and work are admitted before output copying |
| Freeze full qualification | `planCurrentLogicalRefresh` | Actual profile/global policies, complete-map and retained raw-key quotas are frozen; no later source or target substitution is accepted |
| Complete refresh | `executeCurrentLogicalRefresh` | Existing full current and raw-key matching returns `CurrentLogicalState` on the actual successor; supplied payloads and histories refresh while original identities remain fixed |

Request-key capture and complete matching retain their mandatory hashing. Reconstruction planning,
fixed-context observations and admitted detached copying use cached facts without hashing. Metadata
and request histories still pass their exact existing codecs. Failed stages preserve typed source,
missing identity, malformed value, backend and resource reasons; they expose no successful prefix.
The original configured source and completed source remain distinct guarded alternatives through
`identityParent` and `identityPriorCurrent`; the wrong alternative returns `WrongSource`.

Exact full-view provenance includes retained history, full Parameter bytes and finality presence or
absence. Equal state roots or unchanged cardinalities cannot replace it. The fixed
`currentUpdateChildContext`, `currentUpdatePriorViewInfo` and `currentUpdateViewInfo` getters
permit small observations before admitting heavy selected-view/index copies. Successful reconstruction does not grant a
producer-owned manifest, trusted-root policy, installation or finality authority.

The signed integration witnesses cover complete original code namespaces, real HALT execution,
funded existing-key storage growth, forget/restore request histories, and repeated actual children.
Creation, deletion and ejection refuse identity preservation. Separate tests cover equal-root physical
owners, altered history/finality/Parameters, reordered/mutated caller declarations, scope retirement,
exact resource ledgers and actual proof-worker collection/join ownership. All sixteen authenticated
chapter captures and mixed present-empty/absence proofs use independently selected actual roots.
Review still consumes the original current compact inventory; the independently matched raw-key
companion has a different compact identity. Do not join review predicates across those owners.

See [selected parent profiles](../spec/state-parent-profile.md),
[original logical seeds](../spec/state-parent-logical.md),
[identity preservation](../spec/state-current-identities.md),
[request-key companions](../spec/state-current-request-keys.md),
[reconstruction plans](../spec/state-current-refresh-plan.md),
[full logical refresh](../spec/state-current-logical-refresh.md),
[proof integration](../spec/state-current-logical-proofs.md) and
[worker leases](../spec/state-current-logical-worker-lease.md).

## Consume an actual preparation completion on the host

`app/current_logical.refreshCollectedLogical` connects the bounded stages above to the actual
preparation worker receipt. Its Services overloads accept the configured `SelectedLogicalParent`
or completed `CurrentLogicalState`, the opaque `PreparationCompletion` and explicit
`CollectedLogicalLimits`. Capture the configured source against the physical Services-owned view
after startup; an independently reparsed equal-root source cannot replace it.

Keep retained sources and receipts completely untouched while preparation, proof or publication
owns its graph lease. Call `Services.collectPreparation` with the actual ticket first. An
`Uninitialized` receipt leaves the lease closed. Done and cancellation alone grant no host access.
After matching collection reopens access, call `Services.refreshCollectedLogical`; its existing
canonical guards enforce all three managed exclusions. The adapter checks current-vs-legacy
completion, original typed preparation success and the exact still-selected canonical parent before
running identity preservation, request-key capture, reconstruction planning and full qualification.

Inspect `CollectedLogicalError` and use only its selected nested reason accessor. A successful
result is the existing `CurrentLogicalState`; no map constructor or installation authority is added.
Qualification is an optional bounded observation: its resource refusal does not invalidate an
otherwise successful prepared candidate. Enqueue/adopt that original prepared update separately
through existing host APIs. Reusing its receipt after adoption returns `StaleUpdate`. Before another
worker starts, finish any source replacement and let temporary canonical aliases retire. General
producer mutation propagation still requires the separate contract below.

The [collected qualification contract](../spec/application-current-logical.md) records genuine
worker, managed Services, detached proof and durable-publication witnesses. Their expected roots
are explicitly selected actual posterior commitments, independently of the child's prior-state
header root; they are not published upstream current-schema golden vectors.

## Remaining producer contract and parity gates

PVM and state agreed to defer a public delta API until a jointly designed producer contract has a
concrete consumer. Identity-preserving supplied continuation is implemented within the bounded
contracts above. General producer mutation propagation remains separate. That design must settle:

- Exact original logical/physical parent and prepared-successor provenance, including untouched keys.
- Explicit operation identities and ordering, including absence versus present-empty values.
- Selected regular, exceptional and checkpoint rollback outcomes without replaying guests.
- Service creation/deletion and non-guest composition changes across every namespace.
- Bounded retained event/key/payload storage, immutable ownership and atomic failure.

A touched-key trace or physical before/after map difference cannot recover untouched raw keys or
maintain complete logical provenance. Supplied before/after declarations could prove a narrower
observational relation, but would remain supplied evidence rather than a producer mutation certificate.
No speculative public delta API is introduced here.

Full current-pin STF qualification still needs independent complete current-schema pre/post source
material, actual selected producer integration and the outstanding normative/crypto gates. The
[current Bandersnatch pin record](../spec/bandersnatch-pins.json) preserves release-reference IETF
verification separately from adopted current Thin VRF parity. Conflicting bless allowances retain
`AmbiguousPrivileges` under the [existing integration contract](../spec/pvm-accumulation-integration.md).
No pins, compatibility fallback, RPC root/schema policy or storage API/format are changed. M1 framing
and current request namespace completion do not imply complete state serialization/STF or JAM parity.

## Explicit supplied successors and retained consumers

When actual execution changes physical identities, identity-preserving refresh continues to refuse.
A caller with complete explicitly supplied successor declarations may instead use
`planCollectedSupplied` then `executeCollectedSupplied` after actual collection. The frozen plan
binds the genuine target and independent policies; execution rechecks the canonical prior and
matches the entire actual map before retaining raw keys. This is supplied post-state evidence,
not a producer mutation relation or provenance certificate. See
[collected supplied qualification](../spec/application-collected-supplied.md).

`captureLogicalSeed` captures the actual configured host source under independent selected-view,
global and logical policies. Fixed `currentLogicalUpdate`, `currentLogicalContext` and
`currentLogicalViewInfo` observations preserve original provenance before heavy copy admission.
Retained-source consumers include [checkpoint capture](../spec/application-logical-checkpoint.md),
[bounded proof queries](../spec/application-logical-proof.md) and
[original-current review](../spec/application-logical-review.md). Services guards seed, supplied
planning/execution, checkpoint and review against all three managed native graph leases. Review
never joins raw-key companion compact predicates into original-current reports. Bounded failures
remain optional observations, separate from valid candidate acceptance and actual adoption.

The [durable composition](../spec/application-logical-durable-consumers.md) exercises real new-key
creation, three consecutive children, both disk layouts, retained consumers through actual native
collection and detached bytes after shutdown. Broader producer-owned operation/rollback/untouched-key
provenance and independent current-pin parity gates remain open.

## Submit a retained logical proof through Services

Call `Services.beginLogicalProof(source, plan, limits)` outside other managed work to prove the
original retained logical producer, including a prepared successor not yet installed canonically.
Use its guarded admission error before extracting the existing proof-worker ticket. Capture refusals
retain original logical/query causes; managed RPC/native refusal remains separate. Keep every source
and plan alias untouched until actual `collectStateProof(ticket)` or joined close; cancellation and
Done retain exclusion. Authenticate detached response bytes against your independently selected
expected root. See [managed logical proofs](../spec/application-managed-logical-proofs.md).
