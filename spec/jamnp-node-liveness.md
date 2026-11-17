# Explicit node connection liveness

Scope: generic QUICHE startup configuration and persistent validator connection liveness for
JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`. Node connections explicitly select a30s
idle timeout with keepalive enabled, rather than inheriting two-second crash-test settings.
This is transport configuration; full stream routing and remaining protocols are separate work.

`rq_transport_options` is a copied scalar-only startup structure. Family, multi-peer policy and
optional idle/keepalive are applied before QUICHE session construction.
The generic Nim adapter validates timing before acquiring resources. Zero idle preserves legacy
profile defaults and cannot carry a partial keepalive override; explicit idle must be1..600s.
Keepalive is enable/disable. The bridge selects a public QUICHE keepalive probe timeout at half
its configured idle timeout. Default/retired owner metric reads return zero.

The silent expiry control permits bootstrap control traffic before requiring expiry. One byte
each way confirms a full connection, then the app leaves an open stream without further writes.
Silent connections must expire; enabled IPv4/IPv6 connections must remain alive. Node actor tests
retain the same peer generations across7s without application traffic, then perform normal
role transitions. No private timing hook or upstream source patch is used.

Verification: `quic_transport`, `jamnp_node_connections`, shared ALPN, multi-peer capacity and
persistent-stream regressions, formatter/inventory and production build. No network-protocol
completion is implied by this transport fix.
