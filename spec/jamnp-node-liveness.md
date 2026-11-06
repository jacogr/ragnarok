# Explicit node connection liveness

Scope: generic LSQUIC startup configuration and persistent validator connection liveness for
JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`. Node connections explicitly select a30s
idle timeout with keepalive enabled, rather than inheriting two-second crash-test settings.
This is transport configuration; full stream routing and remaining protocols are separate work.

`rq_transport_options` is a copied scalar-only startup structure. Family, multi-peer policy and
optional idle/keepalive are applied before LSQUIC copies settings during engine construction.
The generic Nim adapter validates timing before acquiring resources. Zero idle preserves legacy
profile defaults and cannot carry a partial keepalive override; explicit idle must be1..600s.
Keepalive is enable/disable: the pinned IETF engine schedules enabled probes at half the negotiated
idle timeout rather than using the numeric `es_ping_period` as a caller-chosen interval.
Existing native factory ABIs remain available. Default/retired owner metric reads return zero.

The silent expiry control must observe beyond real transport bootstrap. Pinned LSQUIC can issue
eight source connection IDs at60/minute; NEW_CONNECTION_ID/ACK traffic correctly refreshes idle.
An initial6s observation was therefore not actually idle, despite negotiated3s and zero PING
period. Public diagnostics confirmed CID_THROT traffic; no private timing hook or source patch
was needed. Temporary tracing was removed. The final14s observation exceeds8s bootstrap plus3s
idle and margin. One byte each way confirms a full connection, then the app leaves an open
stream without further writes. Silent connections actually expire; enabled IPv4/IPv6 connections
remain alive. Node actor tests retain the same peer generations across7s without application
traffic, then perform normal epoch/role transitions. This also verifies startup/retirement and
1000-cycle ARC stability under the explicit node policy.

Verification: `quic_transport`, `jamnp_node_connections`, shared ALPN, multi-peer capacity and
persistent-stream regressions, formatter/inventory and production build. No network-protocol
completion is implied by this transport fix.
