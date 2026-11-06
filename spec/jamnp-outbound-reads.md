# Bounded outbound canonical reads

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE128/129/143 requests
on an already authenticated node connection. No dependency source or pin changes. This layer
supplies complete transport framing, not semantic/cryptographic response validation, canonical
adoption, ordinary executable activation or the remaining protocol families.

`NodeService.request` reserves a fixed client frame and returns an opaque peer-generation,
nonwrapping-serial ticket before requesting any native open. Client and responder reads share the
global limit of64 and per-peer limit of2; selectors and UP0 retain their independent reservations. Each peer
serializes its one outstanding local open intent (UP0 or read). Required UP0 handshakes must be
usable before a local read starts; validator peers that require no UP0 can still exchange reads.
Both connection directions may initiate CE streams, independently of UP0's initiator-only rule.

The pinned public `lsquic_conn_n_pending_streams` and `lsquic_conn_cancel_pending_streams` APIs
cancel delayed native opens without closing existing streams. Generation-checked bridge control
never falls back to a sole/global connection. `NodeConnections.cancelStreamOpens` tombstones its
queued peer intents and cancels native-delayed opens. Its caller owns all that peer's pending
opens; `NodeService`'s serialization makes this one exact outbound intent. If native mapping fails,
the logical peer becomes closing before its application slot can be reused. No stream handle is
invented for a cancelled intent. Tombstones drain under the existing four-open poll budget.

`read_client.nim` encodes one exact fixed selector/E4/request and sends FIN. Response parsing
requires exactly one E4 message for CE128/143 or two for CE129, then native FIN. Every truncated
prefix/body, extra message/suffix and excessive declared extent fails without exposing a prefix.
Input is incrementally appended in at most4096-byte chunks, with an8MiB aggregate wire ceiling
(including prefixes) and32MiB shared client-input credit. Lengths are checked by subtraction before
body growth/narrowing. Exact-budget responses can still read their final EOF with zero unused
body credit. Sequence capacity can exceed logical length by allocator growth; caller-owned copies
and native-library buffers are outside this actor's logical byte accounting.

Completed response bytes survive actual native stream retirement until host collection,
cancellation or deadline. Taking bytes before retirement refunds input credit but retains the
physical frame reservation until native close. Queued cancellation removes both host/native
pending opens before releasing its slot. Peer retirement and explicit shutdown also release
never-opened and complete-but-uncollected frames. Stale/default tickets cannot collect a reused
slot. Queued opens have5s; active/uncollected client reads share30s inactivity/120s absolute
bounds with responder reads.

`UntrustedReadReply` has private immutable complete bytes and exact request facts. TLS identity
and framing do not verify block counts/hashes/execution, state proof authentication or preimage
hashes. Hosts must validate those before use; no response selects canonical state or finality.
`ApplicationNode` forwards these network-only operations even while an unrelated Services worker
owns the canonical graph. Taking/cancelling an outbound reply never releases that worker lease.

Verification:

- `jamnp_node_service`: real paired owners on IPv4/IPv6, both initiating directions, literal empty
  block replies, canonical two-message state transfer, missing-preimage reset and healthy retry,
  one remote request per intent, queued/active/sibling cancellation, per-peer quota, unchanged
  authenticated peer generations, delayed host collection and queued/uncollected shutdown.
  Existing inbound, UP0, fairness and1000-cycle ARC checks remain.
- `jamnp_read_client`: independent raw TLS request/response literals, every incomplete prefix of
  a two-message reply, extra messages/suffixes, oversized declarations, exact/exhausted credit,
  withheld FIN and successful extraction only after actual native close. First failure reasons
  survive that close. Raw payloads intentionally establish framing only.
- `quic_pending_opens`: hold all eight pinned multi-peer stream credits, create four delayed
  opens, cancel them, preserve the eight existing streams, return credit without phantom opens,
  and open a fresh ninth stream on the same authenticated connection.
- `quic_peer_control`: default/foreign/stale/replaced/closed generation cancellation refusal.
- `jamnp_application_node`: outbound replies and queued cancellation while an unrelated real
  Services read is Done but still owns its canonical/RPC lease; only its exact collection resumes
  the graph. Existing managed inbound, finality, close/restart and clock checks remain.
