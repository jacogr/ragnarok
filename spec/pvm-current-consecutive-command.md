# Consecutive current command adoption

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. This test-only layer
uses the bounded genuine consecutive fixture through actual authenticated TLS and
`runCurrentDownloads`, with no runtime, policy-default, pin or certificate changes.

An independent forked responder validates the original parent request and the second request's
actual sealed first-child identity. A complete explicit consecutive policy permits two genuine
current adoptions. An explicitly short two-row recent-history policy is separately exercised against the
same two valid blocks: it must refuse continued preparation without widening itself, retain one
confirmed adoption, and return Exhausted with requested=2/adopted=1. All workers/endpoints join
before the responder is reaped. Neither reception nor returned bytes substitute for adoption.

Run `make unit SUITE=pvm_current_consecutive_command`. This layer checks real command authority
and scalar progress in memory. Complete expected maps are qualified by the lower fixture layer;
actual durable reopen and RPC inspection follow separately. It is not upstream current-pin full
STF/Thin VRF parity. M1 framing remains separate from complete state serialization.

Local macOS checked ARC/Clang results: genuine two-child command adoption and explicit second-child
C3 resource refusal passed, with exact independent request counts, semantic/inventory/format checks.
The original policy also adopted both blocks; it was not treated as an expected refusal.
