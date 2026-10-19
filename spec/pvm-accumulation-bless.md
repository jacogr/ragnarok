# Accumulation bless host

## Scope and authority

Implement bless (15), Omega_B, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex and
definitions.tex. Charge the full `422 + 20*r12` before all table mutations.
Read one E4 assigner per configured core from r8 and r12 raw E4-service/E8-gas
pairs from r11. Bad readable intervals panic before authorization. A non-manager
returns HUH; only then do out-of-domain full-width manager/delegator/registrar
registers (r7/r9/r10) return WHO. Successful calls replace those roles, assigners
and the complete always-accumulate set, returning OK.

Current privilege snapshots and serialized C(12) remain coherent with the current
complete account map. Each effect version owns both; checkpoint retains them,
while write/provide/yield preserve them. Never mutate initial provenance or publish
persistent block state. Local copy, item, codec/store and backend failures expose
no partial execution. Protocol cost retains all high bits and the existing signed
negative-gas representation gate.

Completion witnesses cover gas/overflow edges, memory/authorization/type ordering,
zero and multiple pairs, numeric sorting and exact-pair set deduplication, role
boundaries, repeated manager handoff, checkpoints, coherent state and prior owners,
resource/backend refusals, guarded APIs and ARC release.

## Explicit specification boundaries

The set comprehension removes identical service/gas pairs. Different gas values
for one service do not define a dictionary in the pinned row; preserve this case
as local AmbiguousPrivileges with a focused pending parity test, without choosing
first/last/max gas or a fabricated guest code. The chapter-12 codec still accepts
only strictly increasing unique numeric service keys.

Grow_heap (1) remains gated by the existing GP/vector gas and stack-rounding
questions in pvm-heap-memory.md. This tranche adopts neither vector deviation.
Other accumulation hosts and complete Psi_A/publication remain later work.

## Ownership and bounded work

The protocol parameter core count must match the prepared privilege profile;
otherwise the host refuses locally rather than guessing a memory layout. Copy
policy applies independently to the positional assigner array and raw pair array.
PrivilegeConfig bounds raw record capture/sorting as well as encoded C(12) size,
even if duplicate pairs would reduce the final dictionary. Gas uses the full raw
input count, not the deduplicated count. Funded item cost proves the subsequent
12*n byte extent cannot wrap; successful memory preflight and explicit typed
allocation ceilings precede every native index conversion and allocation.

The manager check is repeated at the state API boundary. It accepts only typed
role IDs, independently owns canonical snapshot bytes and replaces serialized
C(12) on a fork with inherited store ceilings. Default/failed results expose no
map, privileges or partial execution. Subsequent yield/provide/storage operations
preserve accepted privileges; checkpoint and outcome normalization retain/select
the exact corresponding account/privilege version. No underlying guest memory,
initial roles, original map or caller-owned role arrays are mutated.

Authored fixture inputs now support a bounded writable payload and explicit initial
manager. Their raw-program ceiling includes the opcode mask/framing for code that
was already separately bounded below 128 bytes; production policy is unchanged.

## Local verification (2026-10-19)

Nine affected native suites passed: bless, effects, write, info, provide, dispatch,
outcome, provision integration and machine initialization. Every suite retained
fresh 1,000-cycle ARC evidence with unchanged occupied memory. Bless witnesses
cover authority handoff and reauthorization, current/initial/exceptional versions,
input/type/gas precedence, canonical order/set deduplication, full-width IDs and
allowances, exact funding edges, cost above uint64 with borrowing, exact 2^63 debt
and representation refusal, API input independence, encoded component ceilings,
Merklization refusal, and privilege preservation through yield/storage writes.

All 111 production semantic checks, 24 runtime extraction probes, nine privacy
rejections and 42 selected discovery/failure/native-harness Python checks passed.
Three specification evidence tests passed; three parity tests remain explicitly
pending (the two existing heap questions and the conflicting-allowance question).
Pinned parser metadata confirms both new public routine docs are attached.
Inventory, pinned Nim/Rust formatting and whitespace checks passed.

Evidence remains under `build/pvm-bless/`: native.log, modules.log, guards.log,
targeted-results.json, api-docs.log, selected Python logs and format-check.log.
This is focused local macOS evidence, not complete verification or exact-head
Linux CI. Consumer runs reused one prepared library set with fresh per-suite
execution/output/ARC checks. The older helper's zero allowance capacity remains
the default; bless tests explicitly opt into positive capacity.
