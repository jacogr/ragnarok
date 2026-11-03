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

## Approved native reset API build patch

On 2026-11-03 the maintainer authorized a public reset API build patch, preferring a pin upgrade
if an equivalent upstream API already existed. Fresh GitHub source checks found no public
stream-reset operation in either `iftech/lsquic` master
[`0c9c6690`](https://github.com/iftech/lsquic/blob/0c9c66903b70ac25852d70d54672005aafb1a446/include/lsquic.h) or `litespeedtech/lsquic` master
[`cd23e526`](https://github.com/litespeedtech/lsquic/blob/cd23e526e53387ad7a2fada9a4479d2353ee2b42/include/lsquic.h). Both retain only an internal reset helper.
The LSQUIC pin therefore remains `fd0d75c6584eb4c20dfa8b4b865bfe3daf5a2e52`.

The approved patch adds `lsquic_stream_reset` to the public header and library implementation.
It delegates to LSQUIC's existing reset machinery inside the library; the bridge uses only the
public header/API. Reset before write shutdown reports success, while closed/write-finished
streams report EBADF/EPIPE. `streamAbort` uses reset and falls back to ordinary close only when
reset can no longer be sent. Existing native close callbacks retain lifetime responsibility.

`spec/quic-proof-pins.json` binds the patch SHA-256 and both input/output file SHA-256 digests.
`build_quic.py` first validates all pristine pinned vendor inputs, then creates a temporary
build-directory copy including pinned nested submodules. Patch/input/output drift aborts before
publishing that copy. Every preparation recreates the copy, discarding stale generated edits.
The vendor checkout and gitlinks stay untouched; no private API is imported by the bridge.
Verification provenance includes the same recorded patch as the production build.

Observed local checks: formatter and `make unit SUITE=jamnp_block_service` pass, including
an actual reset after request FIN followed by a successful second stream on the same TLS
connection, foreign-reply refusal, 64-block cap, oversized-first refusal and oversized-later prefix.
The earlier strict rejection regression observed EOF with zero bytes instead of reset; the test
was retained unchanged in its rejection requirement. Shared transport/build verification is
recorded with the PR. This does not complete ordinary Services integration or other CE methods.
