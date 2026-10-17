# Initial JIP-3 telemetry

Ragnarök's bounded proof peer can register with a JAM Tart collector and report its current
authenticated peer count approximately every two seconds. Telemetry is disabled by default.
This is a JIP-3 version-1 subset, not a claim of full telemetry or validator functionality.

## Run

Append `--telemetry HOST:PORT` to an existing `server` or `client` invocation. This increment
accepts numeric IPv4 collector addresses and `localhost`; DNS names and IPv6 collector addresses
remain unsupported. The advertised QUIC address can be IPv4-mapped IPv6 or IPv6 loopback,
matching the existing peer mode and actual bound UDP port.

Set `RAGNAROK_TELEMETRY_CHAIN` to an explicit JIP-4 JSON chain file. For example, after producing
the usual proof-peer certificate/key/public-key fixtures:

```sh
RAGNAROK_TELEMETRY_CHAIN=/absolute/path/dev.json \
  ./build/ragnarok server 40000 a.cert.pem a.key.pem b.pub \
  jamnp-s/1/245becfe 10000 --telemetry 127.0.0.1:9000
```

Keep the existing positional mode argument, if any, before `--telemetry`. The retained `mesh`
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
- Event 0: dropped observations, with first/last timestamps and the exact number of omitted
  status observations when the pending send buffer prevents enqueueing another status.

No best/finalized block, sync, connection-correlation, authoring, execution, service, ticket or
work-package events are fabricated. The next useful increment is connection lifecycle events
once the native callback surface exposes the required peer addresses and correlated attempts.

Frames use E4 little-endian payload length, then canonical JAM encoding. Strings use the existing
natural codec. Status's core array has no length prefix. Event timestamps are microseconds from
2025-01-01 12:00:00 UTC; retry/status scheduling uses the monotonic clock.

The exporter owns one non-copyable TCP descriptor and a fixed 2048-byte send buffer. Each peer
iteration performs at most one zero-timeout poll and one nonblocking send. Partial sends resume
at the exact suffix. Connect/write stalls time out after five seconds; failures retry after five
seconds and resend registration with a fresh event-ID namespace. Pending data is discarded on
disconnect or shutdown. There are no background threads, persistent queues or blocking shutdown
flushes. SIGPIPE is suppressed per socket/send. The existing dispatcher bounds its waits to 10 ms.

Chain input is capped at 8 MiB, nesting at 32 levels, serialized header at 64 KiB, certificate PEM
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

Compatibility reference: jamtart `76debc1b1b90889749d0129ca18ffdb5d96d17a4`, `src/decoder.rs`,
`src/events.rs` and `src/types.rs`. It is a cross-check, not a replacement for JIP-3 or the GP.

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
frames. `make check-guards` includes a native lowering probe rejecting copies of the TCP owner.
`make check-e2e` includes a reset/reconnect collector and a real certificate-backed proof-peer
exchange with telemetry enabled. Python is only the independent collector/test orchestrator;
production encoding, configuration, hashing and transport stay in Nim and the maintained ABIs.
`make check-modules` and `make format-check` cover the new sources automatically.
