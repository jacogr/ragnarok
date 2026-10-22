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
