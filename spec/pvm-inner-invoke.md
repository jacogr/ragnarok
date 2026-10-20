# Bounded inner-machine invocation

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`pvm_invocations.tex` Omega_K and general gas rules, `definitions.tex` K gas
and invocation result codes, `pvm.tex` Psi. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: host 13 runs one raw inner Psi segment, without dispatching its host requests.
Registers 7/8 select machine and a writable natural 112-byte caller frame: fourteen
little-endian uint64 words containing unsigned gas followed by thirteen registers.
An inaccessible/read-only/overflowing frame supplies zero requested gas for charging,
then panics if the base cost is affordable. A writable frame reserves 968+requested
gas before identity lookup. Underfunding preserves frame/map/registers with exact
terminal debt; unrepresentable debt is a typed local LimitExceeded gate. WHO consumes
the full reservation and changes neither frame nor map. All arithmetic is checked
without overflowing the sum 968+requested.

A known affordable machine executes its original program, retained RAM, PC and
charged flag using frame gas/registers. Halt/Panic/Fault/Host/OOG return codes are
0/1/2/3/4. Only Host/Fault replace outer r8 with the host identifier/physical fault
address; all other exits retain the caller's frame pointer. Write back all fourteen
posterior words. Refund actual unspent inner credit, including block OOG's retained
positive credit. Guest-only execution cannot create host debt. Preserve the inner
engine's normalized PC, RAM and charged flag, except Host advances PC past the
causing ecalli. The caller can repair a fault or handle a host request before resuming.

Every map captures independent per-segment ExecutionStepLimit and GasCycleLimit
policies. The outer HostCallLimit bounds segment count, so callbacks cannot execute
unbounded work or recursively dispatch another invoke. These inner policies do not
replenish or replace the outer instruction/call budgets. Inner engine refusals retain
exact StepError through dispatch/normalized invocation as ExecutionFailure, with no
partial frame, map, output or export successor. Frame copies have the fixed protocol
112-byte bound, independent of variable transfer-copy policy.

Completion: real original guests for all five exits, exact frame encoding/high words,
reservation/refund/WHO/OOG and overflow edges, cross-page frames and permission
priority; host PC progression, page repair/retry without double charging, repeated
host segments, halt/panic PC normalization, immutable source/other-slot retention,
independent local engine policies and fresh 1,000-cycle ARC release. Real bound outer
guests must compose creation/invoke/output and preserve typed refusal normalization.
Strict result/reason access, compiler privacy/nominal guards and affected consumers
remain required. Pins, established specification gates and state ownership stay fixed.

Local evidence: checked optimized native `pvm_inner_invoke`,
`pvm_inner_invoke_dispatch`, `pvm_inner_lifecycle`, `pvm_inner_transfer_dispatch`,
`pvm_refinement_dispatch` and `pvm_refinement_outcome` pass, each with fresh
1,000-cycle unchanged ARC occupancy. Twenty-six optimized runtime guards, eight
exact compiler privacy/nominal rejections, verification inventory, nineteen
inventory/provenance Python tests and pinned formatting pass. These are local
macOS results; exact-head Linux CI remains independent.

Next: work-package report result integration. Complete refinement still requires
remaining bootstrap/authenticated-input gates and report policy. M1 framing is complete;
full state serialization and whole-block parity remain open.
