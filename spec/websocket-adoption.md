# Stock WebSocket transport implementation draft

This document records the split-half prototype. The production listener uses the
single-owner stream transport in [`src/rpc/wire_stream.nim`](../src/rpc/wire_stream.nim).

## Scope and decision

Implement a bounded `std/websocket` transport bridge at the November 9 Nimony pin
`fd9742bf1939a1b754144506e89a8acb0e7b747a` (0.6.3). No Gray Paper wire interpretation
changes or dependency patches are involved. The default CLI/Services transport remains the
existing RPC listener; this draft adds an explicitly selected dispatcher API and stock split-half
adapters, exercised together on the real wire.

**Keep this PR draft.** Real subscription delivery and dispatcher lease exclusion now have
implementation witnesses. Local cancellation, framing and deadline parity, and process-wide
runtime integration remain gates before switching Services. #2099 fixed the HTTP message
retirement leak tracked as [Nimony #2940](https://github.com/nim-lang/nimony/issues/2940).
The macOS listener sets `SO_NOSIGPIPE` through its public descriptor before accept.
Its accepted connections survive slow-peer closure with catchable send errors and joined cleanup.
Runtime qualification here is on macOS ARM64.

## Implemented boundary

`src/rpc/transport_bridge.nim` owns eight detached-byte mailboxes. Each retains at most one
16 KiB request and one 65535-byte response, with one output credit held until its writer completes.
A reader can additionally own one received frame while waiting to publish; session notification
FIFOs retain their existing count/byte limits. Each operation attempts one per-slot CAS and returns
`Busy` without blocking the dispatcher. Generations and reservation sequences reject stale
requests, responses and write acknowledgements. Shutdown freezes admission before scanning slots.
The bridge is one-shot; its stable storage outlives every borrowing task.

`Server.startTransport`, `dispatchTransport` and `closeTransport` reuse the actual RPC context,
sessions, publication queues and proof handoffs. Each turn considers eight slots and dispatches
at most one frame per slot. Output credit is reserved before canonical execution; a busy commit
retains the serialized reply without executing its method twice. Binding to the reservation's
actual generation prevents a snapshot/reuse race from inheriting another session. The existing
chain lease refuses dispatch and shutdown before canonical context construction.

`src/rpc/websocket_transport.nim` moves one stock reader and one stock writer into separate tasks.
Those tasks import no canonical/query/server owners: only detached bytes and scalar tickets cross
the bridge. The application retains route, origin and message-size policy; the stock library owns
HTTP/WebSocket parsing. Ping and normal close responses go through the sole writer. IO polling
on the caller lane happens before dispatcher entry because passive tasks may execute there.
`closeTransport` retires mailboxes and RPC owners, **not** blocked socket tasks. The caller must
join those tasks before releasing bridge/state storage or stopping the shared runtime.

## Evidence and remaining gates

| Requirement | Observation | Required before replacement |
| --- | --- | --- |
| Subscription delivery | Eight upgraded peers receive the exact unmasked text frame `81 06 update` while independent server read tasks wait for client input. No subsequent client request triggers delivery. | The real stock-wire suite additionally checks subscribe reply, initial event, unsolicited block publication and unsubscribe; the detached dispatcher suite checks overflow. Extend to all subscription families and partial-send cancellation before replacement. |
| Fairness | With one peer's receive buffer constrained and its writer sending 512 frames of 16 KiB, the other seven writers finish and their peers receive the exact update frame while the slow writer remains pending. | The bridge now bounds admission, mailboxes and per-turn dispatch; its real RPC fixture isolates a held slow-writer credit while a healthy subscriber progresses. Qualify sustained load and scheduler behavior. A finite eight-peer progress witness is not a scheduler fairness guarantee or a measured latency bound. |
| Cancellation | Aborting completed writers leaves all eight idle readers pending. Closing the independent peers releases the positive fixture's readers; all owners retire before pool shutdown. The slow-writer closure is tested in a separate process. | Establish an owner-safe, bounded local stop path for idle reads, blocked writes, queued notifications and shutdown without relying on remote cooperation. |
| Canonical-state exclusion | Probe tasks carry only owned transport halves, owned strings and pointers to fixed-lifetime atomic scalar observations. They import no application/query/canonical-state modules. | The implemented bridge imports only atomics. Real dispatcher tests cover lease refusal/resume, publication, reused sessions and stale completions. Qualify complete Services/proof-worker lifecycle on supported hosts. |
| Process lifecycle | Import initializes the shared I/O runtime. Shutdown joins the workers, and calling ring init again leaves the worker count at zero. The standalone pool can be restarted separately. | Integrate startup and joined shutdown with all existing owners. An RPC listener cannot independently stop a process-global runtime used by other services. |
| Listener admission | The RPC stock wire suite checks that the bound socket is IPv4 loopback and that startup refuses an occupied port. | Integrate admission and listener shutdown with the process owner. |
| HTTP owner retirement | The November 9 pin retains zero bytes in the original retirement probe. #2055 verified stock HTTP parsing and peer cleanup on this pin. | Check complete stock transport owner cleanup when integrating Services. |
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

The stock upgrade defaults to a 1 MiB maximum message and no idle deadline. The original probe
observes those defaults. The implementation adapter passes the existing RPC 16 KiB message limit
and retains endpoint admission. Independent write/idle deadline parity remains open. The bare
reader exposes `ProtocolError` but not its private `failCode`; this draft aborts failed reads
instead of claiming the existing 1002/1007/1009 close-code behavior is preserved. A peer close
without a status becomes the stock writer's default 1000 close. Qualify these differences before
switching Services; no parser compatibility patch is introduced.

`streamio.Writer.abort` ends the write direction; it does not cancel a read half.
The pinned I/O runtime's descriptor cancellation operates only in the calling thread's lane.
Closing or mutating a half concurrently with its task would bypass ownership rather than prove
cancellation. This experiment uses neither private runtime hooks nor cross-task descriptor closure.

Passive waits may execute queued work on the foreground thread; callbacks are not inherently
bound to either the dispatcher or a dedicated I/O thread. The integration driver explicitly polls
its caller lane before entering the canonical dispatcher. Neither
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

The bounded bridge and real stock-wire subscription path are implemented. Next, qualify an
owner-safe local cancellation API, independent deadlines and failure-close metadata with the
public library. The stock wire suite now runs through a loopback-only listener. Process-wide
Services startup and joined shutdown remain separate qualification work.
The synchronous slot-reuse and stop-admission regressions pin concrete interleavings; concurrent
producer tests exercise actual mailbox contention. These witnesses do not claim complete
scheduler fairness or local cancellation of stock socket operations.

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
queue cancellation and overflow isolation. Revisit stock-library lifecycle and error metadata after the planned
Nimony upgrade; keep this implementation PR draft until replacement qualification is available.

## Implementation checks

Run `make unit SUITE=rpc_transport_bridge` for byte bounds, ownership on refusal, output credit,
late acknowledgements, concurrent producers and frozen shutdown admission. Run `make unit SUITE=rpc`
for the actual dispatcher/session integration, including lease exclusion, generation reuse,
reply ordering, slow-peer isolation and overflow. The original eight-peer and isolated peer-close
assessments remain separate witnesses for the split-half prototype.

Run `make unit SUITE=rpc_stock_websocket` for the production listener. An independent masked
client exercises subscription delivery, unsubscribe, ping/pong, and replies after a peer
half-closes its write side. The suite also checks shutdown with an idle client and a blocked writer.
