# Repeated bounded reentry

Current transfer support is specified in [transfer-aware reentry](pvm-transfer-reentry.md).
It replaces the outgoing-transfer gate below with bounded canonical collection, paid-gas
restoration and combined transfer/report inputs for first and repeated rounds. The
report-only implementation and verification record below is historical; queue, depth,
state ownership and stopped-source contracts remain applicable.

## Scope and authority

Advance a certified completed reentry into the next report-only accseq entry, using the same
prepared/completed public types for every depth. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f` (`accseq`, `accpar`,
`fnprovide`) and pvm_invocations.tex SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb` (actual gas collapse).
Pins, domains and the parked request namespace question do not change.

Derive each cumulative original-queue offset, recursive budget, complete prior and current batch
only from genuine immutable completion. Prove depth/offset arithmetic and gas subtraction before
use. Require an explicit nominal maximum retained depth on repeated advance, and refuse advance
from a stopped entry. Preflight bounded selection/materialization before privately applying only
the just-completed batch under inherited limits. Preserve no-bypass, whole-report rollback, empty
allowances/transfers, exact-prior ownership and outgoing-transfer gates. Never replay older batches
or rescan retained history to recover original authenticated block provenance.

Preparation and completion now own one private immutable certificate graph in accumulation_reentry;
the existing execution module remains a narrow compatibility export. Keep existing source/input/
state/bootstrap/completion APIs and first-entry behavior. Retain the immediate previous completed
reentry through a guarded accessor; first entry reports no previous reentry. Root provenance remains
constant-time. Failed/default alternatives contain reasons alone. No public raw-field constructor
or mutable snapshot view is introduced.

Completion/application stay caller-driven and bounded; no unbounded execution loop is added.
Transfer-aware recursion, account-effect merger, output union and final block publication remain
separate. M1 framing is complete; full state serialization and accumulation/block parity remain open.

## Completion tests

Use real signed queues and initial/continuation/reentry PVM executions to advance through at least
three dispatched reentries and a terminal entry, checking exact offsets, actual gas rather than
reservations, previous/root/source identity and original report order. Verify nominal depth caps,
stopped/default sources, short materialization/work limits, full-width ordinals, hash-disabled
no-op application, unchanged caller snapshots, stale/foreign outcome rejection, and detached
history lifetime. Reuse prior genuine provision-changing/backend-refusal tests for the shared
application helper. Check 1,000 complete/advance/refused history ARC cycles, strict extraction,
privacy and nominal guards, old execution import compatibility, Python/inventory and pinned format.

## API and ownership

The existing two-argument `prepareAccumulationReentry(CompletedAccumulationContinuation, config)`
continues to construct the first entry. The new overload accepts `CompletedAccumulationReentry`,
config and an explicit `AccumulationReentryDepthLimit`. `AccumulationReentryInfo.depth` is a nominal
observation starting at one. The new overload refuses stopped entries and checks current depth
against the cap before incrementing, so even `high(uint64)` is a policy bound rather than an
allocation size or unchecked arithmetic input.

Both constructors feed one private `ReentryStep` into the existing bounded selection/materialization/
application phases. This object contains only genuine certificate-derived root, prior, current
batch, progress and actual gas. Its fields are never public construction parameters. Each new entry
retains the immediate completed predecessor and the original completed continuation root directly.
`reentryPrevious` reports `NoPrevious` for first entry and `Uninitialized` for defaults; selected
success retains the actual predecessor. Root/previous access requires no history traversal.

Preparation and completion now live together in accumulation_reentry so neither needs a public
raw-data bridge to build the other's private certificates. The unchanged completion implementation
was moved, renaming only its private owner and applying pinned formatting; source comparison
confirmed that equivalence. accumulation_reentry_execution selectively re-exports its previous
execution API. Existing bound invocation paths continue to derive entropy from direct root
provenance, while the complete batch adapter still enforces exact input/prior/slot ownership and
supported account effects. Actual graphs are acyclic: new preparation retains an already completed
older node; no existing node is mutated to point forward.

## Local verification

The signed seven-report fixture uses real initial, continuation and repeated reentry PVM runs.
First reentry consumes original reports 66/67; second starts at offset 4 and selects report 68;
third starts at offset 5 and selects report 69 plus zero-gas report 70. Recursive budgets are
200,868, 200,824 and finally 200,780 after actual 44-gas rounds, rather than subtracting 200,000-gas
reservations. The terminal fourth entry has completed offset 7 and no inputs. Completing it cannot
authorize another entry, even with a full-width cap. All-skip sources preserve zero actual gas.

Tests verify exact depth caps and zero/full-width policies, previous/root/input identity, nominal
original-queue ranges, copied observations, detached history lifetime, defaults, stopped entries,
short selection/operand/input limits, full-width report ordinals and foreign outcome rejection.
Hash-disabled no-op advancement preserves source snapshots. A prior provision-changing source
remains the actual map through repeated advance; older batches are not replayed. The unchanged
first-entry suite exercises literal successor roots and late fulfillment backend refusal through
the same shared private helper.

Passed `make unit SUITE=accumulation_reentry_cycle`: 1,000 complete/advance/refused-history cycles
retained 914,944 occupied bytes before and after. The original reentry suite passed with 1,030,192
bytes before/after 1,000 changed-map success/refusal cycles. The execution compatibility suite
also passed, retaining 2,010,944 bytes before/after 1,000 cycles. Both expanded reentry extraction/nominal
coverage (13 runtime and eight compiler probes) and existing execution guards (13 runtime and 12
compiler probes) passed, including the old execution import. Python discovery passed 443 tests
with seven skips; inventory reports 106 failure families, 1,606 probes and 164 native suites.
Pinned formatting and diff checks passed. Logs are retained under `build/accumulation-reentry-cycle/`.

These are local macOS checks, separate from exact-head Linux CI. Diagnostic iterations reused
prepared libraries and the previous signed fixture gained optional authenticated tail rows;
unchanged fixture defaults remain covered by its existing consumer suite. No PVM host or account
merger behavior was changed. Next work collects/merges output pairs across the retained rounds and
connects final publication; account-effect and transfer integration remain explicit gates. M1
framing is complete; full state serialization and accumulation/block parity remain open.
