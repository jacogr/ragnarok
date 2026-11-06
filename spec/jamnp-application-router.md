# Managed application node routing

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, application lifecycle for
UP0 and canonical CE128/129/143. This component integrates real Services ownership; ordinary
executable configuration, outbound synchronization and remaining protocol families are separate
incomplete work. No dependency pin changes or compatibility-completion claim.

`app/node.nim` owns one stable `ApplicationNode`, borrowing a stable Services address through
explicit close. It installs the node stream actor only for an initialized full-state owner under
the graph gate. The protocol must match the detached original configured-genesis identity;
a restored/current best head never redefines ALPN. Startup requires explicitly selected finality.

At most one exact Services worker ticket and node read ticket are retained. Native polling uses
detached bytes only. Source refresh occurs only under the canonical gate, in a staging activation
that retires every temporary graph alias before a managed read starts. Fixed source hashes and
local JAM time detect changes without caching canonical maps/headers. Clock ticks alone do not
broadcast an unchanged header; a held epoch transition is retried as local JAM time advances.
Peer claims never select a trusted head, finality or clock.

The shared worker is admitted only when Services grants its exclusive graph/RPC lease. Busy
foreign proof/preparation/publication work remains untouched while native streams continue.
Cancellation retains the lease until matching Done collection or joined shutdown. The host closes
its own exact read by cancellation and joined stop; closing an idle/stale host cannot join or
release an unrelated worker ticket. Services storage must outlive the borrowing host. A worker
failure, cancelled task or unavailable reply resets the request without an empty success prefix.

Worker admission rotates across physical read slots. A client recycling a low slot therefore
cannot repeatedly overtake an existing higher-slot request. A literal real-TLS witness failed
with the original ascending slot scan, then passed with the rotating cursor. This is bounded
admission fairness, not a promise to finish every request before its deadline.

Trusted local `Services.publishFinalized` updates canonical and optional RPC views together,
rejecting busy graphs, stale histories, unknown selections and regressions before mutation or
notifications. The RPC overload installs both selected views before subscriber queue work;
repeated selection is silent. It verifies no consensus proof and is not exposed as a peer/WS
method. Missing finality still refuses node startup: a best head, restored checkpoint or peer
announcement does not implicitly supply it. This in-memory publication does not persist finality
across restarts. Light mode remains a separate partial-state runtime.

`jamnp_application_node` uses a complete configured chainspec, real Services and mutually
authenticated TLS with configured-genesis ALPN. It covers absent/unknown/explicit finality,
request FIN gating, a real canonical worker reply, cancellation after Done, own-read joined
shutdown, restart, foreign-lease preservation and no duplicate announcement on a clock tick.
`rpc_accumulation` covers atomic canonical/RPC finality, unknown/stale refusal and silent repeats.
`jamnp_node_service` supplies the real-stream scheduling witness and existing ownership/resource
coverage. Actual ARC lowering rejects duplication of `ApplicationNode`; copying would duplicate
worker ownership and move native callback addresses.
