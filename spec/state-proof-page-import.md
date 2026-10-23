# Complete state from authenticated pages

`importProofPages` consumes stable borrowed verified `ProofView` pages against an independently
selected root. Pages may arrive in any order and overlap, including absent and present-empty facts.
Exact repeated facts coalesce; contradictory facts refuse. Root agreement and page counts alone do
not prove completeness: only rebuilding the entire distinct present map and comparing its root
publishes an independent `StateStore`. Missing pages ordinarily return `Incomplete`.

The caller supplies independent page, total delivered lookup (including duplicates/absence), heap
scratch, distinct descriptor/value-copy and inherited complete-store policies. Every input root and
lookup count passes before scratch allocation. A fixed page-head min-heap performs two sorted
passes: the first admits every distinct present descriptor and payload before any value copying or
commitment hashing; the second copies only admitted distinct values. Work is bounded by delivered
lookup count and logarithmic page-head maintenance, rather than repeated growing proof-view unions.
Empty input can restore only the independently selected empty-map root. Failure exposes no prefix;
original pages remain usable for recovery. No format, root trust, producer, adoption or finality
contract changes. This is complete physical restoration, not current producer provenance.

`importSuppliedProofPages` composes the same restoration with all-global decoding, exact complete
manifest matching and raw-key retention. It shares the original single-view typed qualification
implementation and preserves its guarded nested failures. Partial pages, omitted service declarations
and late raw-key quotas expose no earlier successful typed prefix. Inputs remain stable for the
synchronous call. Explicit supplied declarations do not become producer mutation evidence.

Scope preserves Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and vector
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`; no protocol semantics change.

Verification: `make unit SUITE=state_proof_page_import` covers reverse/overlapping delivery,
31 heap sizes, absent/empty facts, exact and short policies, wrong roots/default views, genuine
backend refusal/recovery, incomplete/empty maps, detached ownership and 1,000 isolated ARC cycles.
`make unit SUITE=application_paged_logical_proofs` uses actual managed reverse-order responses
for direct reconstruction and existing complete schema/raw-key/code observations. Existing strict
result accessors remain guarded. M1 framing is complete; independent current-schema STF sources,
producer mutation provenance and current Thin VRF qualification remain separate gates.
