# IPv6 disruption and overload proof

This bounded M3 round uses the same pinned LSQUIC/BoringSSL sources and native Nim/Odin adapters.
It measures recovery and admission behavior, with no speed thresholds or production resilience
claim. The protocol reference remains [JAMNP-S simple.md at
439c45aad135dc654b3de6f56d7d694fd02b7aa8](https://github.com/zdave-parity/jam-np/blob/439c45aad135dc654b3de6f56d7d694fd02b7aa8/simple.md),
**Encryption and handshake**, **Required connectivity**, **Streams**, and **CE 143**. Exact peer
pins, certificate/SAN checks, ALPN, preferred direction and CE framing remain native policies.

## Explicit experiment profiles

The retained-pair profile from [the preceding round](quic-mesh.md) keeps its settings. Two named
profiles are added for these experiments: crash recovery and saturated service. They negotiate a
two-second QUIC idle timeout and one-second liveness probes. These short settings bound deliberate
peer-loss tests; they are not JAMNP-S timeout requirements. Native UDP and QUIC timers still run
on one selector/nbio dispatcher per process, with no worker or per-connection thread.

The saturated service retains the existing ceiling of sixteen promoted connections, eight remotely
initiated bidirectional streams per connection, and sixty-four native application stream owners
across the listener. It retains complete CE query prefixes without FIN for at most thirty seconds
in this test profile. Ordinary service keeps its existing 500 ms incomplete-request deadline.
The larger hold window makes admission saturation observable; receive allocations remain fixed
and bounded rather than following an untrusted length.

## Peer-loss recovery

Each of Nim/Nim, Nim/Odin, Odin/Nim and Odin/Odin runs twelve cycles. The keeper retains its two
role engines, TLS contexts, IPv6 sockets and one dispatcher for the entire experiment. Its partner
is killed and restarted with the same certificate, public identity and listener port every cycle.

Both peers first complete four queries initiated in each direction. An external barrier requires
healthy stream owners to retire on both sides before incomplete requests are introduced. Each
then opens four valid CE query prefixes while withholding FIN and receives the other's four.
The pending marker requires four fully sent requests and four fully received query prefixes,
with no completed/read-FIN owner standing in for pending work. The harness kills the partner only
after both sides prove eight pending owners.

The keeper waits for negotiated transport expiry, without queuing graceful connection close.
Its known peer-loss phase settles each of the eight operations exactly once; final native stream
close remains the sole release point for receive/write buffers. Both connection counters and all
stream slots must retire before the next restart/dial is released. Malformed work in the subsequent
healthy phase remains a failure. Retry timing and process restart are driven by test gates; this is
not a production automatic reconnect scheduler.
A final healthy generation follows the twelfth loss in each pairing and closes gracefully, so
reconnect/work is verified after every forced death, including the last one.

## Admission saturation and healthy recovery

One listener per language stays alive across twelve waves. Load sources alternate Nim and Odin;
all use valid pinned TLS identities. Each wave performs:

1. Fill all sixteen connection slots with authenticated idle peers. A seventeenth attempt must be
   refused without displacing the sixteen existing connections. Kill the accepted sources and
   require all connection owners to expire and retire.
2. Open eight holder connections, each sending eight correct query prefixes without FIN. The
   service must report exactly sixty-four retained native stream owners. A new single-query probe
   must be rejected at the stream budget.
3. Kill one holder and wait for its eight stream owners to retire. A new healthy CE probe must
   complete while the other seven loaded connections remain alive.
4. Kill the remaining holders, wait for exact accepted/closed counter equality and zero live
   stream owners, then observe idle resources before releasing the next wave.

The C bridge observes connection-capacity rejection only; the sixty-four-slot admission rule,
stream buffers, CE validation and load diagnostics stay independently implemented in Nim/Odin.
Successful probing validates the exact fixture response and FIN, rather than treating TLS
success as application progress. The holder identity is intentionally shared across connections;
this tests resource admission, not per-validator identity quotas.

## Reproduction and resource gates

```sh
python3 interoperability/test_quic_resilience.py
# Linux CI reuses freshly built native peers:
python3 interoperability/test_quic_resilience.py --skip-build
```

The default requires twelve cycles/waves and four warmup samples, leaving eight fully retired
samples for each retained process. Limits match the preceding proofs: one OS thread, active RSS
below 256 MiB, idle RSS range at most 16 MiB, descriptor range at most two and live application
allocation range at most 64 KiB. Observed peer-loss retirement must finish within ten seconds.
Final keeper/listener shutdown must pass ARC/tracking cleanup checks; deliberately killed load
sources are reaped by the harness and are not represented as graceful language-level cleanup.

Diagnostics and incomplete/complete summaries live under `build/quic/resilience`. CI uploads only
explicit logs, result JSON and resource samples; certificate/private-key fixtures are excluded.
There are no new dependencies, upstream patches, pin advances or source optimizations.

## Connection retirement before the first request

The reusable IPv6 engine returns to idle after a connection closes. The single-attempt dialer CLI must
check active/closed counters as well as transport status: after a retained connection retires,
there is no peer on which its unfinished exchange can complete. In particular, admission can
close after authentication but before a stream exists, leaving no stream callback to report the
failure. Both native CLI loops now terminate that attempt promptly.

Successful handshake history remains in metric 4, separately from live connection state and
application success. The final native-loop observation uses that history if a receive cycle also
closes the connection; an exchange still requires all exact responses and FINs to be validated.
Reusable mesh engines retain their existing idle/reconnect semantics and the C ABI is unchanged.

The resilience runner first checks all four language pairings: authenticate a client in the
existing no-stream `idle` mode, kill its listener, and require failure within five seconds rather
than the CLI's sixty-second overall timeout. The existing connection/stream admission probes keep
the same five-second gate; missed retirement now includes the native client log in the failure.
Fixtures are isolated under `build/quic/resilience/fixtures` so other runners cannot replace pins.

## Limits

This proves finite, controlled process loss and authenticated admission saturation on IPv6
loopback. It does not test arbitrary packet loss/reordering, network-interface changes, untrusted
handshake floods, connection migration, a general multi-target dialer, validator sets, independent
JAM stacks or long-running production DoS resistance. C/TLS allocation instrumentation and
bounded Bandersnatch offload remain separate gates. See [observed results](../results/quic-resilience.md).
