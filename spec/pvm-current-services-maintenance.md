# Current Services managed maintenance orderings

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains definitive.
These native witnesses exercise the existing current durable Services integration; they change
no runtime code, protocol rules, storage algorithms/formats or dependency pins.

`tests/unit/state/test_pvm_current_services_maintenance.nim` executes actual signed current input
through the managed preparation and disk workers. Four explicit orderings run with enabled and
disabled startup RPC:

- Maintenance while a current update is Pending retains the prepared update. After collecting
  maintenance, the next host turn submits its current publication against the same canonical parent.
- Maintenance after publication but before acknowledgment retains the current Finished result and
  the actual publication generation. Physical replacement never overwrites the IO receipt.
- An explicit one-byte journal threshold admits automatic maintenance in the host turn that collects
  current publication. Finished acknowledgment remains unavailable until maintenance is collected.
  Any actual pre-listener startup compaction has its own receipt and epoch; the test does not mistake
  that receipt for post-publication maintenance. Header-only replacement journals cannot cause
  repeated immediate compaction.
- Joined maintenance shutdown preserves an entered maintenance result or explicit NotExecuted while
  retaining the already-confirmed current publication and its acknowledgment. Explicit worker shutdown
  blocks further preparation, proof and publication until fresh startup. The test accepts its
  actual scheduler outcome and does not claim both outcomes occurred.

Running and synchronized Done both retain the RPC/graph lease. The suite checks scalar exclusion,
Busy producer admission, refused cancellation/duplicate maintenance and unavailable preparation/proof
work without touching borrowed canonical aliases. After collection it checks the actual maintenance
kind, success/cleanup and exact successor epoch, unchanged publication generation where captured,
exact installed current state identity, and single Finished acknowledgment. Enabled RPC witnesses
use real best-head subscription/query. Strict restart compares the exact head and every state entry
against independently composed current state after physical replacement.

Run `make unit SUITE=pvm_current_services_maintenance`. The suite provides selected deterministic
orderings, not exhaustive scheduler enumeration or a claim of process-wide allocator balance across
thread-local heaps. Managed physical failure variants, post-commit enabled-RPC refusal and production
transport migration remain separate work. Local macOS evidence does not establish exact-head Linux
CI or complete JAM/ThinVRF parity.

Local macOS ARC/Clang validation passed for all eight scenarios, including actual RPC witnesses,
strict complete-map reopen and the explicit stopped-backend restart gate. Focused semantic checking,
inventory and changed-source pinned formatter idempotence passed. Production and shared helper
sources are unchanged from qualified parent layers, so their existing checks remain applicable.
