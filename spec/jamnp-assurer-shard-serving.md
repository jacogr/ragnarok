# Assurer shard retention and audit serving

Target JAMNP-S aa0e2b8498c0b1bc1725af2903704d701c6577ab CE137/138 and GP
fad0ded4a433052397bf7234352a57fe491883f7 General Merklization. Retain only a complete
verified distribution, bound to its independent expected specifier and exact shard.
Derive CE138 by appending the authenticated segment-shard root to the original outer
trace. Empty segment trees append zero. Do not retain full execution/state provenance.

Storage requires explicit count/byte limits. Private detached copies prevent the
caller's release from sharing non-atomic ARC ownership with a later worker. Replacement
is bounded oldest-entry eviction; duplicate root/shard entries require identical
expected metadata. Defaults, partial data, audit-only transfers and oversized entries
never populate the cache. Exhausted generations do not wrap.

Services owns the cache and freezes it throughout the existing exclusive CPU lease,
including uncollected Done. Reset and shutdown keep the source until exact collection
or join. CE138 shares existing fixed-request framing and the ordinary 8 MiB ceiling.
Storage/proof success grants Merkle inclusion only, not assurance duty, report inclusion
or signing authority. Automatic assurer acquisition and CE139/140 serving remain work
for their own complete protocol consumers.

Completion: derive proofs from genuine verified distributions including zero/odd/page
geometries, verify against independent roots, exercise refusal/duplicate/eviction/byte
bounds and external-owner release; real TLS CE138 after original report retirement;
reset/close at Done and unchanged ordinary read behavior, ARC release and owner checks.

Observed local evidence: the native availability suite passes genuine zero/odd/page
geometries, exact derived/original proof equality, independent verification, count and
byte eviction, duplicate/conflict and audit-only refusal. Its 1000 release cycles now
include private cache cloning and audit derivation; occupied ARC remains 711536 bytes.
All 33 live work/availability cases pass, including CE138 after report retirement,
external original-owner release at Done, mutation refusal during the lease, missing
shards, local abort and joined close. Existing client/canonical/validation/Services
suites pass; Services ARC remains 139360 bytes over 1000 cycles. Fresh actual Services
and worker copy lowering is rejected. Production build, format and inventory pass.
These are local scoped results, not full JAMNP-S completion or Linux CI evidence.
