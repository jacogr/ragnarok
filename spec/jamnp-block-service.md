# Canonical CE128 retrieval

Scope: pinned JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE128.
`block_service.nim` implements ascending-exclusive and descending-inclusive retrieval from an
explicit host-selected complete canonical `ChainView`. Selection is structural read service;
this module neither selects forks nor certifies finality. Unknown/incompatible anchors reset.
A retained child can establish an ascending start after its parent has been evicted. Missing
later bodies/parents stop an available prefix. Header-only snapshots never fabricate blocks.

Requests require selector128, exactly one E4-framed 37-byte payload and request FIN. Replies
contain one E4-framed bare concatenation of complete blocks followed by FIN, capped at64 blocks
and8MiB including framing. Zero maxima and known canonical tips return a valid empty frame.
All size checks precede body copies. Malformed, unavailable and oversized-first-block requests
must reset only their stream. Frozen replies match all originating request facts.

The borrowed route performs bounded reads/writes and retains no canonical graph. Its parent must
provide fixed stream capacity, reject local/unidirectional streams, keep the route stable through
native close, enforce request/job deadlines, and drain `takeRequest` outside native callbacks.
Canonical work must run under a host read lease. Host failures call `reject`; successful replies
call `respond`. Native reset/close revokes pending requests. This layer supplies a working runtime
route; integration with ordinary Services and other methods remains a following feature.

Completion checks: `make unit SUITE=jamnp_block_service`, actual authenticated TLS transcripts
for both directions, u32 maximum, count truncation, zero maximum, known empty tip, evicted parent,
pruned descending prefix, unknown anchor, header-only body, invalid direction, overlong/truncated
requests and delayed request FIN. Test replies independently assemble the expected framing/order.

## Native stream reset

The QUICHE provider uses public `QuicStream::ResetWithError` with application error code zero.
It can reset a request after its FIN while preserving healthy sibling streams. Native handles
remain alive until their final close callback. No library patch is required.

The `jamnp_block_service` suite requires an actual reset after request FIN followed by a successful
second stream on the same authenticated connection, foreign-reply refusal, the 64-block cap and
oversized-response handling. The production provider and its public pins are recorded in
[`quic-proof-pins.json`](quic-proof-pins.json).
