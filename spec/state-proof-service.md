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
