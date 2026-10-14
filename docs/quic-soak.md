# Bounded QUIC lifecycle soak

Run the sustained-operation correctness test with the existing pinned tools:

```sh
python3 interoperability/test_quic_soak.py --fetch
```

After a successful build of the current native sources, reuse its binaries:

```sh
python3 interoperability/test_quic_soak.py --skip-build
```

The Linux CI workflow runs this command after the original QUIC rejection suite
and the harness regression checks:

```sh
python3 interoperability/test_quic_soak_harness.py
```
The default is 40 sessions per language pairing, with eight warmup sessions.
The server/client combinations Nim/Nim, Odin/Odin, Nim/Odin and Odin/Nim each
keep the same two native processes alive across all rounds. Engines, listeners,
sockets and connections
are recreated and retired within those processes. Odin holds one dispatcher
per process; session-level acquisitions borrow that dispatcher and release their
reference after draining operations. This measures retained
resources across lifecycle churn; it does not establish multi-connection service
within a persistent engine.

Each session opens eight CE 143 streams: five healthy requests, one client
cancellation during a large reply, one malformed stream kind, and one request
that withholds FIN. The server bounds missing FIN to 500 ms without closing the
connection. Three healthy requests start at 650 ms, after that timeout, to prove
continued service. The large fixture is exactly 1 MiB of `i mod 251`, named by
its independently checked Blake2b-256 digest. Every response byte is validated.

Both transports cap stream credit at 64 KiB in soak mode. The slow reader waits
350 ms before consuming the large response; the cancelled reader aborts at
150 ms. The server must observe a large write still pending at 100 ms in every
session. This exercises real transport flow control rather than a simulated
write failure. Pending native buffers outlive their write/reset callbacks.

## Failure criteria

Every session has a five-second native deadline and an eight-second harness
progress deadline. The harness requires exact healthy/cancellation/rejection
counts, one missing-FIN timeout, and evidence of backpressure per session.
After all sessions, both peers must exit normally after cleanup.

Live observations require one OS thread and resident memory below 256 MiB.
After warmup, idle RSS must stay within a 16 MiB range, live language allocations
within 64 KiB, and descriptor counts within a range of two. Nim reports its ARC
allocator occupancy and reserve; Odin uses its tracking allocator and requires
application ownership to return to the exact pre-session baseline each round.
These counters exclude C/TLS allocation internals, which remain covered by the
aggregate RSS budget. Sampling happens after each engine/socket teardown,
while both processes wait for an external gate. Linux uses `/proc`; macOS uses
`ps` and `lsof`. Gate waits also have a 15-second native deadline so an abandoned
harness cannot retain a peer forever. Odin's UDP receive has no linked timeout:
its standalone QUIC timer wakes deadline checks, and shutdown explicitly
removes the pending receive and drains cancellation before releasing its buffer.
Odin's native `--io-selftest` covers 256 idle/ready receive cancellations;
Nim's covers 256 idle/ready selector registration retirements before the peer
matrix runs. Nim has no queued asynchronous receive operations: its
[explicit adapter](quic-adapters.md) owns readiness and synchronous nonblocking
syscalls. Readiness and completion use exact
marker lines; interleaved transport diagnostics cannot hide readiness or reuse
a previous round's readiness.

These are finite regression budgets, not a proof of leak freedom or a performance
benchmark. Results retain every idle observation and active resource peaks.
Longer local runs can use `--rounds 200 --warmup 20`; rounds are bounded to
16..1000, with at least eight samples after warmup.

Logs and results live in ignored `build/quic/soak/`. CI uploads only logs and
JSON diagnostics, excluding generated TLS private keys and gate files.
[The current adapter report](../results/quic-adapters.md) records executed
results and remaining M3 work; [the earlier report](../results/quic-soak.md)
preserves the historical patched-wrapper results.

The protocol baseline stays at JAMNP-S commit
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`, sections **Protocols and streams**,
**Messages**, **Notation**, and **CE 143: Preimage request**. The workload sizes,
timeouts, flow-control settings and resource budgets are local test policy,
not additional JAMNP-S requirements. No compiler or dependency revision changes.
