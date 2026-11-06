# Authenticated admission boundary

Scope: generic synchronous server admission using the authenticated leaf certificate, selected
ALPN and prospective native peer slot. JAMNP-S pin remains
`aa0e2b8498c0b1bc1725af2903704d701c6577ab`. Nim owns validator/builder capacity policy;
C supplies opaque TLS/LSQUIC facts only. Builder ALPN requests a reservation and grants no
protocol privileges. This prerequisite alone does not implement validator admission policy.

The optional callback is installed once before IO. Exactly one permits retention. Refusal consumes
no peer slot and emits no accepted observation. Default listeners keep their previous admission.
Both metadata byte spans are borrowed only during the callback after server authentication.
Policy callbacks may update application state, but must not recursively poll, close or reopen
the transport while its native admission stack is active.

A startup-allocated registry tracks at most peer capacity plus 64 pending/live SSL objects. SSL
ex-data cleanup clears entries before storage is freed. Each admission correlates using public
`lsquic_ssl_to_conn` on the live SSL object after promotion; keys and socket tuples are never used
as surrogate connection identity. Exhausted/missing correlation fails closed. No upstream changes.

Completion checks: real TLS base/builder concurrent attempts with the same client certificate,
policy refusal before acceptance, capacity preservation/reuse, IPv4/IPv6, default TLS regression,
and bounded owner cleanup. Validator reservations and epoch transitions remain following work.

Local checked ARC/release tests pass for simultaneous same-key base/builder TLS in both IP
families, 72 additional refusals per family (beyond the 66-entry two-peer registry), later admission
and genuine slot reuse. Late first registration refuses atomically, and reopening a retired owner
permits fresh setup. Default ALPN, 20-peer capacity and persistent-stream suites also pass.
Production `make build` also passes with ARC/LTO.
