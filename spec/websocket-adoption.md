# Stock WebSocket adoption evaluation

## Scope and decision

Evaluate `std/websocket` at the unchanged Nimony pin
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` (0.6.3). This is an independent
qualification experiment, with no production RPC transport changes or dependency patches.
No Gray Paper wire interpretation changes are involved.

**Do not replace the RPC transport yet.** Basic unsolicited delivery works, but bounded
RPC integration, local cancellation, and canonical-state exclusion remain adoption gates.
HTTP message retirement also needs upstream qualification under NIM-009.
The macOS listener now sets `SO_NOSIGPIPE` through its public descriptor before accept.
Its accepted connections survive slow-peer closure with catchable send errors and joined cleanup.
These results do not establish Linux behavior or the behavior of newer upstream revisions.

## Evidence and remaining gates

| Requirement | Observation | Required before replacement |
| --- | --- | --- |
| Subscription delivery | Eight upgraded peers receive the exact unmasked text frame `81 06 update` while independent server read tasks wait for client input. No subsequent client request triggers delivery. | Exercise real `RpcSession` publication, reply-before-notification ordering, subscription removal and bounded FIFO overflow through the replacement bridge. This fixture sends literal bytes, not RPC subscriptions. |
| Fairness | With one peer's receive buffer constrained and its writer sending 512 frames of 16 KiB, the other seven writers finish and their peers receive the exact update frame while the slow writer remains pending. | Prove bounded dispatcher admission, per-turn work and memory under sustained load. A finite eight-peer progress witness is not a scheduler fairness guarantee or a measured latency bound. |
| Cancellation | Aborting completed writers leaves all eight idle readers pending. Closing the independent peers releases the positive fixture's readers; all owners retire before pool shutdown. The slow-writer closure is tested in a separate process. | Establish an owner-safe, bounded local stop path for idle reads, blocked writes, queued notifications and shutdown without relying on remote cooperation. |
| Canonical-state exclusion | Probe tasks carry only owned transport halves, owned strings and pointers to fixed-lifetime atomic scalar observations. They import no application/query/canonical-state modules. | Keep decoding/routing and every canonical access on the dispatcher, retain `pauseChain`/`resumeChain` lease exclusion, and test concurrent publication, proof leases, disconnect and stale completions with a real detached-byte bridge. Probe isolation is not proof of that unimplemented bridge. |
| Process lifecycle | Import initializes the shared I/O runtime; shutdown stops its process-wide pool. Calling init again leaves the pool stopped. | Integrate startup and joined shutdown with all existing owners. An RPC listener cannot independently stop a process-global runtime used by other services. |
| Listener admission | The stock `listenHttp`/`listenTcp` path binds IPv4 wildcard; the probe's clients connect over loopback. | Preserve the production RPC listener's loopback-only binding through supported public APIs before adoption. |
| HTTP owner retirement | The stock handshake constructs `HttpMsg` owners; [NIM-009](nimony-reports-2026-11-08/http-message-retirement.md) records their retirement failure at this pin. | Qualify the upstream fix and complete connection cleanup; successful delivery alone does not discharge this dependency gate. |
| Peer failure | An unconfigured macOS listener reproduces SIGPIPE. Setting `SO_NOSIGPIPE` before accept makes the slow-peer assessment retire all owners cleanly through the stock error path. | Carry this ordinary Darwin socket configuration into a future transport owner. A configured listener must pass clean retirement; upstream patching is not required for this setting. Qualify supported hosts separately. |

The existing RPC server deliberately services at most one accept, one bounded read, one frame
and one write per slot per dispatcher turn. Publication uses connection-local, count/byte-bounded
serialized queues and closes only an overflowing consumer. These contracts remain the baseline;
using an asynchronous library does not discharge them.

## Public API observations

At the pinned library, `WebSocket.reader` and `.writer` expose move-only split owners. Use a
single writer owner per connection: the pair's `recv` automatically emits pong/close responses,
so its documented contract forbids concurrent use with another writer task. Bare reader `recv`
returns control frames for the writer owner to handle instead.

On macOS the probe configures `SO_NOSIGPIPE` on the listener before accepting any peers.
The accepted sockets inherit it. This uses the public descriptor and ordinary OS socket policy;
it changes neither library code nor the process-wide signal handler. A one-peer reset control
also changes from SIGPIPE to a caught `ErrorCode` with this option.

The stock upgrade defaults to a 1 MiB maximum message and no idle deadline. The probe observes
that default instead of imposing generic HTTP/framing policies. Future integration must still
honor existing RPC-specific origin/admission and resource contracts.

`streamio.Writer.abort` ends the write direction; it does not cancel a read half.
The pinned I/O runtime's descriptor cancellation operates only in the calling thread's lane.
Closing or mutating a half concurrently with its task would bypass ownership rather than prove
cancellation. This experiment uses neither private runtime hooks nor cross-task descriptor closure.

Passive waits may execute queued work on the foreground thread; callbacks are not inherently
bound to either the dispatcher or a dedicated I/O thread. The probe starts readers only after
foreground handshake I/O completes, then uses native sleeps to observe worker execution. Neither
thread identity nor immutable ARC handles grant canonical access: only the existing dispatcher
and lease contract can grant that authority.

## Reproduction

Run `make unit SUITE=websocket_adoption` for the positive public-API delivery, idle-reader and
joined-shutdown checks. It runs through the ordinary pinned native runner with an exact output
contract and no foreign application libraries.

Run `make assess-websocket-adoption` for isolated slow-peer closure. It compiles current source
using the shared checked ARC/Clang/ThinLTO profile and a private cache, enforces a 20-second child
runtime limit, and writes `build/tests/websocket-adoption/assessment.json` plus compiler/runtime
logs. On macOS the configured listener must reach `peer-close-retired`; SIGPIPE is a failed
assessment. An unconfigured platform may still report the witnessed `blocked-by-sigpipe`
blocker, never transport success. Every result remains `not-qualified` until the RPC integration
gates pass. Missing progress witnesses, arbitrary crashes, failed builds and timeouts fail
the assessment. The report records whether the Darwin listener option was enabled.
This optional experiment is not a new production failure policy or an expected-crash CI gate.

Only the independent raw test client uses `SO_RCVBUF=4096` to arrange backpressure; this is not a
server policy. Progress waits are bounded test allowances, not claims about guaranteed latency.
The unit and slow-peer process own no canonical state and replace no production tests.

## Next bounded work

A one-peer reset reproduction and a listener-option control were prepared for a maintainer
issue draft. The upstream issue search for SIGPIPE found no match on 2026-11-08; current upstream
was not executed. No upstream issue has been filed by this PR. Clarifying or changing upstream
defaults is separate from using the demonstrated public listener configuration here.

Design one bounded detached-byte bridge
between library tasks and the existing dispatcher. Prove cancellation and overflow ownership
before implementing it; then run real subscription, lease and service-lifecycle integration
scenarios on the supported hosts. Replacing the RPC transport is a separate decision after
those gates pass. A model of a hypothetical bridge would not prove the current implementation,
so this evaluation does not substitute a model for the missing integration.

## RPC subscription acceptance audit

The baseline is the existing dispatcher transport, independent of the stock WebSocket experiment.
The current coverage is concentrated in
[`test_rpc.nim`](../tests/unit/crypto/test_rpc.nim), with process/browser startup checks in
[`rpc_checks.py`](../tests/rpc_checks.py). Preserve these observable contracts when evaluating a
replacement; the library's literal `update` frame probe does not exercise them.

| Contract | Current witness | Replacement acceptance criterion |
| --- | --- | --- |
| Reply and event ordering | `publicationLifecycle` reads the subscribe reply before its initial notification and receives subsequent publications without a new client request. Its partial-output fixture preserves an existing reply's remaining bytes across publication. Session capacity checks drain exact initial-then-publication FIFO envelopes. | Keep an existing partial frame intact; send the subscribe reply before the initial event and preserve notification FIFO order. A reply takes priority over a queued event, not over bytes of a frame already being sent. |
| Cancellation | Session assertions cover invalid and wrong-family cancellation, repeated cancellation, notification-form calls, sequential batches, independent IDs and released queue bytes. The connected fixture now sends unsubscribe after its subscribe reply while its initial event is still queued, checks zero active/pending usage and observes no frame on the following turn. | An acknowledged cancellation removes only that connection's matching ID and its unsent queued events. A newly created subscription gets a fresh ID. Specify and test cancellation during a partially sent notification; the queued-event regression does not prove that race for a future task bridge. |
| Count and byte overflow | `capacitySession` fills sixteen messages and verifies refusal preserves the full prior sequence. `byteLimited` uses valid large statistics to cross the serialized byte ceiling and checks cancellation returns capacity. Publication fixtures cover both best and finalized overflow. | Keep count and serialized-byte bounds, preflight publication batches, and retire only the overflowing connection without rolling back accepted chain state. |
| Active-peer isolation | The connected publication fixture now fills an unread peer's real nonblocking kernel send buffer until even a one-byte send would block. Its RPC output remains pending while a separate subscribed peer receives each of sixteen exact publication frames, including publications after the slow connection overflows. An independent query client remains usable. | A stalled writer cannot prevent another connection from receiving notifications or processing requests. Retain fixed per-turn dispatcher work; this finite witness is not proof of starvation freedom under arbitrary request traffic. |
| Stream and selector isolation | Finalized-family assertions and connected publication checks distinguish best/finalized sources, suppress repeated finality, retain independent service selectors and isolate terminal errors. | Preserve source routing, terminal-error scope and connection-local diagnostics without retaining canonical owners in transport tasks. |
| Ownership and cleanup | Existing disconnect/ARC checks retire sessions and pending text. The proof-transport suite exercises `pauseChain`/`resumeChain`; this audit does not extend it. | Separately prove local reader/writer cancellation, stale-completion rejection and joined shutdown around real canonical leases. Existing synchronous session tests do not qualify asynchronous ownership. |

Run `make unit SUITE=rpc` for the audited native subscription baseline. The added socket cases
reuse this suite and its existing expected output/link profile; no parallel RPC harness or new
production policy is introduced. The unread peer's padding and small socket buffer arrange test
backpressure only. Healthy notifications are asserted on the actual wire while the dispatcher
continues ticking, rather than draining a session queue to make the test pass.

Remaining integration gaps are cancellation after a notification has begun writing, starvation
behavior under sustained identified requests, asynchronous shutdown/cancellation and stale
completion authority across lease transitions. Keep those distinct from already-covered FIFO,
queue cancellation and overflow isolation. Revisit the stock-library failure after the planned
Nimony upgrade; keep this evaluation PR draft until that qualification is available.
