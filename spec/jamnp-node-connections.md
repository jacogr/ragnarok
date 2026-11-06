# Validator connection owner

Scope: a bounded stable Nim connection owner integrating canonical topology, validator/builder/other
admission and live native peer controls. JAMNP-S remains pinned at
`aa0e2b8498c0b1bc1725af2903704d701c6577ab`, required connectivity and preferred initiators.
The owner supplies actual authenticated connection and raw stream dispatch APIs; command/backend
and UP0 message integration remain subsequent work until explicitly verified.

Canonical roster policy is copied into identity/address facts; no full canonical graph is retained
by network callbacks or across Services worker leases. Derive local identity from the bounded public
leaf certificate, not a private-key file or caller-asserted key. All outgoing attempts pin exact
roster Ed25519 identities. Missing advertised routes do not fabricate loopback targets.

One listener and a fixed stable pool of outgoing owners share bounded dispatcher work. Per-turn
packet/timer/dial work is finite, and no connection creates a thread. Every foreign callback context
stays at its original address until explicit close. Native close observations or final engine
retirement end ownership; logical intent alone never releases a live slot.

Duplicate arbitration preserves the preferred connection. If both directions authenticate, hold at
most one pending preferred replacement per identity until the old non-preferred connection actually
closes. Suppress stream dispatch on pending peers; promote only after a real free policy slot exists.
The non-preferred side keeps the incoming preferred connection. Never close both preferred sides
merely because each side first observed an incoming connection.

Completion checks: two real TLS node owners, actual preferred/fallback dialing and identity pins,
concurrent cross-dial arbitration, close/reconnect generations, bounded raw-stream routing, epoch
reclassification, atomic setup failure and deterministic shutdown with live callbacks.

## Implemented contract

`NodeConnections.open` derives the maximum validator reservation/pool from the source core count
(three possible rosters of at most 3C each, bounded by 3069), copies fixed topology facts and derives
local identity from the configured public certificate. Explicit callback types use `nimcall` and
borrow a caller-owned stable context. Configuration/domain/source refusal starts no native work;
partial native setup uses the same complete close routine. Public method results never infer
trusted finality from a peer or from best-head advancement.

Application hooks queue stream requests or mark closure/stop intent. A turn processes up to 64
ready descriptors, a rotating slice of 64 outgoing timers, four queued stream requests, two dial attempts
and four outgoing engine retirements. Incoming peers share one bounded listener. Retry cursors
follow identity across head updates, so early route refusals cannot repeatedly starve later routes.
IPv4-mapped metadata is routed through the actual IPv4 family; unsupported explicit bind families
are refused instead of reconstructed as loopback. Pending duplicates receive no application streams;
callers handle rejected ephemeral requests as failures and cancel pending opens on Closed/Retired.
The raw stream budget is global; method-aware persistent/ephemeral fairness belongs to the following
protocol-session layer, before claiming ordinary-node UP0 service completion.

`close` runs outside callbacks, retires all engines while their enclosing addresses remain valid,
then ends still-owned logical reservations with explicit Retired events. Native stream-close routes
are cleared before user hooks. Copied NodePeer facts validate their exact native generation on
current operations; they cannot authorize a replacement or a reopened owner. Runtime listener/
dispatch failures retain typed failure status separately from a requested stop.

## Verification

`make unit SUITE=jamnp_node_connections` passes checked ARC/release tests for actual simultaneous
cross-dials in IPv4-mapped and IPv6 families, preferred replacement after actual close, opaque
byte/FIN exchanges, explicit finality/elapsed-slot role retirement, callback-requested stop and
blocked live stream retirement. A real UDP sink witnesses fair progress under repeated head updates
and two early explicit-family route refusals. Bounded malformed/oversized/chained public PEM cases
and default/failed setup are covered. One thousand mixed successful/failed constructor lifetimes
return live Nim allocation usage 47424=>47424. The actual lowering guard rejects NodeConnections
`=dup`; semantic compilation alone is not its evidence. `make format`, production ARC/LTO
`make build` and `build/ragnarok --mesh-selftest` pass. Dependency pins are unchanged.

The owner is an executable networking component, not yet the ordinary command's protocol service.
Canonical CE128/CE143 backends, trusted UP0 handshake availability and method dispatch still need
integration. Normal Services currently do not produce consensus finality; the trusted host must
supply it, and networking must not manufacture a finalized genesis or accept a peer's finality hint.
