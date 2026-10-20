# Inner-machine memory transfers

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`pvm_invocations.tex` Omega_P/Omega_O and fnmemgas, `definitions.tex` P/O gas;
vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`. No pins change.

Scope: hosts 10 (peek) and 11 (poke), using the same invocation-local map as
machine/pages/expunge. Registers 7/8/9/10 select inner ID, caller address, inner
address and byte count. Peek charges 377+ceil(336*z/1024); poke charges
297+ceil(224*z/1024). Quotient/remainder pricing handles the whole uint64 count
domain without overflowing; every possible cost/debt remains below 2^63.
Underfunding precedes all permission, ID and copy-policy checks, retaining exact
debt and all original registers/memory/map owners.

Peek requires the whole caller destination writable, then checks WHO for an absent
full-width inner ID, then OOB for unreadable inner bytes. Poke requires the whole
caller source readable, then WHO, then OOB for a nonwritable inner destination.
Caller permission/range failure panics before WHO. Natural ranges never wrap or
truncate high address bits; empty intervals ignore pointers but still check ID.
No partly readable/writable prefix can become a partial transfer.

Allocation-free readable/writable range queries establish protocol order before the
local MemoryByteLimit. Only a fully accessible transfer tests that copy policy.
Local exhaustion returns LimitExceeded with no response or partial successor.
Peek copies inner bytes into an immutable caller-memory successor and retains the
original map. Poke copies caller bytes into the selected inner RAM successor,
preserving caller memory, every other slot, program, PC, charged flag and policies.
Only r7 changes to OK/WHO/OOB on affordable nonpanic rows. No public setter can
replace a map's memory owner or source provenance.

Completion: literal gas costs/rounding/high counts and exact underfunding; complete
cross-page transfers and prefix/suffix preservation; caller/WHO/OOB/copy-policy
priority, read-only permissions, empty and overflowing ranges; copied/detached
immutable snapshots and untouched other slots/metadata; real create/pages/poke/
peek guests, return bytes, gas normalization and typed local refusals. Fresh
1,000-cycle ARC release, optimized result-access guards, nominal/compiler rejection,
selected consumer suites and inventory/formatting checks remain required.

Local evidence: checked optimized native `pvm_inner_transfer`,
`pvm_inner_transfer_dispatch`, `pvm_machine`, `pvm_inner_pages`,
`pvm_inner_dispatch` and `pvm_refinement_dispatch` pass, each with fresh
1,000-cycle unchanged ARC occupancy. Eleven optimized runtime guards, seven
exact compiler privacy/nominal rejections, verification inventory, nineteen
inventory/provenance Python tests and pinned formatting pass. These are local
macOS results; exact-head Linux CI remains independent.

Nested invoke remains gated. Next: invoke, then work-package report integration.
State composition/publication ownership is unchanged. M1 framing is complete;
full state serialization and complete refinement remain open.
