# Authenticated global state reads

Use `state/proof_global` to select and decode global chapters from verified partial evidence.
The [feature contract](../spec/state-global-proofs.md) records scope and verification;
[selected-state queries](state-proof-queries.md) explains managed worker admission and ownership.

## Request a bounded plan

`planProofChapter` and `planProofChapters` accept the existing nominal `StateChapterId` values
and a caller `ElementLimit`. Inspect `GlobalProofError` before accessing `.value`. Capture sorts
keys into canonical order and rejects duplicates. Default plans are invalid; an explicitly empty
plan requests no facts. Plans contain no root, values or verified-state authority.

Existing semantic service selectors remain in `proof_service`. Call `toStateProofPlan` explicitly,
then `mergeStateProofPlans` with a global plan and a combined count ceiling. Union coalesces equal
identities; it does not discover roots or grant completeness. There is no implicit conversion back
to a semantic service plan.

Pass the resulting generic plan to `captureProofQuery` or `Services.beginStateProof` with the
same complete selected-block source and explicit policies used by service queries. Generic
execution reports view/framing refusals as `ProofQueryError.ViewFailure` with guarded `viewError`;
nested proof errors still use `proofError`. Existing service-plan overloads preserve their
`ServiceFailure`/`serviceError` behavior. Managed worker leasing, cancellation and joined retirement
apply unchanged; release temporary canonical aliases before submission.

## Authenticate the reply

Supply an independently selected expected root and the exact requested plan to
`decodePlannedProofs`. RPV1 carries witnesses, not root authority. The decoder checks declared
count and each fixed key before copying witnesses or hashing; failures publish no verified prefix.
Keep root/block identity selection in the caller's established trust policy.

This example accepts a reply for exactly time and entropy, retains all existing receive budgets,
and updates the caller's output only after both typed reads succeed:

```nim
import src/state/[proof_global, proof_plan, proof_view, planned_proof, trie_proof]
import src/codec/[bounded, state_composition, state_safrole, state_trie]

proc verifiedReplyTime(wire: openArray[byte], expectedRoot: StateRoot,
    retained: ProofViewLimits, perProof: StateProofLimits, aggregate: StateProofBatchLimits,
    wireBytes, entropyBytes: ByteLimit, output: var StateTime): bool =
  ## Authenticate exact scope first; failed transport or typed reads leave output unchanged.
  let planned = planProofChapters([StateChapterId.Time, StateChapterId.Entropy], ElementLimit(2))
  if planned.error != GlobalProofError.None:
    return false # Plan refusal provides no requested-key owner.
  let received = decodePlannedProofs(wire, planned.value, expectedRoot, retained,
    perProof, aggregate, wireBytes)
  if received.error != ProofViewError.None:
    return false # Framing, scope, budget or authentication failure grants no partial view.
  let time = received.value.readGlobalTime
  if time.error != GlobalProofError.None:
    return false # Missing, absent or malformed time is not a default timeslot.
  let entropy = received.value.readGlobalEntropy(entropyBytes)
  if entropy.error != GlobalProofError.None:
    return false # Authentication alone does not establish a complete entropy value.
  output = time.value
  true
```

`projectPlannedProofs` selects an exact bounded plan from already verified evidence without
rehashing and preserves its root. Missing requested evidence refuses atomically. Extra facts
cannot be encoded with `encodePlannedProofs` until an exact projection is selected. A projection
can retain proven absence, but cannot infer absence for a key missing from its source view.

## Decode the requested fields

Each reader uses the existing codec and requires the exact whole chapter, including rejection of
trailing bytes. Variable-size reads accept the codec's explicit configuration and bound cached
verified bytes before making a detached copy. Returned snapshots expose existing owner-bound
accessors; callers cannot mutate their backing storage.

| Chapter | Reader | Caller policy / result |
| --- | --- | --- |
| 1/2 pools and queues | `readGlobalAuthorization` | `AuthorizationKind`, `AuthorizationConfig`; immutable core rows |
| 3 recent history | `readGlobalHistory` | `HistoryConfig`; blocks, packages and optional peaks |
| 4 Safrole | `readGlobalSafrole` | `SafroleStateConfig`; roster, ring root, tagged schedule and tickets |
| 5 disputes | `readGlobalDisputes` | `DisputeStateConfig`; separate judgment/offender sets |
| 6 entropy | `readGlobalEntropy` | `ByteLimit`; four copied ordered words |
| 7/8/9 validators | `readGlobalValidators` | `ValidatorChapter`, `ValidatorStateConfig`; ordered roster |
| 10 availability | `readGlobalAvailability` | `AvailabilityConfig`; optional complete assignments |
| 11 time | `readGlobalTime` | Exact E4 value; existing `readProofTime` stays available |
| 12 privileges | `readGlobalPrivileges` | `PrivilegeConfig`; roles, assigners and gas allowances |
| 13 statistics | `readGlobalStatistics` | `ActivityConfig`; independent epoch populations and accepted compact gas |
| 14 ready work | `readGlobalReady` | `WorkQueueConfig`; reports and canonical dependency sets |
| 15 accumulated work | `readGlobalAccumulated` | `WorkQueueConfig`; canonical per-slot package sets |
| 16 output log | `readGlobalOutputs` | `OutputLogConfig`; ordered pairs, including repeated service IDs |

`readProofChapter` also captures any single chapter through existing `StateProfile` and
`StateChapterPolicy` validation, returning an immutable `StateChapterSnapshot`. It does not
convert partial evidence into a complete state mapping.

Handle `GlobalProofError` explicitly: `Uninitialized` means no valid owner, `MissingWitness` means
no evidence for that key, `AbsentValue` means authenticated absence, `InvalidValue` means a present
value failed exact typed decoding, and `LimitExceeded` means caller/native resource policy refused.
`InvalidConfig` rejects unsupported profiles/selectors; `InvalidInput` rejects malformed plan
selectors such as duplicates. No failed/default result grants `.value` access.

## Verification and remaining scope

Feature-owned native suites cover each reader and independent mixed global/service transport.
The mixed suite uses all 16 independently encoded composition chapters. Registered compiler
privacy probes and strict runtime assertion probes protect guarded alternatives; a positive control
performs completed extraction. The lifecycle suite exercises every typed family and all chapter
captures over 1000 ARC cycles, requiring unchanged live allocation after warmup.

These interfaces validate authenticated bytes and existing serialization contracts. They do not
validate signatures, execute state transitions, establish valid-state consistency, discover trusted
roots or add an RPC method/schema. Complete/light storage contracts remain distinct. M1 framing
and the current request namespace are implemented; full state serialization/STF parity remains open.
