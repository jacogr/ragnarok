# Verified partial state read views

Use the [bounded proof contract](state-trie-proofs.md) and its unchanged GP/vector pins.
This feature collects already verified exact-key facts under one independently
supplied root. `ProofView` is deliberately distinct from complete `StateStoreSnapshot`.
It cannot authorize a state transition, root recomputation or checkpoint restoration.

Capture checks every lookup root, current count/value ceilings and duplicate keys,
then publishes one immutable sorted collection. Present-empty and authenticated
absence remain distinct. Path storage has the proof format's structural 249-node
per-entry maximum; logical value bytes have an independent aggregate ceiling.
Unknown keys must return MissingWitness, never authenticated absence.

Completion plan: immutable capture, exact-key lookup, same-root union, projection,
authenticated witness export, local collection encoding/decoding, a typed C(11)
reader, strict authority guards and usage/evidence documentation. No storage API,
Services lifecycle, proof RPC, network protocol or light-node database changes.
M1 framing remains complete; full state serialization and whole-block parity remain open.

Exact-key binary lookup now returns a verified fact only for a retained key.
Unknown keys, including all keys in an explicit empty view, return MissingWitness.
A retained absence fact succeeds with present=false; no missing value is fabricated.

Same-root immutable union coalesces only identical facts. It checks root identity
before combining, accounts unique output keys/bytes exactly and rejects conflicting
evidence rather than selecting a winner. Inputs and their retained lookups remain
unchanged after short-policy or foreign-root refusal. No cryptography is repeated.

Projection retains an explicitly requested subset under the original root. Missing
witnesses, duplicate requests and short output budgets refuse without changing the
source. A zero-key projection is a valid empty evidence view, not an empty state map.

Witness export returns detached query records holding immutable unverified paths.
A receiving consumer must verify them under its own explicit root. Tightened output
quotas precede record allocation; mutating exported records never changes the view.
