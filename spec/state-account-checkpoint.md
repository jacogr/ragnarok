# Expected-root checkpoint account checks

Scope: restore the existing complete-map checkpoint format and return a targeted
joined account-invariant certificate. `decodeAccountCheckpoint` requires the caller's
independently selected `StateRoot`, complete service declarations, profile and all
resource policies explicitly. It delegates unchanged expected-root restoration,
global serialization and exact manifest validation before capturing an immutable
inventory, checking footprints, request linkage, content hashes and exact-owner join.

Every phase preserves its actual nested failure through a guarded accessor; no
restored map, partial certificate or success prefix escapes failure. Linkage is
checked before detached content copying/hashing. Each phase has its own explicit
limits; this adapter does not claim a single aggregate bound across checkpoint,
manifest and predicate work. Checkpoint bytes and declarations are borrowed only
synchronously; success retains independent restored storage, never caller buffers.

The account predicates follow Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`text/accounts.tex`, eq:deposits and eq:preimageconstraints. Existing transport
format and root policy are unchanged. There is no disk I/O, installation, RPC
schema change, automatic root selection, economic or full STF validity claim.

Verification: independent complete-map fixtures, unchanged checkpoint bytes,
explicit wrong-root and declaration refusals, every bounded predicate phase,
malformed dependent metadata/content/linkage, input overwrite after completion,
1,000 complete graph ARC retirements and strict phase/private/nominal guards.
Run `make unit SUITE=state_account_checkpoint`.

Observed locally: affected native suite and 1,000 restored graph ARC cycles passed
(216,608 bytes before and after). Seven strict runtime phase/payload guards, nine
compiler privacy/root-domain rejections and genuine expected-root positive control
passed; inventory and pinned formatting passed.
