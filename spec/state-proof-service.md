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
