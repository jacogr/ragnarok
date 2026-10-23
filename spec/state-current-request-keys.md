# Bounded current continuation request-key companion

Compact inventory already preserves logical request hash, advertised length and tagged history.
Current continuation needs its physical request key to inspect the actual immutable successor
without hashing during later policy planning. A separate private CurrentRequestKeys owner retains
original PreservedCurrentIdentities and caches only fixed physical keys. This does not change
inventory storage, complete snapshot format, producer events or any storage/proof API.

Whole service/request cardinality and native descriptor/key bytes are admitted before allocating
arrays or invoking key derivation. Exact original request codec/backend refusal remains distinct
from resources, invalid provenance and invalid nominal ordinals; failed partial arrays are dropped.
Fixed source/info/key observations hash nothing after capture. Capture performs exactly one maintained
request-key derivation per original declared request, with no payload copies or history decoding.
These keys grant bounded observation only; full actual successor logical matching remains required.
Shared canonical ARC graph copying/retention/retirement obeys the before-enqueue or after-collection/join gate.

Observed locally: selected native suite, five strict runtime guards, five compiler privacy/nominal
rejections, genuine signed control, pinned formatting and inventory passed. Capture performed exactly
four derivations; one-short resource refusals and cached queries hashed nothing; backend refusal
retained RequestError.BackendFailure.1,000 ARC cycles retained138,112 bytes before/after.
