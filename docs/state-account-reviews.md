# Complete-source account audits and reviews

These synchronous APIs inspect complete serialized state under explicit caller
choices. They preserve serialization, targeted account invariants, resource
admission and economic observations as separate contracts. They do not select a
trusted root, install application state or establish full JAM/STF parity.

## Choose the source and scope

| Input/result | Entry point | What success establishes |
| --- | --- | --- |
| Complete immutable mapping | `validateGlobalState` | All 16 global chapter serializations under the supplied profile |
| Global serialization certificate and complete service declarations | `validateStateManifest` | Exact mapping equality; no opaque/unclassified service fields |
| Exact manifest and service declarations | `captureStateInventory` | Original-source immutable logical identities, metadata and extents |
| Exact inventory and explicit policies | `planAccountAudit` | Complete resource admission; no semantic validity claim |
| Frozen account plan | `executeAccountAudit` | Dependent footprints, present content hashes and request-key linkage |
| Complete directory | `resolveServiceSupervision` / `buildSupervisionTable` | One-hop incarnation-bound supervisor observations |
| Certified footprints, same inventory directory, explicit rates/profile | Deposit observation / economics table | Exact minimums and pool coverage observations |
| Same-source invariant/supervision/economic components | `joinAccountReview` | One joined owner preserving each component's original scope |

The original complete inventory identity matters. Copies of its handle compare
with `sameStateInventory`; defaults and separate captures do not. Equal roots,
independently built equal mappings and even two captures of one snapshot cannot
substitute component evidence. Returned fixed observations are detached copies,
not construction authority. All owner storage, result tags and payload fields stay
private; only successful guarded accessors expose results.

RPV1 proof transport and generic Services `ViewFailure`/`viewError` contracts are
unchanged by these source APIs. Existing service overload errors retain their
compatibility.

Partial authenticated proof views use the separate
[proof query contracts](state-proof-queries.md). They cannot become complete maps,
inventories or trusted-root authority through these APIs. `NoService` from a
complete directory is proven absence in that source; missing partial witness,
malformed value and resource refusal remain separate concepts.

## Admit work, then check predicates

`AccountAuditLimits` contains every footprint/content/linkage policy plus a
planning budget. For N services, S storage facts, R request facts and P present
preimages, planning charges 2N+P fixed inspections. Footprint work charges N+S+R;
content work charges P hashes and actual stored payload bytes; matching admission
charges the complete worst-case sum of each service's P_i*R_i comparisons.
Every multiplication/sum is proved by division/subtraction before evaluation.
Zero-length present preimages still count as hashes. Absent advertised payloads
consume no content-copy budget.

A successful plan freezes the exact inventory and policies. Changing caller policy
objects or returned copies cannot loosen it. Execution accepts only the plan and
runs footprints, linkage, content, then exact-owner join. Early semantic failures
perform no content hashes; backend refusal remains different from hash mismatch.
Planning can succeed for semantically wrong content: admission is not validity.

The targeted equations follow pinned Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, accounts eq:deposits and
eq:preimageconstraints:

- Items are storage count plus twice request count.
- Octets are storage key/value bytes plus 34 per storage item, and advertised request
  bytes plus 81 per request. Present preimage payloads add no separate term.
- Every present preimage hashes to its declared raw Blake2b-256 identity and has
  a request key with that hash and its exact actual byte length.

Request history mode does not participate in that key-membership predicate; this
audit does not infer another ordering/availability invariant. Current request
lengths are below 2^32-2; both reserved namespace prefixes remain rejected with no
legacy fallback. Large absent advertised blobs do not require large allocations.

See the [planning](../spec/state-account-audit-plan.md),
[execution](../spec/state-account-audit-execution.md) and
[request boundary evidence](../spec/state-account-request-boundaries.md).

## Interpret supervisor and economic observations

The effective supervisor is the designated identity only if it exists with the
recorded creation slot; otherwise it is self. Selection is one hop, including
self-designations and cycles. The complete-source reader does not replace mutable
runtime authorization or grant authority over another source.

Minimum balance is max(0, base + item-rate*items + octet-rate*octets - gratis).
The checked arithmetic consumes gratis before refusing an unrepresentable final
E8 value. For example, 2*UINT64_MAX-UINT64_MAX is representable. Pool coverage uses
liquid plus protected balance without forming an overflowing sum. Coverage does
not grant withdrawal permission, and undercoverage is a successful false
observation rather than an inferred universal invalid-state rule.

`StateEconomicProfile` retains the caller's exact immutable `Parameters`, including
non-deposit fields. Default parameters cannot stand in for selected zero rates;
explicitly valid zero-rate configurations remain usable. Existing parameter
validity is its documented population/clock subset, not full chain validation or
network/configuration discovery. Tables preflight service work and retained fixed
row bytes; byte accounting excludes the already retained source graph.

See [supervision](../spec/state-service-supervision.md),
[deposit arithmetic](../spec/state-account-deposit.md),
[economic configuration](../spec/state-economic-profile.md) and
[complete reports](../spec/state-economics-table.md).

## Restore an explicit-root checkpoint

`decodePlannedAccountCheckpoint` retains the existing checkpoint transport and
requires expected root, complete service declarations, state profile and all
resource policies. Serialization/root validation and exact inventory capture
precede account planning. Their mandatory hashes are distinct from later account
content hashes. Planning refusal precedes semantic account checks.

`decodeAccountReviewCheckpoint` additionally requires a selected economic profile
and separate directory/footprint/supervision/economics policies. Invalid economic
provenance refuses before restoration. Later report policies can refuse after a
successful account audit; there is no single aggregate preflight claim across all
restoration and review stages. A bounded hash-free footprint recheck supplies
reusable same-source economic evidence.

For a successful result, `value` returns the retained review. `accountReviewInfo`
returns fixed component counts, `reviewInventory` retains the original complete
logical source, and component/profile accessors retain their original owners.
Failure-specific getters are guarded by their exact phase. Preserve the actual
result and nested reason; do not retry another root/profile, silently loosen
quotas or flatten a malformed value into absence.

Neither adapter performs disk I/O, canonical installation, RPC/schema changes or
automatic root selection. The supplied root's independent authority remains the
caller's responsibility. Returned source graphs outlive caller transport and
manifest buffers. Existing canonical proof-worker ARC exclusion still applies
when application code operates on a leased canonical graph: cancellation does not
release the one-slot worker lease; matching collection or joined shutdown does.
These new APIs introduce no worker, address change or scheduling bypass.

See [planned checkpoint audits](../spec/state-planned-account-checkpoint.md),
[same-source review joins](../spec/state-account-review.md),
[review checkpoint stages](../spec/state-account-review-checkpoint.md) and
[detached ownership evidence](../spec/state-account-review-lifetime.md).

## Verification and remaining scope

Focused source-owned native suites cover typed refusals, exact/short resource
boundaries, content hash observers, source identity, copied policies/observations
and 1,000-cycle ARC retirement. Independent arbitrary-precision corpora check
1,024 deposit cases and 2,048 footprint cases. The supervisor dictionary corpus checks
512 nomination/incarnation configurations in all six declaration orders. Complete
account shape and declaration-order matrices retain canonical roots/transport
while refusing cross-capture evidence substitution. These tests are targeted
current-pin evidence, not the missing full upstream state/STF corpus.

Reproduce affected paths with `make unit SUITE=state_account_review_checkpoint`,
`make unit SUITE=state_account_review_lifetime`, or the owning suite documented in
each contract. Reference/tooling tests run through `make check-python`; lifecycle
models remain in `make check-models`. Strict runtime/compiler guards preserve
genuine success controls and exact diagnostics. Local macOS results remain
separate from exact-head Linux CI. M1 framing/current request namespace completion
does not establish global semantic validity, whole-block STF or full JAM parity.

For the authenticated current producer path, original full-Parameters selection, retained supplied
raw keys and remaining producer/parity gates, see [current qualification](state-current-qualification.md).
