# Canonical read response validation

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab` CE128/129/143 and
Gray Paper `3861aed15d7d016a3a416e14e61fc67dddf6daec`, state Merklization appendix.
This layer validates collected outbound replies through the existing bounded application worker.
It does not execute blocks, certify consensus, adopt canonical state, install the executable node
or implement the remaining protocol families.

`read_validation.nim` accepts an exact request, bounded complete wire bytes, explicit local limits
and independently captured source metadata. Default/failure results carry no checked payload.
Successful `CheckedReadReply` owns immutable copied bytes and exposes only guarded accessors.
All E4 extents, item counts, canonical naturals and allocation limits are checked before narrowing
or growth. Aggregate wire input is capped at8MiB; blocks at64, state pairs at16384 and proof
nodes at512. Caller limits can reduce these ceilings. No parser exposes a successful prefix after
a later failure.

CE128 decodes every bare block using the locally configured profile and frame policy. It checks
request count, ascending exclusive/descending inclusive anchor hashes, parent links and strictly
ordered slots. Descending nonzero requests cannot succeed with an empty reply. Captured local
core, epoch and current-validator metadata constrain the decoding profile; the active population
is not assumed to equal three times the core count. An unknown queried block gains no trusted
state root or consensus authority from structural validation. GP execution, signatures and
candidate admission remain downstream requirements.

CE129 binds the requested block to its independently trusted posterior root. Boundary nodes are
canonical, duplicate-free, parent-before-child and restricted to the start/last returned paths.
The reusable `state/range_proof.nim` preserves GP's255-bit left-child commitments and reuses the
existing GP path verifier. Checking only boundary lookups is insufficient: covered subtree
commitments are also compared against a trie reconstructed from the sorted returned pairs, so
omitted or modified interior values fail. Compressed singleton leaves expand into virtual branches
only during comparison; no synthetic nodes become GP wire proofs. Request byte budgets retain
the protocol's single-pair exception.

`VerifiedStateRange` is partial evidence tied to the independent complete root, never a complete
full-state map or a root recomputed from partial state. Completion through the requested inclusive
end is reported only when the supplied commitments prove it. An empty start-only witness can
prove start absence while completion remains false. No peer root or announcement supplies trust.
CE143 verifies the full requested Blake2b256 content hash, including valid empty preimages.

`app/proof/read_validation.nim` captures only fixed trusted metadata, explicit limits and a fresh
wire copy. State source lookup is bounded to64 rolling snapshots or explicit retained finality;
it never traverses optional unbounded history. Preimage verification needs no state root. Jobs
retain no canonical map/header alias. `Services.beginReadVerification` admits this operation into
the existing single worker and exact canonical/RPC lease. Done and cancelled work retain capacity
and the lease until exact collection or joined shutdown. Busy admission cannot release a foreign
lease. The Services bridge remains full-state only; reusable root/proof mathematics does not
force light state through complete-map storage.

Verification:

- `state_range_proof`: independent full-map witnesses; complete and partial ranges; absent starts;
  uncertain empty completion; omitted/changed interior pairs; wrong roots, reordered, duplicate and
  off-path nodes; maximum-depth shared prefixes in both root halves; limits and immutable extraction.
- `jamnp_read_validation`: block direction/anchor/count/links/slots and malformed later blocks;
  full preimage hashes; actual canonical state responder bytes, trusted-source mismatch, malformed
  proof lengths, excessive canonical lengths and the single-pair byte-budget exception.
- `jamnp_read_verification_worker`: detached capture, busy/Done/cancel/stale tickets, output lifetime,
  joined shutdown and1000 cycles with balanced ARC memory.
- `jamnp_application_node`: actual outbound TLS CE129 reply followed by Services worker verification,
  corrupted-value refusal, exact canonical/RPC lease retention, cancellation and foreign-job shutdown
  isolation. Existing inbound routing and outbound framing coverage remains.
