# Live peer control

Scope: generic owner/generation-bound peer references for selecting a live multi-peer connection,
associating streams with that connection, opening streams and requesting closure. JAMNP-S policy
remains in Nim, pinned at `aa0e2b8498c0b1bc1725af2903704d701c6577ab`.

The [transport adapter](../src/quic/transport.nim) owns peer reference validation and
the distinction between an accepted operation request and native completion.

Completion checks: actual multi-peer TLS stream routing and targeted replies, one-peer closure,
surviving peer activity, slot replacement, foreign/default/stale references and owner reopening;
existing default ALPN/capacity/persistent regressions and production build as affected.

Local checked ARC/release `quic_peer_control` passes real two-peer TLS targeted stream/FIN
round trips, targeted closure and surviving-peer activity, same-slot generation replacement,
foreign/default/closed-owner refusal and owner reopening at slot0 generation1. `quic_admission`,
`quic_capacity` (20 live TLS peers in both families), `jamnp_persistent`, `jamnp_alpn`,
`make format` and the production ARC/LTO `make build` pass. No dependency changes.
