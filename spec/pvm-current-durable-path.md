# Current signed block to durable RPC head

## Authority and contract

The pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains definitive.
No dependency pin, protocol interpretation, storage format or thread lifecycle changes here.

`confirmsCurrentDiskPublication` lets a host bind a confirmed worker generation to the exact
prepared current state identity, selected disk generation and complete selected application context.
It reads validated cached handles/metadata, without hashing, capture or file IO. Defaults, closed/
poisoned stores, stale generations, other state owners and different context refuse. A generation
alone does not identify the prepared history. This readiness check runs **after** collection/join;
all disk/publication/canonical graph aliases remain frozen while the native worker borrows them.
The caller must first retain the actual successful typed IO receipt; this predicate does not create one.

The native integration witness starts with a genuine signed block with two incoming guarantees,
actual lookup ancestors, available work and provided preimages. Missing ancestry refuses. The actual
current candidate path produces the independently assembled expected complete map. Both single-file
and managed backends then stage current publication, pause RPC, execute native IO, collect the exact
receipt, confirm its selected generation/state/context and install canonical/RPC handles under the
same lease. Actual WebSocket subscribers and best-head queries observe the captured child only after
installation/resume. Strict restart recovers the same complete state root and child history.
A foreign journal with equal generation and exact candidate state but different context refuses.

## Evidence and remaining boundary

Run `make unit SUITE=pvm_current_durable_path`, current candidate and chain regressions for the
extended fixture ancestry ownership, source/module/inventory/format checks, and the nominal gas/
generation rejection. Earlier source-owned current publication/runtime and native-worker ownership
contracts remain in force. Local macOS ARC/Clang evidence is separate from exact-head Linux CI.

Current source-bound phases, signed candidate, in-memory bounded handoff and native disk payload
APIs now have a complete integration witness. The default Services/transport preparation and
handoff scheduler still uses legacy types; switch that producer/consumer lifecycle in a later
coordinated tranche. This witness is not full client/JAM or ThinVRF parity, and does not change
M1 framing-versus-complete-state-serialization claims. Broader pinned PolkaVM fixture/fuzz CI and
performance work remain separate planned verification.

Local macOS validation passed: 306 source modules; complete current durable-path native witness on
both physical backends, real incoming-guarantee lookup refusal/success, typed worker receipt,
foreign equal-generation/equal-state context refusal, zero-hash host confirmation/install, actual
RPC subscriber/query delivery and strict reopen. Current candidate and chain coordinator regressions
passed with fresh 1,000-cycle ARC evidence after retaining original lookup headers. One exact nominal
gas/generation rejection, inventory and formatting passed. Linked suites ran serially. Existing
unchanged runtime/publication and ownership guards retain their earlier source-owned evidence;
this is not a fresh full CI or combined-upstream qualification claim.
