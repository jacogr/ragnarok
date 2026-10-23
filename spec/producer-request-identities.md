# Producer-owned request identities

Scope preserves Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and vector
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`; existing solicit/forget/new semantics and domains
remain unchanged. This adds optional evidence for the current logical continuation consumer.

`requestFacts` independently enables bounded first-touch `(service, hash, length, physical key)`
facts at successful solicit, forget and new-account seed request operations. Zero disables capture
and queries explicitly. Full public lengths are retained; no inversion of a physical hash or guess
from payload bytes supplies logical identity. Fixed descriptor bounds precede fact allocation and
candidate account-map Merklization/publication. Capture reuses already derived canonical keys.

An actual expired forget records `removedPreimage`; this observation remains sticky on that selected
immutable lineage, including later request recreation. It is not a last-value record or complete
operation log. Repeated identical request identities coalesce, while physical collisions with
conflicting raw identity refuse. Only matching successful map publication binds a prepared fact;
failed/quota/backend operations retain the original context unchanged.

All immutable successors preserve facts. Checkpoint and actual terminal normalization select the
matching regular/exceptional trace. Parallel annulment and complete producer history composition
remain follow-up work before a request namespace continuation claim. Copied public facts are fixed
observations, not independently constructible producer certificates; only their original opaque
context owns membership authority.

Verification: `make unit SUITE=accumulation_request_identities` covers genuine direct and dispatcher
operations, first touches, repeated request deletion/recreation, expired preimage removal, new-account
seed identity, copy mutation, full-width bounds, descriptor quotas, late backend failure/recovery,
checkpoint/panic/out-of-gas selection and 1,000 balanced ARC cycles. Existing solicit/forget/new and
current guest consumers, strict result guards, inventory and both formatting gates apply.
M1 framing is complete; full independent current-schema STF, current Thin VRF and ambiguous
privilege gates remain separate.
