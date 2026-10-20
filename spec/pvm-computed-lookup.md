# Source-bound computed lookup anchor

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
reporting_assurance.tex limitlookupanchorage and ancestor h/h-prime equations;
header.tex full sealed-header identity. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume RecentComputedReport and stable borrowed older OwnedHeaders in
newest-first order. Derive the admitted parent endpoint, candidate slot, report
lookup tuple and original execution Parameters internally. Require lookup slot
at least max(0, candidate slot - original maxLookupAnchorAge). Derive header
core/epoch domains from original Parameters; use 3*cores as the structural author
ceiling, not proof of active roster membership. No caller-selected clock, age,
parent, root or replacement execution parameters are accepted.

Preflight local header-count, per-header byte and aggregate encoded-byte ceilings,
including the admitted parent, before variable allocation or hashing. Recapture
all full headers under that derived profile and hash their entire sealed bytes.
Require strictly decreasing slots and exact child.parent == hash(older) for the
whole supplied sequence, including headers beyond a matched lookup. Locate one
older header whose full hash and slot match the original lookup tuple, and compare
the immediately newer retained child's prior-state root with lookupStateRoot.
A sufficient prefix ending at the lookup is accepted; every additionally supplied
suffix is still validated. The lookup header's own prior root is not its posterior root. Both headers must
be ancestors; the admitted candidate is not added as a witness, so the endpoint
parent alone cannot satisfy the pair. Missing/truncated history has no fallback
to C3. Retain original source, all recaptured headers and copied match/resource
facts only after complete success. Defaults/refusals contain reasons alone.

Resource policies count canonical encoded preimages and handles, not aggregate
process memory: shared source allocations, fixed metadata and codec/hash stack
scratch are excluded. Native descriptor extents and every sum/narrowing are
proved before allocation. A backend refusal never exposes a partial chain.
No guest execution or state publication occurs.

This closes lookup tuple/age/ancestry against the existing admitted endpoint. It
inherits that endpoint's trusted-parent assumption; it does not establish chain
consensus/finality, complete parameter/active-roster/assignment eligibility,
exporter-state trust, report inclusion, availability distribution/assurance,
credentials or signing permission.

Completion coverage: genuine linked full sealed headers,
original C3-bearing execution and completed recent/state/block stages; independent
literal full-chain hash witnesses; exact age boundary and one-slot-too-old,
saturating subtraction, immediate-child posterior root versus own prior root,
last retained lookup, wrong hash/slot, candidate exclusion, missing/duplicate/
reordered/forked/nondecreasing headers and late suffix failure; exact/refused
count/per-header/aggregate policies; zero hashes on early age/policy refusal,
backend prefix failure/retry, original/caller-copy/detached lifetime, full-width
indices and 1000-cycle ARC release; compiler privacy/nominal guards and strict
optimized result/accessor probes with genuine positive controls.

Next: [complete configured parameter binding](pvm-computed-profile.md), then posterior
active-roster/guarantor assignment eligibility and availability/signing integration. M1 framing is complete; full state serialization
and whole-block parity remain open.

Local evidence: checked optimized macOS ARM64 `make unit SUITE=pvm_computed_lookup`
passes genuine original execution, admitted linked parent and C3/state/recent
stages. Three full sealed-header hashes for slots18/19/20 match independent
literal Python hashlib witnesses; unsigned prefixes and seal mutations differ.
The original age2/candidate21/lookup19 inclusive boundary and age100 saturating
case pass; age1 rejects before hashing. Immediate-child root8 succeeds while the
lookup's own prior root7 fails; the oldest retained header succeeds using its
child. Wrong hash/slot/future claims, candidate-as-child endpoint substitution,
missing/skipped/duplicate/reordered/forked headers, a genuinely hash-linked equal-
slot pair, and a corrupt suffix after a matching prefix are refused.

Exact three-header/297-per-header/891-aggregate policies pass; each one-short
policy and invalid source/age refuse before any hash. A complete accepted chain
hashes three times. First and third-call backend refusals expose no owner;
recovery and prior successful owners remain valid. Source/header/info-copy and
caller-list replacement isolation, detached lifetime and full-width invalid
indices pass. Fresh 1000-cycle ARC occupancy is 130128/130128 bytes for the
isolated warmed success/late-ancestry/late-backend workload.

Thirteen strict optimized result/accessor probes and six compiler privacy/nominal
guards pass with genuine admitted-state and linked-header controls. Formatted
unit/driver semantic checks, inventory, 20 affected tooling tests, one independent
full-chain reference test and pinned formatting pass. All 3011 prior source/build
inputs are byte-identical; pins and lower implementation modules are unchanged.
Full local logs, covered input identity and reuse proof remain in ignored
`build/computed-lookup-*` files. Exact-head Linux CI remains separate; remote
checks were not requested.
