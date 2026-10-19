# Accumulation designate host

## Scope and authority

Implement designate (17), Omega_D, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex designate
row, definitions.tex (CgasDconst=1100, CgasDlinear=302), and safrole.tex
valcount/validatorkeys. Charge the complete mathematical `1100+302*r8` before
reading `336*r8` raw bytes at full-width r7. Bad memory panics before HUH
for an invalid count or a caller other than the current delegator. Valid counts
are multiples of three from six through three times the current core count;
they need not equal the initial population. Success returns OK and replaces
the complete ordered staging roster. Keys/metadata are opaque bytes; zero or
repeated records remain valid. No count prefix occurs in guest input.

Version the current typed staging owner with serialized C(7) in the complete
map. Preserve initial provenance, queues, privileges, provisions, yield and
exceptional checkpoint. C(7) keeps its canonical compact count prefix. State
API authorization and protocol/cardinality checks remain independent of host
validation. Copy, typed allocation, component and store ceilings are explicit;
backend/local refusals expose no partial execution or successor state.

Completion witnesses cover count bounds, growth/shrinkage, gas/overflow/debt
boundaries, memory/count/authority precedence, opaque field order, current
privileged authority, coherent serialized and typed state, prior owners,
checkpoint selection, preservation by later effects, borrowed-input independence,
resource/backend refusals, guarded extraction and ARC release.

## Arithmetic and explicit boundaries

Cost uses bounded base-2^32 limbs, preserving all high bits. Existing signed
negative-gas representation refusals remain explicit GasRangeExceeded.
Unlike bless, funded per-item gas does not prove the larger raw record extent
fits uint64. Preflight against the 2^32-byte physical memory domain before
forming 336*z; an impossible nonempty interval is charged panic, never wrapping
into a small readable input. Zero records still capture an empty interval for
any pointer before returning HUH.

Protocol core count must agree with the prepared staging profile. Component
ceilings are checked after protocol memory and HUH ordering, before typed
record allocation. Heap and conflicting-bless-allowance questions remain gated
in their existing contracts. No pins change, no key validation or roster
sorting/deduplication is invented, and no persistent block state is published.
Remaining accumulation hosts and complete Psi_A remain later work.

## Local verification (2026-10-19)

Eleven affected native suites passed: designate, assign, bless, effects, write,
info, provide, dispatch, outcome, provision integration and machine initialization.
Every suite retained fresh 1,000-cycle ARC evidence with unchanged occupied memory.
Designate witnesses cover both two/three-core profiles, six/nine-validator
populations, shrinkage, exact opaque field order and zero/duplicate records,
full-width pointers/counts/credits, empty input, memory-before-HUH ordering,
complete high-limb gas costs, exact deficits including 2^63, unrepresentable debt,
funded byte-extent overflow, raw/typed/encoded/map ceilings, delegator handoff and
reauthorization, panic/OOG checkpoints, subsequent assign/bless/yield/storage
preservation, prior owners, borrowed-input independence and immediate/delayed
Merklization failure. Aggregate store refusal is witnessed before hashing.

All 111 production semantic checks, 28 runtime extraction refusals, nine privacy
rejections, the existing assign core-domain rejection and 42 selected inventory/
failure/native-harness Python checks passed. Pinned parser metadata confirms
attached documentation for both new public routines and three changed public
fixture routines. Inventory, pinned Nim/Rust formatting and whitespace checks
passed. Removing an unused import and refining fixture comments needed only a
focused final effects semantic check; passing consumer suites were retained.

Evidence is retained under `build/pvm-designate/`: native.log, modules.log,
guards.log, targeted-results.json, selected Python logs, inventory.log,
final-effects.log and format-check.log. This is focused local macOS evidence,
not complete verification or exact-head Linux CI. The selected suites reused one
prepared native library set with fresh execution/output/ARC checks. Existing
verification helpers were reused instead of rebuilding their orchestration.

Test fixtures now optionally select two or three cores and an initial delegator.
Their default two-core/six-validator profile, ordinary initial roles, envelope
layout and production policy remain unchanged. The three-core fixture retains
six initial staging records while allowing a valid successor of nine.

Next bounded work is service creation (new, 19), beginning with its pinned row,
funding and service-ID allocation checks. Existing specification gates remain
separate from this completed host tranche.
