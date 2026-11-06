# JAMNP-S ALPN acceptance

Scope: JAMNP-S `simple.md` at `aa0e2b8498c0b1bc1725af2903704d701c6577ab`,
“ALPN”. Version1 identifiers contain exactly eight lower-case genesis-header hash nibbles,
with the sole optional `/builder` suffix. An acceptor permits both forms for its configured
chain. A suffix selects transport admission intent only; it grants no validator membership,
work-package authorization or authority to change state.

`jamnp-s/alpn.nim` owns spelling and the two acceptor names. The ordinary peer, mesh listener
and development responder supply those names explicitly. The transport remains generic:
its optional accepted protocol list becomes a copied bounded TLS ALPN wire vector. The C
bridge validates vector framing only, copies it before network processing and never interprets
JAM names. It rejects client-side configuration, empty/oversized/truncated entries and vectors
larger than512 bytes or8 entries. Invalid configuration leaves no partially configured live
endpoint. Existing direct generic transport users retain single-protocol behavior by default.

`make unit SUITE=jamnp_alpn` tests exact accepted/malformed spellings and real production
acceptor TLS handshakes for base/base, base/builder, builder/base, wrong-chain builder and
wrong-version offers using the same independent certificate fixtures. Existing persistent-stream
and protocol checks retain identity/framing/lifecycle coverage. Test-only fixtures create no
application stream or work-package credentials.

This layer fixes base/builder negotiation. Genesis selection, builder-specific capacity and
CE133 state-backed admission remain separate compliance requirements; neither successful
negotiation nor selector decoding establishes those properties.
