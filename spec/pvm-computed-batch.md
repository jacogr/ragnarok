# Source-bound computed guarantee batches

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
reporting_assurance.tex guaranteesextrinsic and reporters; serialization.tex
natural sequence count and guarantee tuples. Vectors remain
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: combine nonempty immutable ComputedGuaranteeEnvelope sources only. Require
strictly ascending unique report cores, the exact same original complete-map
version, exact post-assurance transition snapshot, full sealed candidate header,
and all original Parameters. Refuse foreign contexts even when roots match.
Derive configured cores and structural validator ceiling from original authority.
Empty inputs cannot synthesize context authority and are refused.

Bound source count, whole canonical wire, header copies and unique reporter union
before variable output allocation. Fixed scratch storage is bounded by 341 cores
and 1023 possible distinct credentials. Deduplicate reporter keys by their full
32-byte Ed identity, not validator indices or occurrences. Preserve each source
and its exact credential/report tuple. Use the maintained guarantees encoder with
one canonical outer natural count. Getters copy wire/facts/keys; source handles
share immutable provenance. No hashing, verification, signing or PVM execution.
This establishes composition only, not report policy, candidate inclusion,
availability or final publication.

Completion plan: genuine multi-core work against one shared signed original
and posterior context, explicit count+standalone-wire oracle, canonical codec
roundtrip, unique reporter union/caps, order/duplicate/foreign/default refusals,
exact and short budgets, copied outputs, detached lifetimes, zero new hashes,
1000-cycle ARC evidence, runtime extraction and compiler privacy/nominal guards.
Recheck the changed shared fixture's original consumer. Run inventory, affected
harness/provenance tests and pinned formatting with merged fixture infrastructure.

Next: exact computed-batch binding to candidate guarantees and existing report
admission. M1 framing is complete; full state serialization remains open.

Local evidence: checked optimized macOS ARM64 `make unit SUITE=pvm_computed_batch`
passes with genuine triple credentials on two populated cores, exact count-plus-
standalone-wire comparison and complete codec roundtrip. Repeated actual Ed key
reduces the six-key union to five while retaining all credential records. Exact
and short caps, duplicate/out-of-order cores, default/late-invalid sources and
independently rebuilt equal-root foreign contexts behave as specified. Copy,
detached lifetime and zero-new-hash checks pass. Fresh 1000-cycle ARC occupancy
is 286256/286256. Existing `pvm_computed_roster` passes unchanged 320176/320176.
Eleven strict optimized runtime guards and six exact compiler rejection fixtures
pass. Inventory, 78 native-harness tests, 11 provenance tests, six specialized-
control tests, formatted unit/driver semantic checks and pinned formatting pass.
Logs are under `build/computed-batch-*`; exact-head Linux CI remains separate.
