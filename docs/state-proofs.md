# State trie proofs

State proof APIs verify one serialized key against an independently trusted complete
state root. They return either authenticated presence (including an empty value),
authenticated absence, or a typed failure. A missing proof is a failure, never absence.
Proofs do not establish root trust, block validity or complete state availability.

Use `state/trie_proof` for immutable witness capture, verification, generation,
ordered batches and local envelope encoding. Use `state/snapshot_proof` to generate
from a complete immutable `StateStoreSnapshot`; this adapter uses existing public
reads. `chain/state_proof` binds operations to an explicitly selected block result
and its posterior map root. The header prior-state root belongs to its parent.

Supply independent policies for complete-map construction, each proof's nodes/value
bytes, aggregate batch counts/nodes/value bytes and transport bytes. Bounds are
checked before cryptography; native allocation failure retains the project's
fail-stop policy. Query order and duplicates remain explicit. Batch failure exposes
no verified prefix. Generation currently commits the bounded topology independently
for each query; it is not a compressed multiproof or a performance optimization.

Capture and decode return unverified witnesses. Call `verifyStateProof` with your
trusted root and exact `StateKey`, inspect `error`, then use the verified lookup's
`present` before reading detached `bytes`. Wrong root/key placement, wrong value
preimages, backend failure or exhausted policy never return lookup authority.
A different neighboring leaf may prove absence without disclosing its long value.
Raw inline terminal nodes still expose their embedded bytes; proof transport is not
a general value-confidentiality mechanism.

The project-local RSP1 envelope contains `RSP1`, an E2 node count, an E4 supplied-value
length, canonical 64-byte nodes and supplied bytes. It excludes root and query
identity. Decode consumes exactly one envelope and rejects every suffix or unknown
version. This is not a JAMNP-S message. No proof RPC or network discovery is added.

Proof owners are immutable and retain no mutable source sequences. Complete snapshots
and verified partial evidence remain different types; partial evidence cannot enter
`StateStore`, complete-state publication or checkpoint restoration as a complete map.
Retaining proofs retains their own path/value storage until ARC releases the owners.

See [the contract and evidence](../spec/state-trie-proofs.md) for pinned authorities,
independent frozen paths, published full-map roots, refusal/ownership witnesses and
reproduction commands. M1 framing is complete; complete state serialization and
whole-block JAM/STF parity retain their documented independent gates.
