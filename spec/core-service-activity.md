# Core and service activity projection

## Scope and authority

Implement the per-block core/service portion of GP 0.8.0 C(13), statistics.tex Cores and Services,
revision `07f041dabd073f9018b418e9ee72e79dd2185401`, SHA-256
`a8bee7c99853ed116fb7ed5e45e9977c7c323ad386e5a7e6c8cefba509f2d2a9`.
The same revision's definitions.tex fixes Csegmentsize = 4104, SHA-256
`5e11b5f8bc983aa9b12d6e8d86463ce7c5a3f504bc4575e0944b4a941b138138`.
Reuse existing nominal C(13), report-refinement, provision and accumulation-statistics records.
No codec widths or pins change; gas remains the established vector compact natural.

This layer is a pure projection over explicit stable observations. It certifies no block,
report credentials, availability, preimage admission or accumulation execution and publishes no
state entry. The next layer must derive its inputs from the exact authenticated candidate above
[validator binding](accumulation-validators.md), then combine all four C(13) components.

## Contract

Accept separate incoming and newly-available report lists, raw assurance records, numeric-service
ordered unique per-service PreimageProvision contributions and ordered unique accumulation S rows.
Explicit cores must be in 2..341. Validate initialized report owners, in-profile report cores and at
most one report per core within each list. Cross-list core overlap is allowed: incoming replacement
and newly-available predecessor have different statistical roles. Do not inspect available-report
digests for refinement or service keys. Assurer indices must be strictly ordered/unique, and unused
bitfield bits must be zero; signature, anchor and roster eligibility are external responsibilities.

Start every core/service tuple at zero, without accepting old per-block statistics. Incoming digests
contribute refinement gas/imports/extrinsic counts/bytes/exports to their core and service; every
digest contributes one service refinement count, including failed work and zero load. Incoming
report headers alone supply bundle bytes. Newly-available headers alone supply DA load:
`bundleLength + 4104 * ceil(segmentCount * 65 / 64)`. SegmentCount is E2 and BundleLength E4,
so explicitly widened products and addition fit uint64. Popularity sums every raw assurance bit,
even without an incoming or newly-available report on that core. Authorization gas, accumulation
gas allowances and available-report digests do not contribute refinement statistics.

Service keys are exactly reported services union provided services union keys(S), sorted numerically.
Provision counts must be positive; bytes may be zero for empty preimages. Contributions remain
service-specific, preserving the existing [provision contract](preimage-transition.md) and its
published subsystem-statistics evidence rather than duplicating global totals at every service.
S rows contain only accumulation count, transfer count and accumulation gas, with a nonzero triple;
reject non-accumulation fields and all-zero/noncanonical S keys rather than silently ignoring them.
Copy all three S fields, including transfer-only or gas-only activity. Do not infer account existence.

Preflight independent incoming/available/digest/assurance/provision/S ceilings and native candidate
extents before scratch allocation. Enforce the retained-service ceiling while merging before
allocating the final service array. Aggregate every uint64 counter/gas field using subtraction
checks before addition. A late overflow, invalid input or limit refusal exposes no partial rows.
Opaque acyclic ownership retains only independent fixed core/service tuples and copied info;
nominal full-width extraction returns fixed copies. Input owners/arrays may be released after
success. No hashes, map changes, eligibility checks or stale validator rows occur in this layer.

## Completion tests

Require independent literal core/service tuples covering all fields, role separation, failed work,
shared services across cores, numeric ordering, provided-only/empty-blob and all three S-only cases.
Exercise zero reports, raw popularity on reportless cores, empty initialized projection, independent
limits, duplicates/disorder, wrong/default owners, foreign cores and unused bitfields. Verify DA
rounding at 0/1/63/64/65/65535 segments and full-width bundle length. Every report refinement metric
must accept its exact uint64 endpoint and reject overflow both within a core and across cores at
one service. Check full-width contribution/policy/index domains, copied observations/rows, source
lifetime, hash-disabled operation and 1,000 ARC cycles. Add strict result/default/index extraction
and compiler privacy/nominal probes; run selected native suite, guards, Python/inventory and pinned
formatting. Reuse unchanged codec, provision-admission, validator and accumulation algorithm evidence.

## Remaining work

Authenticated core/service input binding and combined C(13) publication, remaining transfer/account/
privilege coordination and whole-block publication remain open. M1 framing is complete; full state
serialization and accumulation/block parity remain open.

## Local verification

`make unit SUITE=core_service_activity` passes. Independently encoded reports yield literal tuples
for all eight core and eleven service fields, including two cores reporting one service, failed
zero-load work, distinct incoming/available roles and raw popularity on a reportless core. Seven
numeric-service union entries cover overlapping sources, empty-blob provision, provided-only,
count-only, transfer-only and gas-only S records. Available-only digest services never enter the
union; their deliberately maximal refinement load does not contribute. Authorization gas and
accumulation allowances remain separate from refinement gas.

DA witnesses match literal results at 0, 1, 63, 64, 65 and 65,535 segments. Maximal E4 bundle plus
maximal E2 segments yields 4,568,125,431 bytes without narrowing. The 341-core profile accepts bit
340 and refuses padded bit 341. All five report refinement fields accept their exact uint64
endpoint and refuse overflow both within one core and across separately valid cores sharing a
service. Full-width provision counts/bytes and all three S fields remain intact when combined with
reported service activity.

Exact/short/full-width work policies, default/foreign report owners, duplicate cores, duplicated/
disordered assurance/provision/S lists, unused bitfields, zero provisions, zero or polluted S
records and full-width extraction ordinals pass the intended boundary witnesses. Mutating scoped
input lists, observations and extracted tuples cannot change retained output. Empty initialized
projections start from zero. With both hash backends disabled, all witnesses make zero Blake2b
calls. Over 1,000 scoped success/late-service-limit refusal cycles, occupied allocation stays at
17,136 bytes before and after.

Seven strict runtime extraction/index guards and five compiler privacy/nominal guards run through
existing source-discovered runners. Python discovery passes 445 tests with seven skips; inventory
discovers 115 failure families, 1,695 probes and 180 native suites. No shared fixtures, existing
production consumers, codecs, validator/accumulation implementations, preimage admission or PVM
code changed; their prior algorithm evidence is reused. Logs remain under ignored
`build/core-service-activity/` and native selected/evidence directories. Results are local macOS
checks, separate from exact-head Linux CI. M1 framing is complete; full state serialization and
accumulation/block parity remain open.

The final seven runtime and five compiler guard checks pass. Pinned format/check passes for 1,575
Nim files and the Rust crate; `git diff --check` passes. Earlier compiler feedback was resolved by
short independent policy predicates and explicit qualification of colliding nominal test types,
without changing the pinned toolchain or formatters.
