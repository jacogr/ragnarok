# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Export only the authenticated dependencies of metadata-selected code, deriving request length and time from one original qualified logical source.
import ../[code as logical_code, proof as logical_proof]
import ../../proof/query as proof_query
import ../../../state/current/logical as current_logical
import ../../../state/code_availability
import ../../../state/proof/plan as proof_plan
import ../../../codec/bounded
import ../../../codec/state/[layout as state_layout, requests as state_requests,
    service_values as state_service_values]
type
  LogicalCodeProofLimits* = object ## Complete availability auditing and the fixed selector's input/retained/sort storage have separate budgets.
    code*: CodeAvailabilityLimits
    keys*: ElementLimit
    bytes*: ByteLimit
  LogicalCodeProofInfo* = object ## Copied source-bound observations exclude root trust and complete-map authority.
    code*: ServiceCodeInfo
    slot*: RequestSlot
    keys*: int
  LogicalCodeProof* = object ## Original logical source and fixed semantic dependencies cannot be independently replaced.
    initialized: bool
    source: CurrentLogicalState
    keys: StateProofPlan
    info: LogicalCodeProofInfo
  LogicalCodeProofError* {.pure.} = enum ## Whole-source availability, absence of service and selector/query failures have independent contracts.
    Uninitialized, None, InvalidPlan, LimitExceeded, NoService, CodeFailure, PreimageKeyFailure,
      KeyFailure, PlanFailure, QueryFailure
  LogicalCodeProofResult*[T] = object ## No refused operation exposes an executable prefix or fabricated available code.
    case status: LogicalCodeProofError
    of None: completed: T
    of CodeFailure: codeReason: LogicalCodeResult
    of PreimageKeyFailure: preimageReason: ServiceValueError
    of KeyFailure: keyReason: RequestError
    of PlanFailure: planReason: ProofPlanError
    of QueryFailure: queryReason: LogicalProofResult
    else: discard # Defaults, invalid plans and local resource failures are payload-free.
func error*[T](outcome: LogicalCodeProofResult[T]): LogicalCodeProofError =
  ## Observe only the immutable selected stage.
  outcome.status
func value*[T](outcome: LogicalCodeProofResult[T]): T {.inline, requires: outcome.status ==
    LogicalCodeProofError.None.} =
  ## Extract a successful source-bound selector, observation or query only.
  outcome.completed
func codeFailure*[T](outcome: LogicalCodeProofResult[T]): LogicalCodeResult {.inline,
    requires: outcome.status == LogicalCodeProofError.CodeFailure.} =
  ## Preserve genuine original-source audit refusal without a default catalogue.
  outcome.codeReason
func preimageError*[T](outcome: LogicalCodeProofResult[T]): ServiceValueError {.inline,
    requires: outcome.status == LogicalCodeProofError.PreimageKeyFailure.} =
  ## Preserve actual preimage namespace derivation refusal separately from request-key failures.
  outcome.preimageReason
func requestError*[T](outcome: LogicalCodeProofResult[T]): RequestError {.inline,
    requires: outcome.status == LogicalCodeProofError.KeyFailure.} =
  ## Preserve mandatory actual-length request-key derivation refusal.
  outcome.keyReason
func planError*[T](outcome: LogicalCodeProofResult[T]): ProofPlanError {.inline,
    requires: outcome.status == LogicalCodeProofError.PlanFailure.} =
  ## Preserve the existing immutable selector capture's refusal.
  outcome.planReason
func queryFailure*[T](outcome: LogicalCodeProofResult[T]): LogicalProofResult {.inline,
    requires: outcome.status == LogicalCodeProofError.QueryFailure.} =
  ## Preserve independent selected-view and generic proof work refusal.
  outcome.queryReason
proc planLogicalCodeProof*(source: CurrentLogicalState, service: ServiceIndex,
    limits: LogicalCodeProofLimits): LogicalCodeProofResult[LogicalCodeProof] =
  ## Admit the maximum four-key selector before the complete availability audit copies or hashes content; no caller-selected hash, length or slot is accepted.
  if uint64(limits.keys) < 4 or uint64(limits.bytes) < 310:
    return LogicalCodeProofResult[LogicalCodeProof](
        status: LogicalCodeProofError.LimitExceeded) # Four input/output keys and two pinned merge-sort keys require 10*31 bytes even when the eventual absent branch uses fewer.
  let audited = auditLogicalCodeAvailability(source, limits.code)
  if audited.error != LogicalCodeError.None:
    return LogicalCodeProofResult[LogicalCodeProof](status: LogicalCodeProofError.CodeFailure,
        codeReason: audited)
  let table = audited.value.logicalCodeTable
  let found = table.findServiceCode(service)
  if found.error == CodeAvailabilityError.NoService:
    return LogicalCodeProofResult[LogicalCodeProof](
        status: LogicalCodeProofError.NoService) # Exhaustive original inventory membership is distinct from an existing service with absent code.
  let info = table.serviceCodeAt(found.value).value
  let hash = ServicePreimageHash(array[32, byte](info.hash))
  let preimage = servicePreimageKey(service, hash, ByteLimit(32))
  if preimage.error != ServiceValueError.None:
    return LogicalCodeProofResult[LogicalCodeProof](
        status: LogicalCodeProofError.PreimageKeyFailure, preimageReason: preimage.error)
  let count = if info.state == ServiceCodeState.Absent: 3 else: 4
  var keys = newSeq[StateKey](count) # Exact admitted capacity avoids transient sequence growth during selector preparation.
  keys[0] = chapterKey(StateChapter(11))
  keys[1] = chapterServiceKey(StateChapter(255), service)
  keys[2] = preimage.value
  if info.state != ServiceCodeState.Absent:
    if info.bytes >= uint64(high(uint32))-1:
      return LogicalCodeProofResult[LogicalCodeProof](
          status: LogicalCodeProofError.LimitExceeded) # Actual bounded namespace length must never be truncated or replaced by another request.
    let request = serviceRequestKey(service, hash, RequestLength(uint32(info.bytes)), ByteLimit(32))
    if request.error != RequestError.None:
      return LogicalCodeProofResult[LogicalCodeProof](status: LogicalCodeProofError.KeyFailure,
          keyReason: request.error)
    keys[3] = request.value # Only genuinely stored code supplies an actual-length request; absent content needs no invented length.
  let plan = captureStateProofPlan(keys, limits.keys)
  if plan.error != ProofPlanError.None:
    return LogicalCodeProofResult[LogicalCodeProof](status: LogicalCodeProofError.PlanFailure,
        planReason: plan.error)
  LogicalCodeProofResult[LogicalCodeProof](status: LogicalCodeProofError.None,
    completed: LogicalCodeProof(initialized: true, source: audited.value.logicalCodeSource,
      keys: plan.value,
      info: LogicalCodeProofInfo(code: info, slot: table.codeAvailabilityInfo.value.slot,
          keys: plan.value.len)))
proc logicalCodeProofInfo*(plan: LogicalCodeProof): LogicalCodeProofResult[LogicalCodeProofInfo] =
  ## Copy fixed semantic selector observations; code bytes remain in the original immutable owner.
  if not plan.initialized: return LogicalCodeProofResult[LogicalCodeProofInfo](
      status: LogicalCodeProofError.InvalidPlan)
  LogicalCodeProofResult[LogicalCodeProofInfo](status: LogicalCodeProofError.None,
      completed: plan.info)
proc logicalCodeProofSource*(plan: LogicalCodeProof): LogicalCodeProofResult[CurrentLogicalState] =
  ## Retain the original source for existing managed proof submission outside native graph leases.
  if not plan.initialized: return LogicalCodeProofResult[CurrentLogicalState](
      status: LogicalCodeProofError.InvalidPlan)
  LogicalCodeProofResult[CurrentLogicalState](status: LogicalCodeProofError.None,
      completed: plan.source)
proc logicalCodeProofKeys*(plan: LogicalCodeProof): LogicalCodeProofResult[StateProofPlan] =
  ## Retain only exact metadata/time/preimage/actual-length dependencies for independent planned response verification.
  if not plan.initialized: return LogicalCodeProofResult[StateProofPlan](
      status: LogicalCodeProofError.InvalidPlan)
  LogicalCodeProofResult[StateProofPlan](status: LogicalCodeProofError.None, completed: plan.keys)
proc captureLogicalCodeProofQuery*(plan: LogicalCodeProof,
    limits: LogicalProofLimits): LogicalCodeProofResult[ProofQuery] =
  ## Existing independent full-map/view/path/hash/wire policies apply without allowing a replacement source or selector.
  if not plan.initialized: return LogicalCodeProofResult[ProofQuery](
      status: LogicalCodeProofError.InvalidPlan)
  let query = captureLogicalProofQuery(plan.source, plan.keys, limits)
  if query.error != LogicalProofError.None:
    return LogicalCodeProofResult[ProofQuery](status: LogicalCodeProofError.QueryFailure,
        queryReason: query)
  LogicalCodeProofResult[ProofQuery](status: LogicalCodeProofError.None, completed: query.value)
