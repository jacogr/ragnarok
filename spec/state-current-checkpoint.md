# Current prepared-update checkpoint qualification

State owns this read-only qualification boundary coordinated with PVM #6 at
`PreparedCurrentChainUpdate`, under Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. Capture only the genuine opaque
current producer; no detached map/header/profile can substitute for completion.

`captureCurrentUpdateCheckpoint` retains that original owner and bounded existing
V1 complete-map bytes from `currentUpdateState`. Copied observations distinguish
the sealed child's prior-state commitment from the computed posterior map root,
block/parent identities, slot, complete-map counts and wire extent. Finality is
the exact retained view's explicit selection, or typed `NoFinality`; C15/C16
completion never finalizes the child. Original encoding refusal and later copy
policy refusal remain distinct, and each byte export is independently owned.

This is synchronous stable host-graph work before enqueue or after collection/join.
Running, cancellation and scalar-observed Done still hold all existing leases;
copying/replacing/dropping capsule aliases also shares the retained canonical ARC
graph and must obey those rules. No Services/proof/preparation/disk worker or
installation behavior changes. Exported byte copies alone are detached.

Native witnesses use `prepareCurrentCandidate` with genuine admitted current
blocks and compare the entire expected phase-composed checkpoint. They prove
hash-free export, exact/short limits, independent output mutation, retained source
identity/scope and explicit inherited/absent finality. Those local authored
phase-composition answers are not independent published current-pin STF goldens.
Release-reference Bandersnatch versus Thin VRF, conflicting privilege allowances
and other scoped specification gates remain open. No new root/finality trust is
inferred. Run `make unit SUITE=state_current_checkpoint` plus owned strict guards.

Observed locally: genuine current producer/finality/extent/mutation/hash checks,
1,000 ARC cycles (726,304 bytes before/after), seven strict runtime and five
compiler rejections with signed positive control, inventory and pinned formatting
passed with checked ARC/Clang release on macOS ARM64. Linux CI remains separate.
