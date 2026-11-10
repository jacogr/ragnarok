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

Telemetry reads the JIP-4 JSON chain file from `--chain PATH` or defaults to `./chain.json`.
The node derives the network ALPN from the genesis header hash. An explicit `--net-alpn`
must match that network. For example, after producing the usual proof-peer certificate
and key fixtures:

```sh
./build/ragnarok server --net-port 40000 \
  --net-cert a.cert.pem --net-key a.key.pem --net-peer-key b.pub \
  --net-timeout-ms 10000 \
  --chain /absolute/path/dev.json --with-telemetry --telemetry-endpoint 127.0.0.1:9000
```

For `mesh`, supply the gate with `--net-gate PATH`. Telemetry activates only with
`--with-telemetry`. Invalid explicit endpoint, certificate, or chain inputs fail startup.
Collector unavailability leaves peer work running. State initialization and bootnode
connections are controlled by the application mode and its options.

See the [telemetry record](../../spec/telemetry.md) for pinned protocol references, fixture
provenance, and native and collector interoperability checks.
