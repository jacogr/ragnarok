# Proof-backed service state reads

## Scope and authority

Current Gray Paper commit `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
Appendix T and service accounts, owns the current 105-byte supervisor metadata and
bounded request namespace. Published release vectors remain historical corpora.
This increment consumes the authenticated [partial view](state-proof-views.md).
It does not turn a partial map into complete state, validate balances/footprints,
select a trusted chain root or change storage/PVM/Services interfaces.

The planned bounded progression is exact account metadata, bounded storage and
preimage reads, request-history reads and composed account-dependent queries,
followed by snapshot/selected-block generation, independent transport verification,
negative authority tests and lifecycle evidence. Each feature is published when ready.
No network RPC, light database or startup mode is introduced by this contract.

## Account reader

`readProofAccount` derives C(255, service), then requires exact current metadata
extent and canonical version zero through the shared codec. It preserves supervisor,
supervisor creation and both balances. Missing witness, authenticated absence and
malformed present data have distinct errors. A successful metadata read says nothing
about the completeness or consistency of unqueried nested storage/preimage maps.

Completion checks: literal field-offset witnesses including supervisor fields;
unknown and wrong-service witnesses; default view; proven absence; empty, truncated,
suffixed and unsupported-version values. Selected native suite:
`state_proof_service_account`. Full JAM serialization and STF parity remain open;
M1 framing is implemented, including the adopted bounded request-length domain.

## Storage reader

`readProofStorage` requires the exact account and storage facts in one view.
Orphan storage cannot establish an account; unknown account or storage evidence
remains `MissingWitness`. Raw keys use the shared reserved storage namespace, with
key limits before hashing and value limits before exposing the immutable lookup.
Present empty keys and values are supported. Suite `state_proof_service_storage`
covers those boundaries, account absence and one-short response policy.

## Preimage reader

`readProofPreimage` authenticates account and preimage in the same view, bounds
actual content before copying, and checks Blake2b against the advertised hash.
Malformed committed state cannot supply a different blob at a valid preimage key.
Empty present preimages remain valid; content/backend errors never become absence.
Suite `state_proof_service_preimage` covers content mismatch, missing evidence,
orphan entries, proven absence and exact/short output limits.

## Request reader

`readProofRequest` rejects both reserved lengths before any state/key work and
uses the shared request namespace and four canonical history shapes. Exact EOF
is required; malformed counts, suffixes and short slots are invalid committed
values. The maximum admitted scalar length does not size any allocation.
Suite `state_proof_service_request` covers all shapes and the current domain edges.

## Solicitation query

`proofPreimageRequested` reports true only for a canonical Requested history.
Proven absent accounts/requests are false; missing witnesses and malformed state
remain errors. An absent account short-circuits without demanding orphan history
evidence. Suite `state_proof_service_requested` covers all modes and negative facts.

## Historical availability

`readProofHistoricalPreimage` uses actual authenticated blob length to select its
request history. Account/content/history must come from one root; an unknown
history is missing evidence, while a proven missing history beside a present blob
violates the account invariant and is invalid. The pinned four-shape interval
equation uses an explicit query slot; that slot carries no independent chain-time
authority. No extra chronological rule is imposed. Unavailable logical values
return `AbsentValue`. Suite `state_proof_service_historical` checks exact interval
boundaries and incomplete/malformed dependency sets.

## Code resolution

`readProofCode` derives the code hash from this view's current metadata and
resolves that identity with the historical preimage reader. Detached alternative
code hashes cannot replace it. This resolves bytes only: program validation, PVM
execution and refinement-anchor provenance remain their existing owners' work.
Suite `state_proof_service_code` covers selection, time, quotas and missing history.

## Root-independent query plans

`ServiceProofPlan` retains a bounded canonical key set, with private immutable
ownership and guarded ordinal access. It requests evidence without certifying
state or trusting a root. `planProofAccount` requests only C(255, service).
Default plans are invalid; short count limits and invalid ordinals fail explicitly.
Suite `state_proof_plan_account` covers the owner and count contract.

## Storage query planning

`planProofStorage` derives the current namespace and includes the canonical
account dependency in a sorted immutable plan. Count/key policy precedes key
hashing. No plan grants state authority. Suite `state_proof_plan_storage` checks
exact namespace identities and short policies. Historical lengths are hints for
requested evidence; readers independently choose the actual authenticated length
and return missing witness if the hint omitted that identity.

## Preimage query planning

`planProofPreimage` derives the current namespace and includes the canonical
account dependency in a sorted immutable plan. Count/key policy precedes key
hashing. No plan grants state authority. Suite `state_proof_plan_preimage` checks
exact namespace identities and short policies. Historical lengths are hints for
requested evidence; readers independently choose the actual authenticated length
and return missing witness if the hint omitted that identity.

## Request query planning

`planProofRequest` derives the current namespace and includes the canonical
account dependency in a sorted immutable plan. Count/key policy precedes key
hashing. No plan grants state authority. Suite `state_proof_plan_request` checks
exact namespace identities and short policies. Historical lengths are hints for
requested evidence; readers independently choose the actual authenticated length
and return missing witness if the hint omitted that identity.

## Historical query planning

`planProofHistorical` derives the current namespace and includes the canonical
account dependency in a sorted immutable plan. Count/key policy precedes key
hashing. No plan grants state authority. Suite `state_proof_plan_historical` checks
exact namespace identities and short policies. Historical lengths are hints for
requested evidence; readers independently choose the actual authenticated length
and return missing witness if the hint omitted that identity.

## Code dependency discovery

`planProofCode` discovers current code identity from authenticated account
metadata, then requests its account/blob/length-hint history dependencies.
A plan grants no root authority and can be sent for another root; the eventual
code reader rederives identity from that response's account. A stale discovery
therefore fails on missing actual evidence rather than substituting stale code.
Suite `state_proof_plan_code` checks exact identities and refusal paths.

## Plan union

`mergeProofPlans` unions sorted immutable requested keys. Exact unique output
count and native extent are checked before allocation; shared account
dependencies coalesce. No hashing, root comparison or value conflict resolution
is involved because plans request facts without granting them.
Suite `state_proof_plan_union` checks shared dependencies, default inputs,
exact/short output quotas and preservation of both inputs.

## Complete snapshot batch adapter

The snapshot `generateStateProofs` overload preflights and copies complete state
once, then delegates the existing bounded atomic path-set generator. Raw query
order and duplicates remain supported; no multiproof compression or performance
claim is made. The single-path overload shares its unchanged complete-map
preflight. Suites `state_proof_snapshot_batch` and `state_snapshot_proof` cover
ordered membership/absence, limits, defaults and retained-source behavior.

## Semantic snapshot generation

`generateServiceProofs` reads only a valid plan's exact canonical identities
through the complete snapshot batch adapter. Count/native bounds precede key
copying and source traversal. Suite `state_proof_snapshot_plan` verifies exact
account/storage identities and rejects default plans and short aggregate counts.

## Selected-block batch adapters

`generateBlockStateProofs` and `verifyBlockStateProofs` bind ordered raw batches
to the explicitly selected block's posterior complete-state root. Failed/default
selections never fall back to zero-root state. Suite `chain_state_proof_batch`
uses a genuinely signed fixture and compares selected complete-state values.

## Selected-block semantic generation

`generateBlockServiceProofs` resolves the exact immutable plan against one
explicitly selected posterior map. Service identities are selectors rather than
root authority; default selection and invalid plans cannot generate a response.
Suite `chain_state_proof_plan` verifies the selected fixture's actual account.

## Exact response verification

`verifyServiceProofs` requires the plan's exact sorted selector set before any
hashing, then verifies every witness under an independently supplied root.
The stricter aggregate/view count and value quotas apply before crypto work.
No prefix view escapes a later authentication failure. Precise proof reasons
remain guarded by `ProofFailure`; missing/extra/reordered selectors are invalid
input. `matchesProofPlan` compares exact identities without cryptography.
Suite `state_proof_service_verification` checks selection, root and scope refusal.

## Exact local response encoding

`encodeServiceProofs` accepts exactly the requested key set and reuses RPV1
without any root trust field or new network protocol. Extra/missing selectors
refuse before encoding. Existing per-proof/view/wire ceilings still apply.
Suite `state_proof_service_encoding` checks byte identity with the shared codec,
exact/short framing budgets, wrong plans, extra keys and source preservation.

## Receiving local responses

`decodeServiceProofs` consumes canonical RPV1 with a separately retained exact
plan and independently selected root. Declared counts must match the request
before witness decoding. Shared framing/pre-copy aggregate quotas and atomic
authentication remain mandatory. Exact verified identities must also match;
wrong roots and malformed framing never return a prefix view.
Suite `state_proof_service_decoding` verifies round trips and receiving policy.

## Receiving tampering and late failure

`state_proof_service_tampering` rejects every strict wire prefix and every
one-bit octet mutation of a real two-fact response, plus suffixes and a replaced
last witness under a foreign root. No earlier verified prefix escapes a later
failure. Source evidence and an unchanged complete response remain readable
after all refusals. These are bounded authored transport tests, not fuzzing or
a public network-protocol claim.

## Independent namespace and full-map witnesses

Four frozen Python/hashlib maps independently encode current supervisor metadata,
account/storage/preimage/request keys and full trie roots. Cases span service0,
7, a multibyte index and uint32-max; preimages span0/1/32/33 bytes. Independent
direct partitioning computes roots without production sorting/codecs. Native
`state_proof_service_reference` checks typed reads, exact query-plan unions and
literal roots; two Python safeguards protect frozen bytes and an explicit key
equation. The fixture descriptor pins exact corpus bytes.

## Actual primitive refusal evidence

`state_proof_service_backend` measures and refuses every Blake2b prefix in raw
storage, content, historical and code reads and atomic response verification.
No failed prefix exposes a typed result or earlier verified subset. Account reads,
account planning, plan union/matching and encoding work with hashing refused.
Short key/count/aggregate quotas and reserved request lengths attempt zero hashes.
Recovery after each refused operation retains the original usable immutable view.

## Complete revision retention

`state_proof_service_retention` generates an account/storage response, publishes
a real complete-map successor with changed metadata and deleted storage, then
releases original complete owners. Old typed reads keep their original facts;
new reads prove deletion under the new root. Old transport refuses that new
root, detached value copies cannot mutate retained evidence, and the original
response remains independently verifiable under its own root.
