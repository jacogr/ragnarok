# Managed original-bound work report preparation

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab` CE134/135/137/147 and Gray Paper
`fad0ded4a433052397bf7234352a57fe491883f7`. Extend the retained genuine refinement through
original auditable-bundle encoding, bundle/export erasure coding, availability commitment,
canonical computed report and its GP guarantee transcript. No caller-supplied replacement bundle,
report hash, export root, authorizer trace or successful certificate may substitute for that chain.

Each stage has explicit independent resource caps and preserves its actual selected failure cause.
Computation remains separate from report inclusion, signing permission, credentials and distribution.
The network session's source-derived active roster count supplies the encoding shard count; it is
not inferred as three times the configured core count. Unknown epochs and expired rotations refuse
new managed report work. Original-source and exact worker/session gates precede capture and collection.

CPU jobs, intermediate artifacts and completed report ownership stay in Services under its existing
shared exclusive graph lease. Network hosts observe only fixed metadata/tokens during execution.
Cancellation retains selected aliases through Done until exact collection or joined shutdown and
must preserve foreign worker generations. A completed report is retained until downstream processing
explicitly releases its original session.

Completion evidence must cover genuine report/availability/transcript bytes from live managed work,
variable actual populations, default and stage-specific failures, stale/foreign controls,
cancellation/Done/close, foreign Done preservation and repeated original-source release. Existing
work-policy-v1 enables authorization/refinement only; no new erasure/report budgets are inferred.
Report sharing, signatures, source eligibility, availability serving and auditing remain subsequent work.

## Observed verification

`jamnp_work_report` passed with genuine imported-bundle byte preservation, canonical report/hash
transcript checks, six/nine-shard source geometry and every selected failed stage. A two-core
source correctly refuses nine shards at report serialization; a distinct three-core source is
configured before refinement for the positive nine-shard case. Its 1,000 fresh report/availability
preparation-and-release cycles retained 209,280 bytes before/after.

`jamnp_work_dispatch` passed 20 actual ApplicationNode TLS/PVM scenarios, including report success,
real stage refusal, expired duty, cancelled Done, joined close and foreign Done preservation during
fixed metadata observation and release. Report-stage release keeps the host's exact session until
collection. `jamnp_work_duty` proves actual six/nine populations independently of core capacity and
fixed rotation expiry, with 1,000 release cycles (58,864 bytes unchanged).

Fresh actual lowering rejected duplication of the changed Services and StateProofWorker owners.
The managed computation-only API refuses network report duty, and its 1,000 release cycles remain
40,816 bytes unchanged. Shared worker/Services, light-runtime and foreground-node consumers passed.
These are local checked ARC/Clang results on master `7ab0549` plus this native stack.

Application build, formatting and inventory checks also passed. No exact-head Linux CI run is claimed.
