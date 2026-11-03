# Live peer control

Scope: generic owner/generation-bound peer references for selecting a live multi-peer connection,
associating streams with that connection, opening streams and requesting closure. JAMNP-S policy
remains in Nim, pinned at `aa0e2b8498c0b1bc1725af2903704d701c6577ab`.

A native slot alone is a reusable coordinate. References also carry a process-unique transport
identity and monotonically increasing admission generation. Both counters refuse exhaustion before
wrapping. Every operation validates the live owner, slot and generation; defaults, foreign owners,
closed/replaced peers and reopened owners fail without affecting another connection. References
own no foreign pointer and extend no lifetime. Stream extraction binds to the queried transport.

Peer closure requests do not release application ownership; actual native close observations do.
Stream opening reports an accepted request, not protocol completion. Callers keep pending stream
work bounded and do not recursively poll/retire the transport from callbacks.

Completion checks: actual multi-peer TLS stream routing and targeted replies, one-peer closure,
surviving peer activity, slot replacement, foreign/default/stale references and owner reopening;
existing default ALPN/capacity/persistent regressions and production build as affected.

Local checked ARC/release `quic_peer_control` passes real two-peer TLS targeted stream/FIN
round trips, targeted closure and surviving-peer activity, same-slot generation replacement,
foreign/default/closed-owner refusal and owner reopening at slot0 generation1. `quic_admission`,
`quic_capacity` (20 live TLS peers in both families), `jamnp_persistent`, `jamnp_alpn`,
`make format` and the production ARC/LTO `make build` pass. No dependency changes.
