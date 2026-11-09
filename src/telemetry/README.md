# Telemetry delivery

[Source guide](../README.md)

This folder implements the optional bounded JIP-3 telemetry subset and its adapter from actual
peer observations.

| Module | Contents |
| --- | --- |
| [`chain.nim`](chain.nim) | Bounded JIP-4 metadata extraction for telemetry network identity |
| [`wire.nim`](wire.nim) | Owned JIP-3 registration and event encodings |
| [`client.nim`](client.nim) | Nonblocking TCP delivery, bounded queues and reconnect lifecycle |
| [`observer.nim`](observer.nim) | Translation of transport/peer events into copied telemetry observations |

## Run

Append `--with-telemetry --telemetry-endpoint HOST:PORT` to a `server`, `client` or `mesh`
invocation. Collector endpoints accept numeric IPv4, `localhost` (IPv4 loopback), and bracketed
IPv6 literals such as
`--telemetry-endpoint '[::1]:9000'`. Ports must be decimal 1–65535. DNS names, IPv6 scope IDs and
unbracketed IPv6 endpoints remain unsupported. The advertised QUIC address can be IPv4-mapped IPv6 or IPv6 loopback,
matching the existing peer mode and actual bound UDP port.

Pass `--chain PATH` with an explicit JIP-4 JSON chain file. Both options are required together
and may appear in either order among the command flags. For example, after producing
the usual proof-peer certificate/key/public-key fixtures:

```sh
./build/ragnarok server --net-port 40000 \
  --net-cert a.cert.pem --net-key a.key.pem --net-peer-key b.pub \
  --net-alpn jamnp-s/1/245becfe --net-timeout-ms 10000 \
  --chain /absolute/path/dev.json --with-telemetry --telemetry-endpoint 127.0.0.1:9000
```

Keep the existing positional mode argument, if any, before the trailing switches and option pairs.
Endpoint configuration alone does not enable telemetry. The retained `mesh`
command accepts the same trailing option pairs after its positional gate directory. No collector address or chain is
assumed when telemetry is absent. An invalid explicit endpoint, certificate or chain file fails
startup with a diagnostic. An unavailable collector never fails an otherwise valid peer session.

The chain file selects telemetry's network identity only: it does not initialize a state store,
connect bootnodes, implement block execution, or automatically replace the existing ALPN argument.
Select the matching ALPN explicitly. The proof peer remains a bounded test application.

See the [telemetry record](../../spec/telemetry.md) for pinned protocol references, fixture
provenance, and native and collector interoperability checks.
