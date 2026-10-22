# Bounded current PVM handoff

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains unchanged.
This single-host adapter adds no protocol semantics or pins.

A `CurrentAccumulationHandoff` retains one prepared current chain update, or one unacknowledged
result. Busy admission does not inspect or replace its existing job. Cancellation drops only an
unattempted update; both installation success and refusal remain finished until taken. Default
slots/results grant no update/child authority. The handoff neither runs guests nor composes state,
hashes or captures children. Publication uses the exact prepared update and original history.

Canonical-only and enabled-RPC process methods attempt once. RPC checks exact history and lease;
refusal never falls back to canonical-only installation. Public phase observation and guarded
pending/result access expose immutable copies. These methods run on the serialized host; they
introduce no thread, disk IO, transport scheduler or unbounded queue.

Completion witnesses cover all slot transitions, cancellation/backpressure, stale parents, closed
and paused RPC, exact-lease installation, retained parent aliases, zero hash calls and 1,000 ARC
cycles. Source-owned compiler/runtime guard checks retain exact diagnostics. Native and module/
inventory/format checks record local macOS evidence separately from exact-head Linux CI.

Local macOS validation passed: 306 source modules; the genuine current handoff suite; all slot
transitions and exact RPC lease behavior; zero hash calls during processing; 1,000 ARC cycles;
three exact runtime guards and two privacy/nominal rejections; inventory and formatting.
Linked checks were serial. Exact-head Linux CI is separate.
