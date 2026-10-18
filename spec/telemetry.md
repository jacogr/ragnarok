# Initial JIP-3 telemetry

Ragnarök's bounded proof peer can register with a JAM Tart collector and report its current
authenticated peer count approximately every two seconds, incoming handshake lifecycles, and
outgoing attempts, authentication outcomes and observed incoming/outgoing closures. Telemetry is disabled by default.
This is a JIP-3 version-1 subset, not a claim of full telemetry or validator functionality.

## Run

Append `--telemetry HOST:PORT` to an existing `server`, `client` or `mesh` invocation. Collector endpoints
accept numeric IPv4, `localhost` (IPv4 loopback), and bracketed IPv6 literals such as
`--telemetry '[::1]:9000'`. Ports must be decimal 1–65535. DNS names, IPv6 scope IDs and
unbracketed IPv6 endpoints remain unsupported. The advertised QUIC address can be IPv4-mapped IPv6 or IPv6 loopback,
matching the existing peer mode and actual bound UDP port.

Pass `--chain PATH` with an explicit JIP-4 JSON chain file. Both options are required together
and may appear in either order after the positional arguments. For example, after producing
the usual proof-peer certificate/key/public-key fixtures:

```sh
./build/ragnarok server 40000 a.cert.pem a.key.pem b.pub \
  jamnp-s/1/245becfe 10000 --chain /absolute/path/dev.json --telemetry 127.0.0.1:9000
```

Keep the existing positional mode argument, if any, before the option pairs. The retained `mesh`
command accepts the same trailing option pairs after its positional gate directory. No collector address or chain is
assumed when telemetry is absent. An invalid explicit endpoint, certificate or chain file fails
startup with a diagnostic. An unavailable collector never fails an otherwise valid peer session.

The chain file selects telemetry's network identity only: it does not initialize a state store,
connect bootnodes, implement block execution, or automatically replace the existing ALPN argument.
Select the matching ALPN explicitly. The proof peer remains a bounded test application.

The node ID comes from the existing local certificate's Ed25519 public key; no example identity
or private key is copied into registration. Genesis identity is Blake2b-256 of the complete
`genesis_header` byte string. It is a **header hash**, not the genesis state's Merkle root.
`protocol_parameters` is the exact 122-byte GP 0.8.0 fetch-parameter representation.
The loader checks JSON shape, required field uniqueness, hexadecimal syntax and supported sizes;
it does not validate genesis consensus rules or recompute `genesis_state`.

## Implemented events and behavior

- First frame on every TCP connection: node information, including explicit network parameters,
  genesis header hash, local identity/address, `Ragnarok`, `development`, GP `0.8.0`, and a note
  identifying the proof-peer limitations. Flags are zero; no PVM implementation is claimed in the note.
- Event 10: status, with current authenticated peers. Validator-role count, block-announcement
  streams, guarantee pools, availability shards and block-production preimage pools are zero:
  these facilities are not implemented by this peer. CE fixture responses are not a preimage pool.
- Event 20: explicit incoming refusal at the native connection-capacity limit, with the actual
  remote address and port. The current limit is checked after TLS authentication, so events
  21/23 precede this refusal. Refused connections occupy no admitted-peer slot and produce no
  incoming event 27. Missing address metadata produces a dropped observation instead.
- Events 21–23: incoming TLS handshake start, failure and success. Start captures the actual
  remote address before authentication; terminal events reference its event ID. Success copies
  the authenticated certificate's Ed25519 identity. Destruction of an unfinished handshake
  settles failure with an empty reason, including endpoint shutdown.
- Event 24: outgoing connection attempt, with the pinned remote Ed25519 identity and actual
  loopback destination address/port, emitted immediately before initiating the QUIC dial.
- Events 25/26: failed/successful outgoing authentication, referencing the attempt's event ID.
  Native successful-handshake evidence determines success independently of application exchanges.
  A pending attempt settles on timeout, synchronous failure or early exit; failure reasons are
  empty when the native transport does not expose a reliable diagnosis.
- Event 27: an authenticated incoming or outgoing connection closed, identified by its remote
  public key. Incoming peers retain the certificate identity at native connection admission and
  emit once from the corresponding close callback. The single-peer dialer requires both a
  successful native handshake and an observed native close. Failed handshakes never produce
  this event. The terminator is absent and the reason empty because these observations do not
  establish who initiated closure or why.
- Event 0: dropped observations, with first/last timestamps and the exact number of omitted
  events when the fixed send buffer cannot accept them.

Pre-TLS refusals, best/finalized blocks, sync, authoring,
execution, service, ticket and work-package events remain unimplemented. Incoming observations
use the pinned libraries' public TLS handshake start/done and SSL ex-data destruction callbacks,
with public LSQUIC socket-address access. TLS success precedes connection-slot admission and does
not imply an application exchange succeeded. Packets rejected before TLS starts remain outside
this observation point.

The incoming observer retains 64 fixed slots until each SSL object is destroyed. Overflow drops
observations rather than changing TLS admission; each untracked start and terminal outcome is
accounted for through event 0. Overflow terminal loss is observed at SSL destruction. Missing
address or certificate metadata is also counted as loss, never replaced with invented identity.
Callbacks only copy borrowed data into bounded queued frames. The exporter and correlation table
outlive engine teardown; shutdown makes one final nonblocking send and never waits for delivery.

Incoming connection admission uses LSQUIC's public peer-certificate API while TLS state is still
available. A separate fixed 16-slot table copies only the authenticated public identities,
matching the transport's admitted-connection limit. Closure clears the slot before reuse; missing
certificate metadata produces a dropped observation instead of an invented identity. This table
is independent of pending-handshake tracking, so handshake-observer saturation cannot assign
another peer's identity to a close.

Disconnections are limited to closes observed while the transport is alive, including graceful
closes and idle expiry. Destroying an otherwise live endpoint does not fabricate a close event.
Incoming peers rejected by connection-capacity admission never enter the retained peer table.
Mesh uses one exporter for both retained role engines and advertises its IPv6 listener address.
Incoming callbacks share the same event-ID sequence as outgoing attempts. Each actual dial records
fresh native authentication/close counter baselines, so reconnects cannot reuse an earlier outcome;
a suppressed fallback direction emits no attempt. Duplicate arbitration emits a close for each
connection actually retired, while status counts the single pinned remote peer once across both
engines. Endpoint destruction settles pending attempts but never fabricates disconnections.

Frames use E4 little-endian payload length, then canonical JAM encoding. Strings use the existing
natural codec. Status's core array has no length prefix. Event timestamps are microseconds from
2025-01-01 12:00:00 UTC; retry/status scheduling uses the monotonic clock.

The exporter owns one non-copyable TCP descriptor and a fixed 2048-byte send buffer. Each peer
iteration performs at most one zero-timeout poll and one nonblocking send. Partial sends resume
at the exact suffix. Scheduled statuses append behind queued lifecycle frames when space permits;
a coincident status deadline does not itself discard an observation. Connect/write stalls time out after five seconds; failures retry after five
seconds and resend registration. Implicit event IDs count every observation, including dropped
ones, and remain monotonic for the exporter lifetime. After reconnecting, registration is followed
by a dropped prefix covering all prior positions so later outcomes retain their original attempt
IDs. An outcome may reference an attempt covered by a dropped marker. ID exhaustion disables
the exporter rather than wrapping.

Lifecycle frames may append behind pending frames when the fixed buffer has room; sampled status
frames still coalesce while a send is pending. Appending never extends the original write
deadline. Pending data is discarded on disconnect or shutdown. There are no background threads,
persistent queues or blocking shutdown flushes. SIGPIPE is suppressed per socket/send. The existing dispatcher bounds its waits to 10 ms.

Chain input is capped at 8 MiB, nesting at 32 levels, serialized header at 256 KiB, certificate PEM
at 16 KiB, DER at 8192 bytes, and core count at 1–1024. These are implementation limits, not new
protocol constraints. All relevant input is copied into owned bounded metadata before polling.

## Specification and example provenance

Normative references:

- [JIP-3](https://github.com/polkadot-fellows/JIPs/blob/14b55b8135285c2239a5ada8a86337907bc17108/JIP-3.md):
  connection option, message encoding, node information, timestamps and events 0/10/20–27.
- [JIP-4](https://github.com/polkadot-fellows/JIPs/blob/14b55b8135285c2239a5ada8a86337907bc17108/JIP-4.md):
  `protocol_parameters` and `genesis_header` chain-file fields.
- The existing Gray Paper pin `07f041dabd073f9018b418e9ee72e79dd2185401`, GP 0.8.0:
  Appendix B fetch parameter encoding (`vendor/graypaper/text/pvm_invocations.tex`), header
  hashing (`text/header.tex`) and cryptography. No dependency or protocol pin was advanced.

The public interoperability fixture `tests/fixtures/telemetry-dev.json` was exported using:

```sh
polkajam --chain dev dump-spec dev.json
```

It is an example, never Ragnarök's default chain. Source: official
[nightly-2026-10-17 release](https://github.com/paritytech/polkajam-releases/releases/tag/nightly-2026-10-17),
`polkajam-nightly-2026-10-17-macos-aarch64.tgz`; the binary reports `polkajam 0.1.29`, `GP 0.8.0`.

- Archive SHA-256: `04489843c21e4ae80362a7fbec5c95caea414b52f0406550ab33290cf3377a12`.
- Fixture SHA-256: `c0e0dab1c242becf8ec2aa06916c74a3dc84ff9aca1c08a5df217a4d6bc4b1c3`.
- Genesis header hash: `245becfe7f091e38fcc013ce7d8dff1f2838588837d57ba6b6fbcdaf89abb76c`.

A bounded loopback capture of that binary's registration matched both the exported parameter
bytes and the independently computed header hash. This establishes example compatibility only.
The binary is not a project dependency, and no downloaded executable is needed for the tests.

## Verification

`make check-unit` includes native wire/metadata tests, malformed chain JSON/hex cases, independent
hash expectations, a saturated socket pair, partial-send continuation and ordered dropped/status
frames, a close queued exactly at a status deadline without spurious loss, incoming/outgoing event layouts, correlation across dropped samples, and event-ID exhaustion.
The native transport suite holds 65 unfinished TLS handshakes against the 64 observation slots
on both IPv4 and IPv6, then completes one, closes it, reuses its slot, and checks tracked failures
and overflow
losses during destruction.
`make check-guards` includes a native lowering probe rejecting copies of the TCP owner.
`make check-e2e` includes IPv4 and IPv6 reset/reconnect collectors and a real certificate-backed proof-peer
exchange with telemetry enabled, an unresponsive outgoing destination, and an attempt/outcome
spanning a collector reset. A real outgoing peer also starts behind a bound UDP gate: only after
a TCP reset, identical registration and dropped-prefix replay does the harness forward its opaque
datagrams. Authentication must reference the original, now-covered attempt ID; both peers must
complete eight CE 143 requests, while the client reports exactly one close without further loss.
The test-only relay has one joined worker and no user-space packet queue. Incoming reconnect
cases instead hold the server's reply flight in a bounded test-only relay (64 datagrams, 128 KiB),
release it after registration and dropped-prefix replay, and require the original incoming ID on
success or certificate rejection. The retained listener then accepts a fresh generation with a new
ID; successful generations complete the mixed eight-request CE workload and close exactly once.
The rejection callback runs at SSL destruction, freeing the first handshake slot before its next
use. Rejection produces no admitted-peer close. The normal service profile avoids the idle client's
two-second expiry while waiting for the exporter's five-second retry. It also checks exactly
one disconnect after a graceful outgoing close,
no disconnect for a failed handshake, and authenticated IPv6 peer loss despite an incomplete
application exchange. Incoming cases check success identity/address/correlation, certificate
rejection, graceful close, two distinct identities across expiry/slot reuse, and no close event
when the server shuts down with a live peer. Mesh captures check one registration per node,
listener-address advertisement, fallback without a spurious outgoing attempt, distinct correlation
IDs across repeated duplicate races, exact closure counts, zero/one unique-peer status and wrong-pin
rejection, using IPv4 and IPv6 collectors. Additional mesh timeout captures verify an unanswered
dial settles once as failure and destruction of a retained authenticated connection adds no false
close after duplicate arbitration. Python is only the
independent collector/test orchestrator;
production encoding, configuration, hashing and transport stay in Nim and the maintained ABIs.
`make check-modules` and `make format-check` cover the new sources automatically.

Capacity checks cover both IPv4 and IPv6 native listeners and a real IPv6 collector capture:
16 admitted connections remain live while the seventeenth is explicitly refused. Saturating the
separate handshake-observation table does not report a refusal. The pinned public
`lsquic_engine_packet_in` return values also cover version negotiation, resets and ignored packets;
they cannot establish a pre-TLS admission refusal and are not translated into event 20.

Expiry/teardown collectors wait for both remote authentication and the current connection’s
retained server slot before killing a peer or releasing an explicit stop gate. TLS-success
telemetry alone is not an admission barrier: a child cannot
expire merely because startup or the CI scheduler took longer than a subsecond fixture lifetime.
Telemetry failures retain their traceback in the E2E console and JSON report, and CI archives
per-scenario telemetry logs alongside the report.

Collector assertions count interleaved status frames in the event-ID sequence instead of assuming
adjacent lifecycle frames or fixed IDs. A registration test deliberately waits past one status
interval before dialing; duplicate lifecycle frames and loss markers still fail complete captures.


Collector-failure isolation also runs eight real mesh exchange/retirement rounds with one IPv4
and one IPv6 collector. Both collectors stop reading events during the first round, then reset
the TCP streams and remove their listeners for the entire second round. The remaining six rounds
run after fresh registration and a dropped prefix. Captures account for the prefix when checking
attempt/outcome IDs, remote identities and exactly-once closures; further loss markers fail.
The existing mesh assertions retain bidirectional CE exchanges, duplicate retirement, one dispatcher
thread, descriptor/RSS/allocation bounds and clean process shutdown throughout the collector outage.
A non-reading low-volume collector does not necessarily saturate the OS send buffer; deterministic
socket-pair unit tests separately prove fixed-buffer saturation, partial writes and exact loss counts.

## JAM Tart interoperability check

`make check-telemetry-interop JAMTART=/absolute/path/to/tart-backend` builds the current
Ragnarök peer, creates isolated fixture identities, and launches the explicitly selected collector
with `--no-database` on ephemeral loopback TCP/HTTP ports. It requires no PostgreSQL instance.
A separate Linux CI job runs `make check-telemetry-interop-ci` on every PR and master push,
building the pinned collector before running this check. It adds no production runtime dependency.
The six existing verification groups retain their scope; `make check` runs those six groups. Its hash-pinned WebSocket client lives in an ignored build-local Python venv.

The harness waits for a subscription acknowledgement, then requires a decoded two-core status
before starting a real authenticated CE 143 exchange. Both peers must finish eight requests.
JAM Tart's public WebSocket history must contain the expected incoming/outgoing attempts,
authentication outcomes, identities, addresses and exactly one close per peer, without loss or
failure events. Correlation is checked against each node's implicit event position: WebSocket
envelope IDs are collector-global and are not JIP-3 attempt IDs.

The collector remains an independent compatibility check, not the protocol authority. This
scenario covers registration acceptance and the implemented status/connection subset; it does
not establish database persistence, dashboard rendering, reconnect behavior in JAM Tart, or
support for unimplemented validator events. The normal tests retain their deterministic loss,
backpressure and reconnect coverage.

The reference collector for this check is
[JAM Tart](https://github.com/paritytech/jamtart/tree/76debc1b1b90889749d0129ca18ffdb5d96d17a4),
revision `76debc1b1b90889749d0129ca18ffdb5d96d17a4` (GP 0.8.0 update), pinned by the
`vendor/jamtart` gitlink. Reproduce the CI job locally with:

```sh
make check-telemetry-interop-ci
```

Make initializes the pristine submodule, builds `tart-backend` with the shared pinned Rust
compiler, `--locked` and `--no-default-features`, and runs the harness with that binary.
Cargo output stays under `build/jamtart-reference-target`. No database service is required.
CI retains build/setup logs and the harness report even when the job fails, excluding generated
fixture keys. The explicit `JAMTART` target remains available for checking another supplied binary.

No upstream sources or lockfile are patched. The caller controls the external binary; the harness
records its actual SHA-256 alongside the peer binary hash, decoded messages and verdict in
`build/tests/telemetry-interop/results.json`. Collector and peer logs are retained in that directory.
A failed build, startup, decode or assertion must remain a failure, not a skipped interoperability pass.
