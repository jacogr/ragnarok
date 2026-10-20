# Refinement historical lookup

Implement GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`pvm_invocations.tex` Omega_H (host 7), `accounts.tex` historicallookup/I,
and `definitions.tex` CgasHconst=1125/CgasHlinear=264. Keep vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` and all dependency pins unchanged.

Capture an immutable complete-map read context with a nominal invoking service and
lookup-anchor time. It is a caller-supplied context, not an authenticated refinement
invocation or a partial/light-state API. No state writes or accumulation composition
changes belong to this increment. Existing accumulation dispatch must continue to
route refine-only host 7 through its unknown-call branch.

Charge 1125 + ceil(264*r11/1024) with full-width arithmetic. Underfunding preserves
registers/memory and exact terminal debt before guest reads or namespace hashes.
Read the fixed 32-byte hash before account lookup, including missing/out-of-domain
service IDs. The full-width all-ones service sentinel selects self. Other IDs above
uint32 return NONE without narrowing. Validate existing selected account metadata.

Use the actual preimage byte length to derive its request key. A stored preimage without its
matching request violates the account invariant and is a local malformed-state error.
An actual length outside the existing E4 request-key domain is a local representability
limit, never a truncated key or a new protocol bound. Requested history is unavailable. Available [x] uses x<=t; Unavailable [x,y] uses
x<=t<y; Reavailable [x,y,z] uses x<=t<y or z<=t. Do not sort, repair, or add chronology
restrictions absent from this equation. Decode the complete request value with no
trailing bytes. Preserve the parked request namespace behavior and preimage integrity
assumptions of a supplied valid complete state; no content rehash is introduced.

Available values return their full length in r7 and copy a clipped suffix using
r10/r11 to r9. Absent values have zero cardinality, ignore the output pointer and
return NONE. Present-empty returns zero. Fixed hash/request/account capture and
selected-byte copying have separate finite bounds; local/backend failures expose
no response. Writes are atomic on guest destination failure and retain prior owners.

Completion: independent boundary truth tables for all four request shapes, missing
and malformed account/request/preimage cases, raw length namespaces, full-width
service/pointer/offset/length/gas, empty versus absent, clipping and cross-page atomicity,
local/backend refusal, immutable detached ownership, actual generic host-loop integration,
source-local runtime/compiler guards and fresh 1,000-cycle ARC release.

Local evidence: checked native `pvm_historical_lookup`, `pvm_accumulation_dispatch`
and `pvm_host_execution` pass, each with fresh 1,000-cycle unchanged ARC occupancy.
Three optimized runtime extraction guards and four compiler privacy/nominal rejections
pass. Verification inventory, inventory/provenance Python tests and pinned formatting
pass. These are local macOS results; exact-head Linux CI remains independent.

Next: refinement export host and bounded refinement invocation/context assembly.
Complete refinement execution and whole-block parity remain open. M1 framing is
complete; full state serialization remains open. Existing specification gates remain.
