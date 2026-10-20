# Inner-machine page management

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`pvm_invocations.tex` Omega_Z and `definitions.tex` Z gas constants; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. No pin changes.

Scope: host 12 on the invocation-local immutable inner-machine map. Registers
7/8/9/10 select machine ID, starting page, count and mode. Charge 212+118*c for
mode 0, 275+121*c for modes 1/2, 130+29*c for modes 3/4, and 80 otherwise.
Affordable calls check WHO before malformed geometry/mode (HUH). Require p>=16
and p+c<2^20, including the strict exclusive endpoint in the pinned text; prove
bounds by subtraction before adding or narrowing. Empty ranges obey those same
geometry rules, but permission preservation is vacuously valid.

Mode 0 clears bytes and makes the interval inaccessible. Modes 1/2 clear bytes
and set read-only/read-write access. Modes 3/4 preserve all bytes and set read-only/
read-write access, refusing with HUH if any prior page is inaccessible. Only r7
changes on affordable protocol responses; parent memory, other machines, inner
program/PC/charged flag and the original map remain unchanged. Empty cleared
inaccessible pages are represented sparsely as absent, recovering local capacity.

A generic atomic memory page-range update preflights the complete retained-page
capacity before cloning any bytes. Local capacity refusal exposes neither host
response nor map successor. Unrepresentable natural gas costs/debts also refuse
locally as LimitExceeded: multiplication is checked before evaluation and a terminal
deficit must fit the engine's existing <=2^63 representation. No wrapping, clamping
or artificial HUH/WHO/OOG is used for this implementation gate. All representable
underfunded calls preserve exact debt and every pre-call owner/register.

Completion checks: literal gas costs and exact underfunding for all modes; WHO/HUH
priority; strict address endpoints, overflow/high bits and empty intervals; whole
range permission checks; clear/preserve/free semantics, capacity reuse, atomic
limits, copied/detached immutable snapshots and unaffected metadata/other slots.
Real bootstraps exercise creation/pages/deletion and normalized outcomes. Fresh
1,000-cycle ARC checks cover all mode successors and local refusals. Optimized
access guards, nominal/compiler checks and affected consumer suites remain required.

Local evidence: checked optimized native `pvm_inner_pages`,
`pvm_inner_page_dispatch`, `pvm_machine`, `pvm_inner_lifecycle`,
`pvm_inner_dispatch` and `pvm_refinement_dispatch` pass, each with fresh
1,000-cycle unchanged ARC occupancy. Nine optimized runtime refusal guards,
seven exact compiler privacy/nominal rejections, verification inventory,
nineteen inventory/provenance Python tests and pinned formatting pass.
These are local macOS results; exact-head Linux CI remains independent.

Peek/poke now follow [the transfer contract](pvm-inner-transfer.md). Invoke follows [the bounded invocation contract](pvm-inner-invoke.md). No report construction, state composition
or publication changes. Next: work-package report integration. M1 framing is complete; full state serialization and complete refinement
remain open.
