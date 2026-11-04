# Authenticated availability transfers

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab` CE137/138/140 and Gray Paper
`fad0ded4a433052397bf7234352a57fe491883f7`, General Merklization N/T/WB. Generate transfer
bytes only from genuine availability commitment provenance and verify received bytes against
an independently supplied expected availability specifier and exact shard/row coordinates.

GP T orders siblings from root to leaf. A singleton N child is the raw leaf, while a singleton
whole WB tree is hashed. Internal nodes hash ASCII `node` followed by their children, split at
ceil(n/2). NP proof discriminator 0 carries a hash, 1 a raw bundle-hash/segment-root pair and 2
a raw segment shard with the width derived from the validated erasure geometry. Each expected
node representation, message extent and suffix must be checked exactly before accepting data.

CE137 verifies the bundle shard and all ordered export/proof shards against the outer trace.
CE138 appends the segment-shard root to that trace. CE140 appends the bundle-shard hash and then
the selected row's trace. Row count is the exported segment count plus its 64-leaf proof-page
count; the original selected request and report determine coordinates and geometry, not peer claims.

Data copying and complete hash work have explicit independent ceilings. Default/refused results
expose no verified byte prefix. Successful received data owns independent immutable byte copies
and copied root/coordinate facts; proof success grants Merkle inclusion only, not chain inclusion,
a signature or canonical state. Run hashing/extraction under the managed CPU lease, never native
network callbacks. Transport dispatch/retention and actual CE133 recovery remain subsequent work.

Completion: cross-check genuine existing availability roots for empty/odd/full populations and
export/proof-page boundaries, independent trace witnesses, exact wire tags, truncations/suffixes,
wrong roots/coordinates/data, resource refusal, backend errors and repeated ownership release.

Observed local evidence: `make unit SUITE=jamnp_availability_merkle` and
`make unit SUITE=jamnp_availability_proofs` pass. Frozen independent hashlib witnesses
cover the GP singleton/internal-node distinction and odd root-first paths. Maximum
3120-by-1368 geometry also passes in an explicitly 512 KiB raw thread whose shared
ARC aliases remain untouched through join. Genuine existing commitments cross-check
six- and 1023-validator populations, zero exports, and the 64-export proof-page boundary.
Exact aggregate hash ceilings refuse work before extraction; malformed tags, data,
coordinates, truncated proofs and suffixes refuse complete transfers. Repeated release
runs keep occupied ARC memory unchanged for 1000 cycles in both suites.
