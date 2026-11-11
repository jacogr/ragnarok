# Accumulation bless host

## Scope and authority

Qualify bless (16), Omega_B, against the [owned-role amendment](https://github.com/gavofyork/graypaper/pull/558)
at `068d88c6` (merged after the repository's Gray Paper pin). Charge
`422 + 20*r12` before capture, including when r11 keeps the current allowance
dictionary. A full-width all-ones role register or input pointer keeps the
corresponding current value. An all-ones E4 assigner keeps that core's owner.
Other inputs use the existing E4 assigner array and E4-service/E8-gas pairs.

The current manager may replace all fields. Each current delegator, registrar
and assigner may transfer the role or core they hold. Any caller may submit an
unchanged proposal. Only the manager can change the allowance dictionary.
Unreadable supplied memory panics. Unauthorized proposals and repeated service
keys return HUH before a permitted out-of-domain role returns WHO. Unique keys
publish in numeric order. Identical repeated keys also return HUH.
The original duplicate-key fixtures remain under
`tests/fixtures/historical/bless-duplicate-keys/`.

Both block publication paths use the role owners from the start of the
parallel accumulation. A changed choice from the original manager wins for
that field. Otherwise the original holder's selected context supplies its
successor. Supervisor account authority does not grant privilege authority.
Staging and queue sources remain the original delegator and core assigners.

Completion witnesses cover role and pointer sentinels, owned and foreign role
proposals, dictionary equality and refusal, manager precedence, original queue
and staging producers, and checkpoint ownership.

## Ownership and bounded work

The protocol parameter core count must match the prepared privilege profile;
otherwise the host refuses locally rather than guessing a memory layout. Copy
policy applies independently to the positional assigner array and raw pair array.
PrivilegeConfig bounds raw record capture/sorting as well as encoded C(12) size,
including every duplicate pair before refusal. Gas uses the full raw
input count, before the uniqueness decision. Funded item cost proves the subsequent
12*n byte extent cannot wrap; successful memory preflight and explicit typed
allocation ceilings precede every native index conversion and allocation.

The effect API checks field ownership against the current snapshot before
narrowing guest role IDs. It owns canonical snapshot bytes and replaces serialized
C(12) on a fork with inherited store ceilings. Default/failed results expose no
map, privileges or partial execution. Subsequent yield/provide/storage operations
preserve accepted privileges; checkpoint and outcome normalization retain/select
the exact corresponding account/privilege version. No underlying guest memory,
initial roles, original map or caller-owned role arrays are mutated.

Authored fixture inputs now support a bounded writable payload and explicit initial
manager. Their raw-program ceiling includes the opcode mask/framing for code that
was already separately bounded below 128 bytes; production policy is unchanged.

## Historical old-pin verification (2026-10-19)

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

## Current qualification witnesses

Real guest calls cover identical and conflicting repeated keys, each also combined
with an invalid proposed role ID, proving HUH precedes WHO. Exact consumed gas
includes both raw pairs. Disabled hashing proves refusal leaves C12 and the full
original map unchanged. Direct state calls independently refuse both forms.
The native release workload includes duplicate capture/sort scratch each cycle.
Independent signed whole-map chains now require duplicate HUH to leave the free
allowance dictionary empty, preventing later empty-operand execution. Rotation
chains retain the same rule across validator population changes. Historical
source/vector evidence and the separate heap questions retain their original scope.

## November 11 campaign qualification

The [0.8.0 campaign](https://github.com/jam-conformance/jam-fuzzing/pull/212),
merged at `cddba17d`, includes post-0.8.0 heap charging and stack rounding,
conditional-move gas pricing and program limits, report limits and saturated
transfer credits. Its bless deviation removes the older blanket non-manager
refusal. The merged rule used here also specifies field ownership and sentinels.

- `1793732768_5752`, slot 36, is the bless witness. The Lasair report differs
  only in C(12). The expected delegator and registrar are both `0x55b364b8`.
  The reported result leaves both roles at service 0. The original signed block
  contains the 0.8.0 assurance anchor field, which the current wire schema omits.
  The local peer reproduced the supplied parent state root. Block decoding
  then refused the old assurance layout with `InvalidValidator` before
  accumulation. Local guest and publication tests cover the handoff.
- `1792928756_4797`, slot 1, is a report admission control. It contains no
  assurances and expects rejection without changing the state root. The
  old genesis header refused initialization with `HeaderFailure`. The exact
  child block and parent map decoded separately, and the native report policy
  returned `RefinementLoadExceeded` for 50,000,001 authorizer gas.

The local macOS build passed eight native suites covering bless, assign,
designate, complete batch publication, annulment and availability. Two
independent Python allowance checks also passed.

The current `gp-next` vector head is four commits ahead of the pinned
`a49f241a791f559d1502dc1b0b5328372995e375`. The range includes changes to the
assurance and preimage codecs and STF witnesses. The pinned corpus and protocol
sources retain their existing revisions during this scoped qualification.
