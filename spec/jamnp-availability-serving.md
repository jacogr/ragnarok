# Managed guarantor availability serving

Target JAMNP-S aa0e2b8498c0b1bc1725af2903704d701c6577ab CE137 and CE147.
A retained original computed report supplies its availability commitment and auditable
bundle. Exact incoming roots and shard indices select this provenance. Serving does
not assert report inclusion, a guarantee signature, or assurer duty.

Activation requires explicit independent availability read limits; defaults refuse.
Callbacks only frame bytes. Services stages a source-bound job after acquiring idle
canonical capacity, then preserves every ARC alias through exact collection or joined
shutdown. Session retirement during another read cannot release that read's source.
CE137 and CE147 get a separate 16 MiB hard reply bound; existing read methods retain
8 MiB. Shared physical stream, reply-byte, timeout and cancellation quotas still apply.
The worker reserves three complete wire budgets for detached copies before computation.

Completion: genuine report-backed serving over TLS, independently verified shard
proofs and exact original bundle bytes; disabled/missing/wrong roots/indices, resource
refusal, malformed framing, reset/expiry and uncollected Done retirement. Verify
existing read clients, canonical readers, Services and owner lowering. Assurer caching,
CE138/139/140/148, acquisition and ordinary operator policy activation remain subsequent.

Observed local evidence: the availability component suite passes with unchanged ARC
usage over 1000 cycles. All 29 actual TLS work/availability scenarios pass, including
independent CE137 proof verification, exact original CE147 bytes, optional activation,
invalid roots/indices/framing, resource refusal, local abort at uncollected Done,
joined host close, and report retirement while its read holds the graph lease.
Fresh compiler lowering rejects copying Services and StateProofWorker. Existing
read-client, canonical-read and read-validation suites pass with the new selectors.
The client explicitly requests its larger byte policy; defaults retain the prior 8 MiB.

Existing verification-worker and application Services suites also pass, with unchanged
ARC usage over 1000 cycles (115728 and 139360 occupied bytes respectively).
The production ARC/LTO build, format check and verification inventory pass locally.
These results cover this layer's code and pinned local dependencies; no Linux CI
or full JAMNP-S completion is claimed.
