# Persistent bidirectional IPv6 peers

This bounded M3 proof retains two role engines per logical peer across sixteen reconnect rounds.
Nim uses one standard selector for both UDP sockets; Odin uses one thread-local `core:nbio` loop.
Both sockets bind to `::1`. One listens on the configured IPv6 port; the outgoing socket receives
an ephemeral port once and retains it through every reconnect. No engine, TLS context, socket or
I/O dispatcher is recreated between rounds. LSQUIC's global initialization is leased across both
engines and cleaned up only after the final engine is destroyed, on the same transport thread.

## Protocol and local policy

Source: [JAMNP-S simple.md at 439c45aad135dc654b3de6f56d7d694fd02b7aa8](https://github.com/zdave-parity/jam-np/blob/439c45aad135dc654b3de6f56d7d694fd02b7aa8/simple.md),
**Encryption and handshake**, **Required connectivity**, **Streams**, and **CE 143**.
Compiler, LSQUIC and TLS pins remain [unchanged](../spec/quic-proof-pins.json); no upstream source
patches or new dependencies are introduced. Identity, preferred-initiator selection and CE framing
remain independent native implementations. C supplies transport state and primitive observations.

Both role engines enforce the expected remote Ed25519 key, key-derived DNS SAN and exact ALPN.
The preferred initiator uses the full public-key byte strings' lexicographic ordering and the
specified XOR of their last-byte high bits. Native selftests cover both orders, all high-bit
combinations, reversed arguments and the 127/128 boundary; Python checks actual fixture decisions
independently. Equal identities are rejected before network setup.

The first round suppresses the preferred dial. The nonpreferred peer initiates after the spec's
example five-second timeout; the established fallback direction carries queries in both directions.
The remaining fifteen rounds intentionally race both dials. Once both attempts authenticate,
**local project policy** retains the preferred-initiator connection and gracefully closes the other.
The pinned specification gives a dial preference, but does not prescribe this duplicate arbitration.
Successful handshake generations remain observable after closure, so a remote duplicate close
cannot erase the evidence needed by the other peer's selection loop.

CE request direction follows the bidirectional stream's initiator, independently of the connection's
TLS client/server role. Each peer initiates four CE 143 queries on the surviving connection, and
serves the other's four. Requests remain kind 143 + E4(32) + fixture preimage hash + FIN;
responses remain E4(3) + bytes `[1, 2, 3]` + FIN. Both native implementations validate full messages
and FIN. They explicitly finish LSQUIC's application read half after validation; observing EOF alone
does not retire that owner. Buffers live until final stream close. No work is opened on the discarded
connection, and no next reconnect starts until both engines have zero live connections/stream slots.

## Reproduction and gates

```sh
python3 interoperability/test_quic_mesh.py
# Reuse freshly built peers, as Linux CI does:
python3 interoperability/test_quic_mesh.py --skip-build
```

The default runs Nim/Nim, Nim/Odin, Odin/Nim and Odin/Odin sequentially. Each pairing performs
sixteen reconnect rounds and 128 successful queries, for **512 queries on 64 surviving connections**.
It additionally retires **60 duplicate connections**. Two mixed-language runs supply a wrong
expected key and require rejection before any CE exchange. Native policy tests need no sockets.

External start/close/stop gates hold the same processes at explicit observation barriers. Every
active sample must report one OS thread and RSS below 256 MiB. After four warmup rounds, twelve
fully retired samples per peer must stay within a 16 MiB RSS range, two descriptors and 64 KiB of
live application allocation variation. Accepted/closed counts must agree before the next dial.
Odin's final cleanup checks zero tracked application bytes and zero pending I/O operations; Nim
checks a bounded post-cleanup ARC baseline. These are finite resource gates, not a leak-freedom claim.

Diagnostic logs, resource samples and summary JSON live under `build/quic/mesh`; CI uploads only
those paths and the CI step log. Certificates/private keys stay in ignored fixture storage.

## Scope remaining

This is a **two-peer loopback proof**, alongside the earlier sixteen-slot inbound service proof.
It does not establish a general multi-target outgoing engine, arbitrary IPv6 routing, metadata
endpoint decoding, previous/current/next validator-set management, durable UP streams, replacement
of a live fallback by a later preferred connection, or independent JAM-stack interoperability.
The fixed peer expectation avoids introducing a general per-connection TLS identity dispatcher
in this increment. Disruption/overload testing, bounded Bandersnatch offload and deeper C/TLS
allocation instrumentation remain separate rounds. No language decision or production networking
claim follows from this test.

The subsequent [resilience round](quic-resilience.md) addresses controlled peer death/restart and
authenticated admission saturation. The broader networking and crypto-offload limits above remain
open; the earlier mesh workload and profile settings remain unchanged.
