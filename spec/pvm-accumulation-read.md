# Accumulation storage read host

## Scope and authority

Implement read (4), Omega_R, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm_invocations.tex`,
with definitions.tex cost `2407 + ceil(1736*r9/1024) + ceil(248*r12/1024)`.
Charge full-width requested extents before memory, account lookup or local copy policy.
Capture the raw key at r8/r9, select exact self-sentinel or uint32 service, derive the
existing storage namespace, clip r11/r12 against the stored value, and atomically
write to r10. Return the full length or NONE; present-empty returns zero. Empty
intervals accept any address. Key and selected output each obey copyLimit.

Completion witnesses cover exact rounding, full-width costs and signed-debt refusal,
self/other/absent accounts, empty/absent keys and values, namespace separation,
clipping, overlapping/cross-page writes and atomic panic, malformed/backend/local
failures, immutable source/effects and repeated ARC release. Shared lookup and
provide charging consumers retain their existing checks. State/test infrastructure
from master is reused; no shared inventory entries are needed.

## Remaining boundary

No account mutation host is implemented, so the current regular implication's
initial complete map is the current account backing. Read neither fulfills
provisions nor publishes state. Write (5), info (6), grow_heap and the remaining
accumulation calls are later increments. Existing signed-gas representation and
provision/hash-return gates remain explicit; this is not full Psi_A execution.

## Interpretation and ownership

Both independently rounded gas terms retain all high bits through a two-limb cost.
Affordability preserves exact debt up to 2^63; greater debt remains the existing
local GasRangeExceeded gate. Key memory is captured before account lookup, and
canonical metadata is validated before deriving C(service, E4(UINT32_MAX) || key).
An orphan storage mapping cannot create an account. No preimage namespace or
alternate key encoding is accepted. Missing values have cardinality zero under
notation.tex; present-empty values instead return length zero.

Key capture precedes any overlapping output. The retained store value is sliced
only after clipping the offset, so short copies do not allocate the complete value.
Guest writes preflight every effective page and publish one immutable successor.
Panic preserves memory and r7; only paid gas changes. Malformed metadata maps to
InvalidContext, namespace backend refusal to BackendFailure and local copy policy
to LimitExceeded, with no partial machine/effects on local failure. The source
machine and both implication contexts remain immutable.

## Local verification (2026-10-19)

Five selected native suites passed: read, lookup, provide, dispatch and outcome.
Each retained fresh 1,000-cycle ARC evidence with unchanged occupied memory.
Read covers key length/namespace separation, empty keys/values, bounded suffixes,
input/output page crossings, overlap, atomic panic, backend/local failures, full
register widths and independently frozen gas constants. Those constants include
a cost above uint64 with low-limb borrowing, addition of the full value term,
and exact 2^63 debt versus one gas unit beyond the representable boundary.

Nine existing runtime result probes and five privacy rejections passed. Forty
selected discovery/native harness Python tests, inventory validation, pinned
Nim/Rust formatting and diff whitespace checks passed. Logs are under
`build/pvm-read/`, including native.log, guards.log, targeted-results.json,
python-inventory.log, python-native.log and format-check.log. Consumer runs reused
one prepared library set while retaining fresh per-suite evidence. This is local
macOS verification; full verification and exact-head Linux CI remain CI work.
