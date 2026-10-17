# Initial JIP-3 telemetry

Ragnarök's bounded proof peer can register with a JAM Tart collector and report its current
authenticated peer count approximately every two seconds, incoming handshake lifecycles, and
outgoing attempts, authentication outcomes and observed incoming/outgoing closures. Telemetry is disabled by default.
This is a JIP-3 version-1 subset, not a claim of full telemetry or validator functionality.

## Run

Append `--telemetry HOST:PORT` to an existing `server` or `client` invocation. This increment
accepts numeric IPv4 collector addresses and `localhost`; DNS names and IPv6 collector addresses
remain unsupported. The advertised QUIC address can be IPv4-mapped IPv6 or IPv6 loopback,
matching the existing peer mode and actual bound UDP port.

Pass `--chain PATH` with an explicit JIP-4 JSON chain file. Both options are required together
and may appear in either order after the positional arguments. For example, after producing
the usual proof-peer certificate/key/public-key fixtures:

```sh
./build/ragnarok server 40000 a.cert.pem a.key.pem b.pub \
  jamnp-s/1/245becfe 10000 --chain /absolute/path/dev.json --telemetry 127.0.0.1:9000
```

Keep the existing positional mode argument, if any, before the option pairs. The retained `mesh`
command is not yet instrumented and rejects this option. No collector address or chain is
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

Incoming refusals (20), best/finalized blocks, sync, authoring,
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
Mesh remains outside this integration.

Frames use E4 little-endian payload length, then canonical JAM encoding. Strings use the existing
natural codec. Status's core array has no length prefix. Event timestamps are microseconds from
2025-01-01 12:00:00 UTC; retry/status scheduling uses the monotonic clock.

The exporter owns one non-copyable TCP descriptor and a fixed 2048-byte send buffer. Each peer
iteration performs at most one zero-timeout poll and one nonblocking send. Partial sends resume
at the exact suffix. Connect/write stalls time out after five seconds; failures retry after five
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
  connection option, message encoding, node information, timestamps and events 0/10.
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
frames, incoming/outgoing event layouts, correlation across dropped samples, and event-ID exhaustion.
The native transport suite holds 65 unfinished TLS handshakes against the 64 observation slots
on both IPv4 and IPv6, then completes one, closes it, reuses its slot, and checks tracked failures
and overflow
losses during destruction.
`make check-guards` includes a native lowering probe rejecting copies of the TCP owner.
`make check-e2e` includes a reset/reconnect collector and a real certificate-backed proof-peer
exchange with telemetry enabled, an unresponsive outgoing destination, and an attempt/outcome
spanning a collector reset. It also checks exactly one disconnect after a graceful outgoing close,
no disconnect for a failed handshake, and authenticated IPv6 peer loss despite an incomplete
application exchange. Incoming cases check success identity/address/correlation, certificate
rejection, graceful close, two distinct identities across expiry/slot reuse, and no close event
when the server shuts down with a live peer. Python is only the
independent collector/test orchestrator;
production encoding, configuration, hashing and transport stay in Nim and the maintained ABIs.
`make check-modules` and `make format-check` cover the new sources automatically.
