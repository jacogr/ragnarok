# Persistent multi-peer QUIC service

This round keeps one listener engine, TLS context, UDP socket and native event loop alive across
multiple simultaneous peers and reconnect waves. It supplements the earlier lifecycle soak, which
recreated the engine for each session. Both listeners accept independent Nim and Odin clients.

The protocol remains JAMNP-S version 1 at commit
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`, specifically **Encryption and handshake**, **Protocols
and streams / Messages**, and **CE 143: Preimage request** in `vendor/jam-np/simple.md`. Certificate
identity, key pinning, ALPN, E4 framing and exact fixture validation remain native to each language.
CE initiator cancellation and acceptor rejection follow the pinned stream conventions. The native
source, compiler and dependency revisions in `spec/quic-proof-pins.json` are unchanged.

## Workload and observations

Run from the repository with the pinned toolchains:

```sh
python3 interoperability/test_quic_service.py --fetch
# After a successful build of the current sources:
python3 interoperability/test_quic_service.py --skip-build
```

The default workload runs sixteen waves per listener, retaining the listener's PID and engine:

- One Nim and one Odin client, with different public identities, each opens eight CE streams:
  five healthy requests, one cancellation, one invalid kind and one missing request FIN.
- Two additional healthy clients request eight tiny preimages each. The native listener must record
  healthy progress while a stream on a **different connection** has a genuinely blocked large write.
- Another client supplies an invalid SAN or incompatible ALPN. Its attempted exchange must fail
  while the listener and authenticated peers continue.
- The first and final waves kill an authenticated client without sending a QUIC close. Transport
  idle expiry must retire its connection and stream buffers.
- The harness waits for zero retained authenticated connections and zero live application stream
  slots, samples resources, then reconnects the same identities in the next wave.
- After the last idle barrier, normal shutdown drains native and I/O callbacks before owner release.

Every completed client must validate exact response bytes and FIN, including the one-MiB fixture.
The mixed-client timings are deliberately longer than the original soak to leave a useful observation
window. A two-second transport idle timeout is an experiment setting for crashed-client retirement,
not a claimed JAM deadline. The existing 500 ms incomplete-request deadline remains stream-local.

The bridge retains at most sixteen promoted connection handles; the native applications retain
at most sixty-four stream slots. Service transport credit starts at eight bidirectional streams per
connection and 64 KiB per stream. These are finite proof bounds, not production admission policy
or coverage of hostile unauthenticated handshake floods. Excess application streams are rejected
without marking the whole service failed. This workload does not exhaust either admission ceiling.

## Ownership and resource checks

C retains only transport handles, counters and TLS state. The bridge exposes copied lifecycle
metrics and synchronous live-stream owner comparison; it exposes no connection pointer to the
languages. Each connection releases its slot at native close. A failed connection cannot change
listener-wide authentication status or retire another peer's handle.

Both languages release stream buffers only at final native close. Nim's selector/ARC owner and
Odin's dispatcher/allocator owner remain stable throughout the service. Graceful clients queue
connection close **before** stopping UDP, then drain transport packets. A killed client exercises the
separate timeout path. Shutdown retains native callback owners until engine destruction finishes;
Odin additionally removes its receive and drains kernel cancellation and standalone timers.

The harness checks one OS thread and less than 256 MiB RSS per listener. After four warmup waves,
it permits at most 16 MiB idle RSS range, two descriptors of variation and 64 KiB of language
allocation variation. Odin must retain exactly one receive and one timer while idle, and zero
application allocations and operations after service teardown. Nim checks its post-teardown
occupied-memory count against the pre-service baseline with a 64 KiB bookkeeping allowance.

The language allocation totals are **not directly comparable**: Nim's occupied-memory observation
includes its live standard selector; Odin's application tracker is installed after dispatcher
acquisition and excludes process-lived dispatcher storage. Neither counter sees LSQUIC/TLS C
allocations. RSS provides aggregate finite-run evidence, not native allocation attribution or proof
of leak freedom. The macOS kqueue selector preallocates a descriptor table based on the OS descriptor
limit; the Linux epoll baseline can differ.

Logs and machine-readable results live under `build/quic/service`. Linux CI runs the test after the
existing lifecycle soak and uploads only diagnostic JSON/log files, excluding TLS private keys.

## What this establishes and what remains

This demonstrates a persistent **inbound** multi-peer service in each language, healthy progress
across connections, repeated reconnects, failed-peer isolation and bounded observed resource use.
Clients deliberately create fresh processes and engines for each connection; this round does not
prove persistent outgoing-engine reconnect or a bidirectional validator mesh. It remains an IPv4
loopback experiment, with independent identities but no independent JAM implementation.

IPv6, loss/reordering/network-path tests, independent-peer interoperability, full admission/fairness
policy and deeper C/TLS allocation instrumentation remain open. Odin's Linux backend still requires
io_uring support and suitable kernel policy; CI preserves those setup checks. The new Linux test
must pass on a pushed run before claiming Linux verification for this increment.

The next proposed round is a codec/crypto/network integration slice. A subsequent measured
comparison will include optimized M1 encode/decode speed, borrowed versus owned decoding,
allocations and latency on identical Linux hardware and input corpora. This service regression is
correctness/resource evidence and produces no speed ranking.
