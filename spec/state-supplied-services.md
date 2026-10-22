# Bounded detached supplied service reconstruction

Scope: reconstruct full explicit service declarations from the retained
[supplied logical inventory](state-supplied-logical-inventory.md), without changing codecs, maps,
execution or evidence authority. Gray Paper/vector pins remain unchanged.

`copySuppliedServices` requires the immutable logical owner rather than compact hashed facts alone.
All service/child descriptor counts, native descriptor bytes, raw-key bytes, storage payloads and
preimage payloads are admitted under explicit service/fact/per-value/combined-byte limits before
any output array or copy is allocated. Fixed request histories and metadata are charged through their
own native descriptors. Aggregate subtraction and division prove multiplication/allocation safety;
combined retained output extent is capped at `high(int)`. A valid empty logical inventory succeeds
under zero limits; default owner and bounded refusal remain distinct failures with guarded output.

Reconstruction uses only the original compact fact identities, copied original raw keys and original
immutable snapshot payloads. It performs no hashing, even when the backend is unavailable. All
returned arrays and bytes are detached and mutable; changing them conveys no new validation
certificate and cannot alter retained keys, facts or source payloads. Source retention/copy/drop
uses the existing canonical ARC host gate; cancellation/Done does not release a worker lease.

This enables safe preservation/consumption of complete supplied declarations. It does not export a
producer manifest, propagate execution deltas, certify code availability, establish full current-pin
STF parity, grant root authority or select installation/finality policy. No Services, RPC, worker,
producer or storage change is introduced.

Verification includes exact/one-short whole-array descriptor/fact/key/payload budgets, caller output
mutation, present-empty/default distinction, full manifest rematching after projection, zero hashes
with backend disabled, strict runtime/compiler guards and 1,000 ARC cycles.

Observed locally: native cases and 1,000 ARC cycles passed at 166,736 bytes before/after;
two strict runtime and three exact compiler rejections with genuine complete-source control passed.
Inventory and pinned formatting passed on macOS ARM64 checked ARC/Clang release. Linux CI is separate.
