# Current Services durable publication

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains definitive.
This integration changes no protocol rules, dependency pins, storage formats or storage algorithms.

Services accepts actual `PreparedCurrentChainUpdate` results for disk-backed operation. One host
tick preflights the exact canonical parent and enabled RPC history, retains its own RPC pause lease,
and stages a `PreparedCurrentDiskPublication` through the existing bounded context API. The current
handoff moves from Pending to Publishing before the shared native worker receives the operation.
During Publishing, current and legacy producers, preparation, proof generation and maintenance remain excluded.

The worker only owns disk IO. Running, cancellation and Done retain every graph borrow until exact
collection or joined shutdown. `diskPublicationPhase` observes only synchronized scalar state;
Done grants no canonical, pending-update or receipt access. No graph-bearing result is exposed by
new accessors while a native preparation, proof or publication lease remains active.

After collection, Services preserves the actual IO result and requires
`confirmsCurrentDiskPublication` to match the saved current publication, selected generation,
exact state owner and complete cached context. Only then may it install the prepared canonical
update and enabled RPC view under the same lease. Completion never fabricates a successful IO
receipt from a ready worker, staged update or successful application installation. The confirmed
host completion reads cached owners and does no hashing, replay or synchronous disk IO.

Actual IO failure, uncertainty or mismatched confirmation freezes further disk work and retains
its typed reason. Staging and worker admission refusals remain separately observable. Queued work
that was never executed yields a refused handoff and no IO success. Joined shutdown uses the same
receipt/confirmation/install path before retiring aliases. Finished results require explicit
acknowledgment; cancellation cannot interrupt publication. Managed maintenance can follow current
publication under the same existing maintenance policy and temporarily delays acknowledgment.

`tests/unit/state/test_pvm_current_services_disk.nim` supplies actual signed current execution,
independent complete original-parent startup, both disk layouts, enabled/disabled RPC, bounded
backpressure and Done exclusion, actual receipts, zero-hash host completion, real WebSocket best-head
subscription/query, and strict restart with every key/value compared to independently composed
current state. Run `make unit SUITE=pvm_current_services_disk`; the memory, legacy disk boundary
and managed maintenance suites remain affected regressions. Current disk uncertainty/fault injection
and managed maintenance interleavings need additional Services-specific witnesses; lower-level
current disk/worker tests remain independent evidence. Local macOS qualification does not establish
exact-head Linux CI, production transport migration or complete JAM/ThinVRF parity.

Local macOS ARC/Clang validation passed for the new four-combination integration suite, current
Services memory, legacy disk failure/shutdown boundaries and managed maintenance. Private current
publication and actual composite Services duplication compiler guards passed. Services, both download
consumers and the production entry point passed semantic checks, together with inventory and
changed-source pinned formatter idempotence. Linked/resource checks ran serially.
