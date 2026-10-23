# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Root-free immutable global/service query identities, with bounded capture and exact union.
## A plan requests evidence; it is neither verified partial state nor a complete-map snapshot.
import std/[algorithm, assertions]
import ../codec/[bounded, state_layout]

type
  ProofPlanError* {.pure.} = enum ## Defaults, malformed selectors and exhausted budgets grant no plan authority.
    Uninitialized, None, InvalidInput, InvalidIndex, LimitExceeded
  ProofPlanResult*[T] = object ## Only successful plan construction or selection exposes a payload.
    case status: ProofPlanError
    of None: completed: T
    else: discard              # Failure reasons carry no requested-key owner.
  PlanData = ref object ## Root-independent query identities share an immutable acyclic owner.
    keys: seq[StateKey]
  StateProofPlan* = object ## A query plan requests evidence; it never grants verified state or root authority.
    data: nil PlanData

func error*[T](outcome: ProofPlanResult[T]): ProofPlanError =
  ## Observe construction/selection refusal without extracting a default payload.
  outcome.status
func value*[T](outcome: ProofPlanResult[T]): T {.inline,
    requires: outcome.status == ProofPlanError.None.} =
  ## Select only complete immutable plans or copied fixed keys.
  outcome.completed

func valid*(plan: StateProofPlan): bool =
  ## Defaults cannot silently request an empty successful read.
  plan.data != nil
func len*(plan: StateProofPlan): int =
  ## Inspect the exact retained query count without allocating key copies.
  let data = plan.data
  if data == nil: 0 else: data.keys.len
proc keyAt*(plan: StateProofPlan, index: int): ProofPlanResult[StateKey] =
  ## Bind ordinal extraction to this immutable owner and reject negative/out-of-range positions.
  let data = plan.data
  if data == nil:
    return ProofPlanResult[StateKey](status: ProofPlanError.Uninitialized)
  if index < 0 or index >= data.keys.len:
    return ProofPlanResult[StateKey](status: ProofPlanError.InvalidIndex)
  ProofPlanResult[StateKey](status: ProofPlanError.None, completed: data.keys[index])
func comparePlanKey(left, right: StateKey): int =
  ## Canonical byte order matches partial-view enumeration independently of semantic selectors.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for i in 0..<31:
    # Stop at the first unequal key byte; identical keys coalesce only in explicit plan union.
    if a[i] < b[i]: return -1
    if a[i] > b[i]: return 1
  0
proc captureStateProofPlan*(keys: openArray[StateKey], limit: ElementLimit): ProofPlanResult[
    StateProofPlan] =
  ## Bound native extents before allocation, copy and sort all selectors, then reject duplicate identities.
  if uint64(keys.len) > uint64(limit) or keys.len > high(int) div sizeof(StateKey):
    return ProofPlanResult[StateProofPlan](status: ProofPlanError.LimitExceeded)
  var copied = newSeq[StateKey](keys.len)
  for i, key in keys:
    # Retain independent fixed bytes before sorting; caller mutation cannot change the plan.
    copied[i] = key
  copied.sort(comparePlanKey)
  for i in 1..<copied.len:
    # Exact duplicates are malformed; only explicit union coalesces requested identities.
    if comparePlanKey(copied[i-1], copied[i]) == 0:
      return ProofPlanResult[StateProofPlan](status: ProofPlanError.InvalidInput)
  ProofPlanResult[StateProofPlan](status: ProofPlanError.None,
    completed: StateProofPlan(data: PlanData(keys: copied)))
iterator items*(plan: StateProofPlan): StateKey =
  ## Yield copied fixed identities in canonical byte order, retaining the immutable owner for iteration.
  let data = plan.data
  if data != nil:
    for i in 0..<data.keys.len:
      yield data.keys[i] # No mutable backing storage or root claim escapes.

proc mergeStateProofPlans*(left, right: StateProofPlan,
    limit: ElementLimit): ProofPlanResult[StateProofPlan] =
  ## Union sorted requested identities, counting exact unique output before allocation; no hashing occurs.
  let a = left.data
  let b = right.data
  if a == nil:
    return ProofPlanResult[StateProofPlan](status: ProofPlanError.Uninitialized)
  if b == nil:
    return ProofPlanResult[StateProofPlan](status: ProofPlanError.Uninitialized)
  var i = 0
  var j = 0
  var count = 0
  while i < a.keys.len or j < b.keys.len:
    # Coalesce only equal key identities; query plans contain no values or conflicting root claims.
    if uint64(count) >= uint64(limit) or count >= high(int) div sizeof(StateKey):
      return ProofPlanResult[StateProofPlan](status: ProofPlanError.LimitExceeded)
    let order = if i == a.keys.len: 1
      elif j == b.keys.len: -1
      else: comparePlanKey(a.keys[i], b.keys[j])
    if order <= 0: inc i
    if order >= 0: inc j
    inc count
  var keys = newSeq[StateKey](count)
  i = 0
  j = 0
  for at in 0..<count:
    # Revisit immutable inputs only after exact count/native allocation extents have been established.
    let order = if i == a.keys.len: 1
      elif j == b.keys.len: -1
      else: comparePlanKey(a.keys[i], b.keys[j])
    keys[at] = if order <= 0: a.keys[i] else: b.keys[j]
    if order <= 0: inc i
    if order >= 0: inc j
  ProofPlanResult[StateProofPlan](status: ProofPlanError.None,
    completed: StateProofPlan(data: PlanData(keys: keys)))

