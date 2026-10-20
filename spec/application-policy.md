# Explicit executable state policy

## Authority and scope

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Connect parsed executable configuration
to the existing canonical service owner without adding another executable or importer.

## Contract and completion tests

Opt in with `--with-state --chain FILE --state-writes COUNT --state-write-bytes BYTES`.
Both unsigned decimal limits are mandatory, including explicit zero for read-only
adoption. Accept 1–20 ASCII decimal digits within uint64; prove each multiplication
and addition before evaluating it. Reject malformed, missing, duplicate, overflowing
or inactive policy controls atomically, clearing previously valid Options.
State activation is valid only on server/client/mesh commands; it enables neither
RPC nor telemetry. A chain file can therefore initialize canonical state with all
listeners disabled. The fixed existing genesis trie ceilings remain authoritative;
mutation limits are never inferred from those ceilings or protocol parameters.

Options retains private typed policy values with guarded read access. The existing
three-argument Services.start selects canonical initialization only for explicit
state-enabled options. Both executable peer shapes already call that one path.
Seed validation happens before listeners/transport startup, including with RPC off;
missing or malformed complete state refuses without falling back to legacy startup.
Existing commands without state activation preserve their prior behavior. Explicit
four-argument component startup continues to use its caller-supplied policy.

Test parser range endpoints/overflow, leading zeros, signs/whitespace/Unicode,
missing/duplicate/inactive flags, mode restrictions and independent parse ownership.
Run default/disabled accessor crash probes and private-policy compiler guards.
Test no-RPC CLI-selected Services startup, exact limits, genuine adoption and RPC
publication. Build the real entry point and run process checks with valid seeds,
invalid/missing seeds and malformed options, including both peer shapes; retain
legacy RPC/UI/telemetry and parser checks. Verify inventory/tooling and formatting.

## Observed verification

Checked optimized native `app_options` and `application_services` pass. The latter
exercises genuine re-admission/finalization/adoption through CLI-selected startup,
exact independent mutation budgets and RPC publication, retaining 114,208 occupied
bytes before/after 1,000 lifecycle cycles. Both private-policy compiler probes and
all four strict default/disabled accessor assertion probes pass.

The normal executable builds and its help documents the explicit controls. The new
registered `application_state` E2E workload passes standalone startup with listeners
disabled, a retained two-process mesh exchange with normal bounded cleanup, actual
RPC queries/concurrent peer work, and missing/invalid seed and overflow refusal in
both peer shapes before readiness. Existing live RPC/UI, configured parameter and
genesis/service queries, and shared telemetry startup checks also pass.

Inventory passes with 203 native suites, 138 failure families and 1,870 data-driven
probes. All 40 affected verification/failure/mesh/RPC harness Python tests pass.
Pinned Nim/Rust formatting and whitespace checks pass. These are local macOS
results; complete/Linux verification remains in CI.

## Remaining work

There is still no live block import scheduler, consensus/fork-choice loop or durable
restart. Full/light startup modes and separate persistent databases remain future
work; this option trusts a supplied complete map and creates no light-state claim.
PVM owns execution/finalized successor selection. M1 framing is complete; full
state serialization and JAM/STF parity remain open.
