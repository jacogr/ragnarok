# WebSocket JSON-RPC foundation

References: [JIP-2 at 14b55b8135285c2239a5ada8a86337907bc17108](https://github.com/polkadot-fellows/JIPs/blob/14b55b8135285c2239a5ada8a86337907bc17108/JIP-2.md),
Protocol and Methods; [JSON-RPC 2.0](https://www.jsonrpc.org/specification), updated 2013-01-04,
sections 4–6; [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455), sections 4–7.

## Usage and implemented scope

Append `--rpc-port 19800` to an existing `build/ragnarok server`, `client`, or `mesh` invocation.
The endpoint is `ws://127.0.0.1:19800/`. RPC is disabled when the flag is absent; an invalid port,
duplicate flag, or failed listener bind fails startup. It is independent of `--telemetry` / `--chain`.
The endpoint lives for the lifetime of the existing proof-peer session. It adds no standalone
node daemon or chain initialization.

Send a WebSocket text message:

```json
{"jsonrpc":"2.0","method":"ragnarok_clientInfo","params":[],"id":1}
```

`ragnarok_clientInfo()` is currently the only available method. The result includes:

- Implementation name, development version, pinned compiler version, Gray Paper version,
  target OS and architecture, and peer command role (`server`, `client`, or `mesh`).
- Milliseconds since RPC startup, observed connected peer count, and occupied/reserved ARC
  allocator bytes (not process RSS). Mesh counts its logical remote once across two role engines.
- `chain`, `bestBlock`, and `finalizedBlock`: null, because no live chain backend exists.
- RPC transport, loopback address, port, available method names, subscription availability,
  maximum message bytes and batch size.

No private keys, environment variables, command-line secrets or filesystem paths are exposed.
Ragnarok-specific extensions use `ragnarok_`. Standard JIP-2 methods retain their specified
unprefixed names when implemented. Currently **all JIP-2 chain methods, including `parameters`,
and subscriptions are unavailable** and return JSON-RPC `-32601` for identified requests.
This is the transport/diagnostics increment, not complete JIP-2 support. In particular an
unavailable block database cannot be reported as an empty chain or a successful subscription.

The next bounded increment should connect `parameters()` to validated chain configuration.
Best/finalized queries and subscriptions require an actual chain source with immutable
block/state snapshots and update events; they must not reuse telemetry's genesis metadata as live state.

## Protocol and bounds

Only WebSocket version 13 is supported; HTTP is used solely for the RFC 6455 upgrade handshake.
POST bodies are never dispatched as RPC. This increment accepts local non-browser tooling:
Origin-bearing requests are rejected. TLS, remote binding, browser Origin configuration,
compression, binary messages and subprotocol negotiation are outside this increment.

Input JSON is validated strictly before dispatch, including number spelling, object keys,
escapes, surrogate pairs, trailing data and duplicate envelope members. Parameters are positional
arrays or omitted. IDs preserve their numeric lexemes or decoded string values without machine
integer/float narrowing. Parse errors use `-32700`, invalid envelopes/batches `-32600`, unavailable
methods `-32601`, and invalid parameters `-32602`. Valid notifications never receive replies,
including errors and notification-only batches.

Parsing uses the pinned Nimony `std/parsejson` streaming API, which also underlies `std/json`.
The tree API converts numbers to integers/floats (including a lossy float fallback for large
integers), so RPC uses streaming numeric lexemes to preserve IDs. The stdlib owns structural
parsing and string decoding; a lexical policy rejects its non-JSON extensions (comments,
trailing commas, permissive escapes/numbers). The event adapter enforces string object keys,
a single root and resource limits before retaining each event. Decoded strings are checked
for valid UTF-8, and stdlib error state is checked even when it emits a string event.

The server accepts masked client frames, fragmented text with interleaved ping/pong, and valid
close handshakes. UTF-8 validation covers the complete reassembled text, so a fragment may split
one Unicode scalar. Server frames are unmasked. Framing violations close with 1002, binary data
with 1003, invalid UTF-8 with 1007, and cumulative oversized messages with 1009. Extended 64-bit
frame lengths are rejected because their canonical minimum exceeds the configured limit.

Resource limits are eight connections, 4 KiB upgrade headers, 16 KiB messages, 16 nesting levels,
2048 JSON values and 16 requests per batch. Input/output is owned per connection. Each dispatcher
turn performs at most one accept and one read (4 KiB), frame dispatch and write per slot. Responses
are bounded by the aggregate request-ID bytes plus sixteen fixed-size diagnostic results.
Backpressure pauses reads until the outstanding response is delivered. Handshakes, partial
messages, fragmented messages and queued writes have five-second budgets; idle upgraded
connections expire after thirty seconds. Ping/pong cannot extend a fragmented message's budget.

The listener/connection composite is explicitly non-copyable. ARC destruction and explicit close
retire native descriptors and owned strings; no foreign callback borrows RPC data. Mesh borrows
one stable stack owner only during its synchronous dispatcher loop. All sockets are nonblocking
and close-on-exec, and SIGPIPE is suppressed per socket/send.

## Verification

`tests/unit/codec/test_rpc.nim` covers JSON-RPC envelopes, batches, notifications, strict malformed
JSON, numeric/string IDs, Unicode boundaries, RFC 6455's published handshake example, every
truncated frame prefix, masking/length/control errors, fragmentation and repeated ARC destruction.
It is registered in `make check-unit`. `make check-guards` includes a lowering-level server-copy
rejection probe. `make check-modules` discovers the new modules automatically.

`tests/rpc_checks.py`, required by `make check-e2e`, independently encodes/decodes WebSocket
frames against the actual peer process. It checks upgrade verification, requests, notifications,
batches, malformed JSON, fragmented text with ping/pong, close handling, unmasked rejection,
HTTP POST rejection, saturated handshake expiry, three concurrent QUIC clients and clean shutdown.
`make check-python` verifies the updated inventories and orchestration. Local macOS results do
not substitute for the Linux CI groups.
