# Current one-child download reception

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains definitive; CE128 framing
retains the existing pinned networking contract. No dependency, protocol or storage pin changes.

`CurrentBlockDownload` is an independent nominal receiver over `CurrentBlockInput`. It emits the
exact ascending one-child request from the captured complete canonical parent, checks the bounded
E4 response extent before allocation, copies fragments and requires both actual FIN observations.
Callbacks do no decoding, hashing, execution or publication. Empty, truncated, oversized, trailing
and stale-generation outcomes never authorize current execution. Terminal outcomes require explicit
acknowledgment; mutable raw storage and worker-borrow state remain private and non-copyable.

Only explicit managed preparation after native stream retirement lends Ready input to Services.
Running, cancellation and Done keep receiver, input, canonical history and RPC leases stable until
collection or joined retirement. Collection accepts only CurrentCompleted and enqueues the actual
PreparedCurrentChainUpdate into the current handoff. A later Services tick and acknowledged result
still determine actual adoption; successful reception or preparation alone never implies it.
There is no synchronous preparation entry point on this receiver.

NeedsAncestors retains the original certified current prefix and generation after collection.
Bounded explicit resumption validates supplied original-history headers without hashing or guest
work, then returns to Ready for a later native submission. Cancellation while Preparing is refused;
worker cancellation/retirement must end the exact lease first. Unexpected worker/startup/preparation
and handoff failures retain only their selected actual typed reason.

The native suite covers all framing splits, fixed request bytes/defensive copy, both FIN orders,
empty/truncated/oversized/trailing and stale callbacks, actual signed current execution, completed
cancellation, Done exclusion, joined retirement, real two-guarantee ancestry suspension/resumption,
complete independent current roots and deferred adoption. A distinct 1,000-cycle reception-only ARC
workload claims no process-wide/threaded allocator balance. Source-owned compiler/ownership and
runtime extraction guards remain required. Run `make unit SUITE=pvm_current_block_download`.
The native stream/session/dispatcher and production command still select legacy adapters until
subsequent layers explicitly integrate this receiver. Local evidence does not establish Linux CI,
sustained load, full JAM or ThinVRF parity.

Local macOS ARC/Clang validation passed: native signed framing/worker/ancestry/deferred-adoption
suite, 1,000 reception-only ARC cycles, private/nominal/actual composite duplication compiler guards,
seven runtime extraction guards, inventory, focused semantic checking and pinned formatter idempotence.
Existing legacy and current dependency sources are unchanged; their prior evidence remains applicable.
