# Selected-state proof queries

The [feature contract](../spec/application-state-proofs.md) records implemented scope and evidence.
This interface serves a bounded semantic proof plan from one exact retained complete-state block.
Public RPC proof methods, remote root discovery and partial light-state generation remain separate.

## Admission and ownership

Start a stable `Services` owner with complete canonical state. Build a semantic plan with the
constructors in `state/proof_service` and choose an explicit `BlockHash`. Supply every
`ProofQueryLimits` policy: full-map entries/nodes, individual proof nodes/value bytes, aggregate
proof counts/nodes/value bytes, retained-view counts/value bytes, encoded bytes and hash work.
These are resource ceilings; the hash-work estimate is not a wall-clock deadline.

Call `beginStateProof` on the serialized host, outside transport callbacks. The first request starts
one reusable native thread; later requests reuse its single slot. Unknown selections, invalid plans
and insufficient capture budgets return `QueryFailure` with a guarded `queryError`. Closed or
busy owners grant no ticket. Native refusal exposes only a guarded `workerError` and restores RPC.

All temporary canonical aliases must retire before submission. In particular, a helper that reads
`chainView` and then starts a worker while still retaining its local selected block violates the ARC
lease. Put selection in a separate activation that returns only the fixed hash:

```nim
import std/assertions
import src/app/[services, proof_query, proof_worker]
import src/chain/[genesis, provider]
import src/state/proof_service

proc selectedHeadHash(owner: Services): BlockHash =
  ## Every history/selected-state temporary retires before returning this fixed copied identity.
  let head = owner.chainView.bestBlock
  assert head.error == GenesisError.None
  head.value.blockHash

proc beginSelectedProof(owner: var Services, plan: ServiceProofPlan,
    limits: ProofQueryLimits): StateProofAdmission {.raises,
    requires: owner.stateProofAvailable.} =
  ## The caller explicitly chooses the current retained head through this helper.
  let selected = selectedHeadHash(owner)
  owner.beginStateProof(selected, plan, limits)
```

`beginStateProof` itself captures the selected snapshot and detaches the plan in a separate helper
activation before transferring its private query owner to the worker. Every external alias of the
canonical graph must stay alive and untouched until collection or joined stop. This includes ARC
copies, destruction and getters that create new aliases. Services enforces its own host boundary;
it cannot discover arbitrary aliases retained by callers. Keep the Services address fixed.

## Progress and retirement

After successful admission, save `admission.value` and use scalar `stateProofPhase` polling.
`Services.tick` continues independent UI work while RPC chain work is paused. Canonical getters,
reception, preparation, adoption and checkpoint preparation cannot touch the leased graph.
Prepared detached checkpoint I/O remains governed by its existing independent worker contract.
Other active preparation, disk publication/maintenance, pending adoption or a foreign RPC pause
prevents proof admission. The lease remains exclusive even after the worker reaches `Done`.

`cancelStateProof(ticket)` requests logical discard. It does not preempt running crypto/FFI work,
release capacity or reopen RPC. Collect only with the matching ticket after `Done`:

- `Uninitialized` completion means early, stale, foreign or otherwise unavailable collection;
  it leaves the lease untouched.
- `Cancelled` retires the request without a response.
- `Completed` exposes a guarded `ProofQueryResult[ProofResponse]`. Inspect its error before
  reading the response or nested proof/service failure reason. Execution failures expose no prefix.

Only successful collection reopens canonical/RPC access. `stopStateProofs` joins before discarding
uncollected work and resumes only its own lease. Stopping preparation cannot release a proof lease.
Call `Services.close` outside transport callbacks before destroying or relocating the aggregate,
including after a refused request that may have started its idle worker. Close joins proofs before
canonical/RPC owners retire. Active worker copies, relocation and unjoined destruction are rejected.

## Response and trust

A successful response owns detached encoded bytes plus fixed block identity and posterior root.
It retains no selected snapshot or raw proof graph. `response.bytes(limit)` checks an explicit copy
budget before returning an independent sequence. The response remains usable after Services closes.

Response identities describe what was generated; consumers still supply their own expected root,
plan and receive budgets to `decodeServiceProofs`. Never infer root authority from response bytes.
Generation, local authentication and encoding are all-or-neither under the admitted limits.

## Verification and remaining scope

`make check-models` runs focused lifecycle models, intentional guard-removal mutants and
reachability witnesses in sequential and four-worker modes. CI has an independent **Model
verification** job with its own summary and replayable diagnostic artifacts; see
[model verification](../spec/model-checking.md).

Native suites cover real signed-state capture/execution, Services exclusion, cancellation, reuse
and joined shutdown. Strict runtime probes check canonical/result access and live-owner lifetimes;
compiler probes check private authority/backing storage and actual composite ownership lowering.
Existing preparation tests exercise enabled RPC/UI behavior through the shared dispatcher lease.
These checks are bounded local evidence, not complete JAM or unbounded concurrency verification.

M1 framing and the pinned current request namespace are implemented. Full state serialization/STF
parity remains open. Public RPC binding belongs to the RPC integration work; this increment adds
internal host interfaces without changing storage APIs, protocol pins or the production compiler.
