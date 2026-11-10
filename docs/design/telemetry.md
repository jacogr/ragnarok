# Telemetry

[Design overview](../design.md) · [Telemetry source guide](../../src/telemetry/README.md)

Application options and certificate/chain setup live under `src/app/`, shared with RPC and UI.
The peer dispatcher drives the exporter and keeps it alive through native transport teardown.
Transport callbacks lend addresses and certificate data to the observer. The observer turns
those borrows into owned observations before returning.

Retained mesh role engines share one exporter and event-ID sequence and advertise the IPv6
listener address. Each actual dial takes a fresh native authentication and close baseline so
reconnects cannot inherit an earlier outcome. A suppressed fallback direction emits no attempt.
Duplicate arbitration reports each observed connection retirement while status counts the
single pinned remote peer once across both engines.

See the [telemetry record](../../spec/telemetry.md) for protocol references and verification.
