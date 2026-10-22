# Current Services memory lifecycle

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains definitive.
This adapter changes no protocol interpretation, dependency pins, RPC schema or storage format.

Services now admits genuine current raw input and grants the existing reusable native preparation
worker one exact managed RPC/canonical lease. Admission pauses RPC before submission. Busy,
cancelled, Running and Done work retain exclusion until exact collection or joined close.
Refused submission restores only its own lease. Current collection exposes only the worker's
`CurrentCompleted` result and never installs canonical state.

A separate explicit enqueue retains the actual `PreparedCurrentChainUpdate` in the current
handoff. Current and legacy producers share capacity: neither may enqueue while the other owns
pending/unacknowledged work. Preparation and proof generation remain unavailable throughout that
handoff. Legacy synchronous producer methods require the current slot idle. A later host tick
installs one already prepared current update, with exact RPC history whenever RPC was enabled
at startup. Closed or otherwise refused enabled RPC never falls back to canonical-only adoption.
No guest replay, capture, hashing or disk IO occurs during this current installation.

Finished success/refusal requires explicit acknowledgment; cancellation applies only before
installation. Shutdown joins preparation/proof/disk owners before retiring current handoff aliases.
RPC proof-session routing and pause/exclusion retain their existing ownership. Current disk-backed
enqueue is explicitly unavailable until its separate durability layer; production transport/download
producers still select legacy APIs at this point.

Completion witnesses use actual signed current children and an independently serialized complete
original parent chainspec. They cover native current preparation, unchanged head after collection,
shared backpressure and cancel-before-install, acknowledgment, enabled/disabled RPC, real best-head
subscriptions/queries, enabled-listener refusal without fallback, no-hash host installation,
malformed cancellation and immediate joined shutdown. Source-owned runtime/private/ownership
guards and affected legacy preparation/proof consumers remain required. Local macOS evidence is
separate from exact-head Linux CI and complete JAM/ThinVRF/production transport parity.

Local macOS ARC/Clang validation passed: current Services memory native integration, legacy
managed preparation-lease regression and actual proof-RPC regression (including its fresh
1,000-cycle ARC evidence); exact current acknowledgment runtime guard, private slot rejection
and actual composite Services `=dup` lowering rejection; Services/download/production-entry
semantic checks; inventory and changed-source pinned formatter idempotence. Linked checks ran
serially. Exact-head Linux CI has not been requested.
