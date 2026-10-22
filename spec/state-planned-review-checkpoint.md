# Explicit-root planned complete review checkpoint

Scope: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, unchanged
complete-map checkpoint format and existing targeted account review contracts.
`decodePlannedReviewCheckpoint` requires explicit root, complete logical service
declarations, state/economic profiles and independent serialization, inventory
and review-preparation policies. No root fallback, I/O, adoption or worker change.

Missing economic policy refuses before any restoration hash. Existing exact-root
typed restoration and compact capture precede frozen report preparation. All
report limits and economic arithmetic finish before account-content hashing;
linkage/content and same-source joins then produce the complete review. Nested
serialization/inventory/preparation/execution refusals retain their exact typed
reasons and expose no earlier source/review prefix. Undercoverage is observation.

Mandatory restoration/capture hashing is not avoided. Observer tests measure it
separately and prove report/arithmetic refusal has exactly one fewer successful
hash than the one-preimage success control. Forced first-content backend refusal
is an execution failure. Caller buffers are borrowed synchronously and can be
overwritten/released after success; output owns restored immutable storage.

Existing checkpoint API semantics, canonical ARC scheduling rules, full/light
separation and full current-pin serialization/STF gates remain unchanged.
Run `make unit SUITE=state_planned_review_checkpoint` with owning runtime/privacy
guards, a genuine success control and 1,000 ARC retirement cycles.

Observed locally: selected native phase/root/backend/ownership cases, 1,000 ARC
cycles (281,056 bytes before/after), six strict runtime and seven compiler
rejections with a genuine success control, inventory and pinned formatting passed
under checked ARC/Clang release on macOS ARM64. Linux CI remains separate.
