# Telemetry

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

An optional `src/telemetry/` exporter sends JIP-3 registration, status and correlated outgoing connection
events, incoming handshake lifecycles and observed incoming/outgoing disconnections. Incoming TLS callbacks
borrow a fixed 64-slot correlation table and exporter through engine teardown; saturation only
loses observations. A separate 16-slot admitted-peer table retains copied identities until an
observed close; engine destruction does not fabricate disconnections. The exporter owns one nonblocking TCP socket
and a fixed send buffer, with no additional threads. Retained mesh role engines share one exporter
and event-ID sequence; status counts their single pinned remote peer once across duplicate connections.
An explicit JIP-4 file supplies network metadata; it does not initialize chain execution.
See [telemetry scope and limits](../../spec/telemetry.md).
