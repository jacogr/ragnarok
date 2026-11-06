# Managed application builder dispatch

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab` CE133/146, Gray Paper
`fad0ded4a433052397bf7234352a57fe491883f7`. Extend staged native streams and current-source
guarantor duty through the ordinary ApplicationNode poll loop. Activation requires an explicit
finite execution policy; default hosts do not accept work. The dispatcher owns detached wire
buffers and exact native/session tokens, while Services keeps all canonical owners and results.

One admitted bundle has separate authorization and body/refinement CPU turns. Body waits hold no
CPU lease. Before acknowledging a genuine completed refinement, recheck the live stream, original
source and observed rotation. Deadlines, reset, changed duty and shutdown retire only this session;
foreign worker generations, including uncollected Done, remain untouched. Retain completed results
inside Services until the next pipeline stage explicitly releases the one-slot completion.

Completion checks: real TLS/PVM successful ApplicationNode dispatch; disabled/default policy,
wrong core, corrupt proof, withheld FIN, clock rotation, deadline, reset through Done, foreign Done
while waiting, joined close, exact stale controls and repeated release. Actual ApplicationNode
and dispatcher copy lowering must reject duplication.

CE133 preferred acquisition requires a separately supplied `WorkAcquisitionPolicy`: at most1023
attempts, a positive request deadline no greater than120 seconds, and a reply ceiling between8 bytes
and16MiB. It stays disabled with only the existing work policy. Derive the complete ordered CE148
request on the authorization CPU turn from the original package and exact selected C(3). The host
receives independent bytes, selects current authenticated validator connections, and retains only
raw transcripts and exact tokens while waiting. An unfinished UP0 source handshake or occupied
native reservation is backpressure under the overall work deadline, not a failed peer attempt.

Fetch cancellation, builder reset and close retire the exact outbound token without collecting a
foreign CPU generation. Empty manifests need no remote request. Exact reply verification, original
root/index matching, complete input binding and refinement share one managed CPU turn. Only its
collected success with a fresh source and duty can acknowledge the builder.

CE139/140 fallback, ordinary acquisition-policy startup activation, report sharing/signatures and
availability distribution remain explicit subsequent work.
No ACK or retained refinement is a guarantee, availability certificate or canonical adoption.

## Observed verification

Local checked ARC/Clang tests passed: `jamnp_work_dispatch` (13 actual TLS/PVM scenarios),
`jamnp_application_node`, `jamnp_ticket_production`, `jamnp_node_command` and
`jamnp_preimage_gossip`. Fresh actual lowering rejected copying both WorkDispatcher and the
changed ApplicationNode owner with their unavailable `=dup` diagnostics. Existing ticket
production and gossip release checks retained identical before/after ARC use over 1,000 cycles.

The live tests hold admission with one host poll per step, so fast CPU completion cannot skip
the cancellation witness. Injected deadline time remains monotonic in subsequent polls. These
corrected test assumptions; no production guard was weakened. Completed-result release during
a foreign Done lease defers source retirement until that foreign generation is exactly collected.

Application build, `make format-check` and `make check-inventory` also passed. This evidence
is local; no exact-head Linux CI run is claimed.
