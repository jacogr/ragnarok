# Source-bound preimage content checks

Scope: `src/state/preimage/content.nim` implements only the first conjunct of
Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, `text/accounts.tex`,
eq:preimageconstraints: every present preimage's raw bytes hash to its declared
Blake2b-256 identity. Request membership is a separate invariant.

Input must be a complete exact-matched immutable inventory. Row count, preimage
count (including empty values), individual detached value bytes and aggregate
input bytes are preflighted before any value copy or content hash. The source's
captured physical identities and lengths select the original retained payloads.
Late backend failure or hash mismatch exposes only the service and local nominal
preimage ordinal, never a prefix certificate. Resource refusal and malformed
content remain distinct. Default results/certificates grant no authority.

Success privately retains the exact original inventory and fixed completed hash
work observations. No new payload arrays are retained. This certificate alone
confers neither request linkage nor global/account/STF validity or root trust.

Verification uses independently encoded complete fixtures and the literal
Blake2b-256(abc) digest, a changed-payload complete map, exact and one-short limits,
a hash observer proving zero calls on all preflight refusals and empty sets,
backend refusal, full positive controls, runtime/private/nominal guards and
1,000 ARC retirement cycles. Run `make unit SUITE=state_preimage_content`.

Observed locally: selected native suite and 1,000 ARC cycles passed (214,256 bytes
before and after); four strict runtime refusals, seven compiler rejections and the
genuine content control passed. Inventory and pinned formatting passed.
