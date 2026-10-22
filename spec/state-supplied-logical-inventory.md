# Retained supplied logical inventory

Scope: preserve the raw storage keys that compact `StateInventory` deliberately discards. Pins remain
Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and vector pin
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. PVM #6 confirmed this fills a real information-loss
gap for a future complete logical parent boundary, with no PVM producer change requested here.

`captureSuppliedLogicalInventory` accepts an original validated complete manifest, stable borrowed
full service declarations and explicit limits. It preflights extra service/key descriptors, key
count, each raw key, aggregate raw-key bytes and combined extra retained array bytes before any
allocation/copy/hash. Descriptor arithmetic uses division and subtraction, capped at `high(int)`.
Compact capture then revalidates every declaration against the original source under its independent
fact/descriptor/matching limits. Refused capture returns only the original guarded nested reason.
No unchecked constructor accepts an arbitrary compact inventory paired with a separate key list.

Success privately retains the newly captured exact inventory plus deep-copied raw storage keys in
the same nominal service/storage order. Preimage/request logical identities already reside in
compact facts; payload bytes remain in the original immutable snapshot. Fixed extra accounting
excludes separately charged compact arrays and fixed owner overhead. Bounded raw-key copy-out returns
fresh storage; present-empty raw keys succeed with zero copy budget, while invalid ordinals and
short budgets remain distinct errors. No default/failed key result can be extracted as empty success.

This is supplied-and-validated logical inventory, not producer-exported provenance or an execution
certificate. Profile/full-Parameters provenance remains with the higher current-state owner. Future
producer handoff must preserve exact parent snapshot identity and maintain all namespaces through
selected mutations, creation/deletion and rollback; untouched hashed namespaces cannot reconstruct
a complete logical manifest. Equal roots do not establish source-owner identity.

Capture, copy-out, retaining and dropping aliases obey the existing canonical ARC host gate before
enqueue or after collection/join. No worker, Services, RPC, storage API/format, execution or adoption
change is made. Full state semantics, current-pin STF parity and trusted-root policy remain separate.

Verification: complete independent source identity; equal-root different owner; caller/output mutation;
present-empty keys; exact/one-short key/count/descriptor/copy limits; prehash resource refusal;
full-width indices; guarded default/source/reason/key extraction; compiler privacy/nominal rejection;
1,000-cycle acyclic ARC retirement.

Observed locally: selected native cases, including omitted/duplicate/opaque declarations, passed.
1,000 ARC cycles held 214,592 bytes before/after; six strict runtime and five exact compiler
guards with genuine positive control passed. Inventory and pinned formatting passed on macOS ARM64
checked ARC/Clang release. Linux CI remains separate.
