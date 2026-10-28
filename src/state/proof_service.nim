# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Typed service reads consume authenticated partial evidence without claiming a complete account map.
## Missing witnesses, proven absence and malformed present bytes remain separate outcomes.
import ./proof_plan as state_proof_plan
import ./preimage_history as state_preimage_history
import ./proof_view as state_proof_view
import ./trie_proof as state_trie_proof
import ../crypto/primitives as crypto_primitives
import ../codec/bounded as codec_bounded
import ../codec/state_accounts as codec_state_accounts
import ../codec/state_layout as codec_state_layout
import ../codec/state_service_values as codec_state_service_values
import ../codec/state_requests as codec_state_requests
import ../codec/state_trie as codec_state_trie

type
  ServiceProofError* {.pure.} = enum ## Failed/default reads expose only a reason, never a fabricated value.
    Uninitialized, None, MissingWitness, AbsentValue, InvalidValue, LimitExceeded,
    BackendFailure, InvalidInput, InvalidIndex, ProofFailure
  ServiceProofResult*[T] = object ## Success alone grants access to a complete typed read.
    case status: ServiceProofError
    of None:
      completed: T
    of ProofFailure:
      proofReason: StateProofError
    else:
      discard                     # Refused reads retain no successful prefix or default account.

func error*[T](outcome: ServiceProofResult[T]): ServiceProofError =
  ## Inspect a reason without authorizing payload access.
  outcome.status
func value*[T](outcome: ServiceProofResult[T]): T {.inline,
    requires: outcome.status == ServiceProofError.None.} =
  ## Extract only explicitly successful typed reads in checked optimized builds.
  outcome.completed
func viewReason(reason: ProofViewError): ServiceProofError =
  ## Exact lookup has no malformed-value interpretation; preserve absent evidence separately.
  case reason
  of ProofViewError.MissingWitness: ServiceProofError.MissingWitness # Unknown never means absent.
  else: ServiceProofError.Uninitialized # Default views cannot authorize any query.

proc readProofAccount*(view: ProofView, service: ServiceIndex): ServiceProofResult[
    ServiceMetadata] =
  ## Decode exact current C(255, service), without claiming validity of its unqueried nested maps.
  let found = view.lookup(chapterServiceKey(StateChapter(255), service))
  if found.error != ProofViewError.None:
    return ServiceProofResult[ServiceMetadata](status: viewReason(found.error))
  if not found.value.present:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.AbsentValue)
  if found.value.byteLength != ServiceMetadataBytes:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.InvalidValue)
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.InvalidValue)
  if decoded.value.consumed != ServiceMetadataBytes:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.InvalidValue)
  ServiceProofResult[ServiceMetadata](status: ServiceProofError.None,
      completed: decoded.value.metadata)

proc presentRead(view: ProofView, key: StateKey, limit: ByteLimit): ServiceProofResult[
    VerifiedStateLookup] =
  ## Inspect immutable authenticated extents before any caller-controlled value copy.
  let found = view.lookup(key)
  if found.error != ProofViewError.None:
    return ServiceProofResult[VerifiedStateLookup](status: viewReason(found.error))
  if not found.value.present:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.AbsentValue)
  if uint64(found.value.byteLength) > uint64(limit):
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.LimitExceeded)
  ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.None, completed: found.value)

proc readProofStorage*(view: ProofView, service: ServiceIndex, key: openArray[byte],
    limits: ServiceEntryLimits): ServiceProofResult[VerifiedStateLookup] =
  ## Require the same view's canonical account before resolving its bounded raw storage namespace.
  if uint64(key.len) > uint64(limits.keyBytes):
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.LimitExceeded)
  let account = view.readProofAccount(service)
  if account.error != ServiceProofError.None:
    return ServiceProofResult[VerifiedStateLookup](status: account.error)
  let derived = serviceStorageKey(service, key, limits.keyBytes)
  if derived.error != ServiceValueError.None:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.BackendFailure)
  presentRead(view, derived.value, limits.valueBytes)

proc readProofPreimage*(view: ProofView, service: ServiceIndex, hash: ServicePreimageHash,
    limit: ByteLimit): ServiceProofResult[VerifiedStateLookup] =
  ## Authenticate the same-root account and bounded preimage, then verify its actual content digest.
  let account = view.readProofAccount(service)
  if account.error != ServiceProofError.None:
    return ServiceProofResult[VerifiedStateLookup](status: account.error)
  let derived = servicePreimageKey(service, hash, ByteLimit(32))
  if derived.error != ServiceValueError.None:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.BackendFailure)
  let found = presentRead(view, derived.value, limit)
  if found.error != ServiceProofError.None:
    return found
  let digest = blake2b256(found.value.bytes)
  if digest.error != CryptoError.None:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.BackendFailure)
  if array[32, byte](digest.value) != array[32, byte](hash):
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.InvalidValue)
  found

proc readProofRequest*(view: ProofView, service: ServiceIndex, hash: ServicePreimageHash,
    length: RequestLength): ServiceProofResult[RequestHistory] =
  ## Refuse reserved lengths before account access or hashing, then decode an exact canonical history.
  if uint32(length) >= high(uint32)-1:
    return ServiceProofResult[RequestHistory](status: ServiceProofError.InvalidInput)
  let account = view.readProofAccount(service)
  if account.error != ServiceProofError.None:
    return ServiceProofResult[RequestHistory](status: account.error)
  let derived = serviceRequestKey(service, hash, length, ByteLimit(32))
  if derived.error != RequestError.None:
    return ServiceProofResult[RequestHistory](status: ServiceProofError.BackendFailure)
  let found = presentRead(view, derived.value, ByteLimit(13))
  if found.error == ServiceProofError.LimitExceeded:
    return ServiceProofResult[RequestHistory](status: ServiceProofError.InvalidValue)
  if found.error != ServiceProofError.None:
    return ServiceProofResult[RequestHistory](status: found.error)
  let decoded = decodeRequestHistory(found.value.bytes,
    RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13)))
  if decoded.error != RequestError.None:
    return ServiceProofResult[RequestHistory](status: ServiceProofError.InvalidValue)
  if decoded.value.consumed != found.value.byteLength:
    return ServiceProofResult[RequestHistory](status: ServiceProofError.InvalidValue)
  ServiceProofResult[RequestHistory](status: ServiceProofError.None,
      completed: decoded.value.history)

proc proofPreimageRequested*(view: ProofView, service: ServiceIndex, hash: ServicePreimageHash,
    length: RequestLength): ServiceProofResult[bool] =
  ## Proven absent accounts/requests are false; unknown witnesses and malformed state cannot decide solicitation.
  let history = view.readProofRequest(service, hash, length)
  if history.error == ServiceProofError.AbsentValue:
    return ServiceProofResult[bool](status: ServiceProofError.None, completed: false)
  if history.error != ServiceProofError.None:
    return ServiceProofResult[bool](status: history.error)
  ServiceProofResult[bool](status: ServiceProofError.None,
    completed: history.value.state == RequestState.Requested)

proc readProofHistoricalPreimage*(view: ProofView, service: ServiceIndex,
    hash: ServicePreimageHash, slot: RequestSlot, limit: ByteLimit): ServiceProofResult[
        VerifiedStateLookup] =
  ## Compose account, content and actual-length history facts from one immutable root at an explicit time.
  let preimage = view.readProofPreimage(service, hash, limit)
  if preimage.error != ServiceProofError.None:
    return preimage
  let size = uint64(preimage.value.byteLength)
  if size >= uint64(high(uint32))-1:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.InvalidValue)
  let history = view.readProofRequest(service, hash, RequestLength(uint32(size)))
  if history.error == ServiceProofError.AbsentValue:
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.InvalidValue)
  if history.error != ServiceProofError.None:
    return ServiceProofResult[VerifiedStateLookup](status: history.error)
  if not requestAvailableAt(history.value, slot):
    return ServiceProofResult[VerifiedStateLookup](status: ServiceProofError.AbsentValue)
  preimage

proc readProofCode*(view: ProofView, service: ServiceIndex, slot: RequestSlot,
    limit: ByteLimit): ServiceProofResult[VerifiedStateLookup] =
  ## Resolve current account code identity internally, then require its authenticated historical preimage.
  let account = view.readProofAccount(service)
  if account.error != ServiceProofError.None:
    return ServiceProofResult[VerifiedStateLookup](status: account.error)
  let hash = ServicePreimageHash(array[32, byte](account.value.codeHash))
  view.readProofHistoricalPreimage(service, hash, slot, limit)

type ServiceProofPlan* = object ## Existing semantic selectors wrap the common immutable requested-key owner.
  plan: StateProofPlan

func planReason(reason: ProofPlanError): ServiceProofError =
  ## Keep every existing service-plan refusal spelling while sharing bounded query mechanics.
  case reason
  of ProofPlanError.None: ServiceProofError.None
  of ProofPlanError.Uninitialized: ServiceProofError.Uninitialized
  of ProofPlanError.InvalidInput: ServiceProofError.InvalidInput
  of ProofPlanError.InvalidIndex: ServiceProofError.InvalidIndex
  of ProofPlanError.LimitExceeded: ServiceProofError.LimitExceeded

func toStateProofPlan*(plan: ServiceProofPlan): StateProofPlan =
  ## Expose only immutable root-free requested identities; a default semantic plan stays invalid.
  plan.plan
func valid*(plan: ServiceProofPlan): bool =
  ## Defaults cannot silently request an empty successful read.
  plan.plan.valid
func len*(plan: ServiceProofPlan): int =
  ## The retained query count is scalar-only and never copies canonical state.
  plan.plan.len
proc keyAt*(plan: ServiceProofPlan, index: int): ServiceProofResult[StateKey] =
  ## Preserve typed service ordinal errors while returning fixed copied key bytes.
  let selected = plan.plan.keyAt(index)
  if selected.error != ProofPlanError.None:
    return ServiceProofResult[StateKey](status: planReason(selected.error))
  ServiceProofResult[StateKey](status: ServiceProofError.None, completed: selected.value)
func comparePlanKey(left, right: StateKey): int =
  ## Canonical byte order matches partial-view enumeration independently of semantic selectors.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for i in 0..<31:
    # Stop at the first unequal key byte; identical keys coalesce only in explicit plan union.
    if a[i] < b[i]: return -1
    if a[i] > b[i]: return 1
  0
proc capturePlan(keys: openArray[StateKey], limit: ElementLimit): ServiceProofResult[
    ServiceProofPlan] =
  ## Semantic constructors share generic count, allocation, canonical-order and duplicate checks.
  let captured = captureStateProofPlan(keys, limit)
  if captured.error != ProofPlanError.None:
    return ServiceProofResult[ServiceProofPlan](status: planReason(captured.error))
  ServiceProofResult[ServiceProofPlan](status: ServiceProofError.None,
    completed: ServiceProofPlan(plan: captured.value))

proc planProofAccount*(service: ServiceIndex, limit: ElementLimit): ServiceProofResult[
    ServiceProofPlan] =
  ## Request only exact account metadata; no nested-map completeness is implied.
  capturePlan([chapterServiceKey(StateChapter(255), service)], limit)

proc planProofStorage*(service: ServiceIndex, key: openArray[byte], keyBytes: ByteLimit,
    limit: ElementLimit): ServiceProofResult[ServiceProofPlan] =
  ## Request account and exact selector dependencies; limits precede hashing and plan allocation.
  if uint64(limit) < 2 or uint64(key.len) > uint64(keyBytes):
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.LimitExceeded)
  let derived = serviceStorageKey(service, key, keyBytes)
  if derived.error != ServiceValueError.None:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.BackendFailure)
  capturePlan([chapterServiceKey(StateChapter(255), service), derived.value], limit)

proc planProofPreimage*(service: ServiceIndex, hash: ServicePreimageHash,
    limit: ElementLimit): ServiceProofResult[ServiceProofPlan] =
  ## Request account and exact selector dependencies; limits precede hashing and plan allocation.
  if uint64(limit) < 2:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.LimitExceeded)
  let derived = servicePreimageKey(service, hash, ByteLimit(32))
  if derived.error != ServiceValueError.None:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.BackendFailure)
  capturePlan([chapterServiceKey(StateChapter(255), service), derived.value], limit)

proc planProofRequest*(service: ServiceIndex, hash: ServicePreimageHash, length: RequestLength,
    limit: ElementLimit): ServiceProofResult[ServiceProofPlan] =
  ## Request account and exact selector dependencies; limits precede hashing and plan allocation.
  if uint32(length) >= high(uint32)-1:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.InvalidInput)
  if uint64(limit) < 2:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.LimitExceeded)
  let derived = serviceRequestKey(service, hash, length, ByteLimit(32))
  if derived.error != RequestError.None:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.BackendFailure)
  capturePlan([chapterServiceKey(StateChapter(255), service), derived.value], limit)

proc planProofHistorical*(service: ServiceIndex, hash: ServicePreimageHash, length: RequestLength,
    limit: ElementLimit): ServiceProofResult[ServiceProofPlan] =
  ## Request account and exact selector dependencies; limits precede hashing and plan allocation.
  if uint32(length) >= high(uint32)-1:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.InvalidInput)
  if uint64(limit) < 3:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.LimitExceeded)
  let blob = servicePreimageKey(service, hash, ByteLimit(32))
  if blob.error != ServiceValueError.None:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.BackendFailure)
  let derived = serviceRequestKey(service, hash, length, ByteLimit(32))
  if derived.error != RequestError.None:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.BackendFailure)
  capturePlan([chapterServiceKey(StateChapter(255), service), blob.value, derived.value], limit)

proc planProofCode*(view: ProofView, service: ServiceIndex, length: RequestLength,
    limit: ElementLimit): ServiceProofResult[ServiceProofPlan] =
  ## Learn code identity from authenticated metadata; the resulting root-free query plan grants no authority.
  if uint32(length) >= high(uint32)-1:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.InvalidInput)
  if uint64(limit) < 3:
    return ServiceProofResult[ServiceProofPlan](status: ServiceProofError.LimitExceeded)
  let account = view.readProofAccount(service)
  if account.error != ServiceProofError.None:
    return ServiceProofResult[ServiceProofPlan](status: account.error)
  planProofHistorical(service, ServicePreimageHash(array[32, byte](account.value.codeHash)), length, limit)

proc mergeProofPlans*(left, right: ServiceProofPlan,
    limit: ElementLimit): ServiceProofResult[ServiceProofPlan] =
  ## Preserve exact service union semantics while delegating both bounded passes to one owner implementation.
  let merged = mergeStateProofPlans(left.plan, right.plan, limit)
  if merged.error != ProofPlanError.None:
    return ServiceProofResult[ServiceProofPlan](status: planReason(merged.error))
  ServiceProofResult[ServiceProofPlan](status: ServiceProofError.None,
    completed: ServiceProofPlan(plan: merged.value))

func proofError*[T](outcome: ServiceProofResult[T]): StateProofError {.inline,
    requires: outcome.status == ServiceProofError.ProofFailure.} =
  ## Preserve precise authentication/backend failure reasons without granting a typed read payload.
  outcome.proofReason

proc matchesProofPlan*(view: ProofView, plan: ServiceProofPlan): ServiceProofResult[bool] =
  ## Compare exact sorted key sets; a superset or missing requested fact cannot substitute for this response.
  if not plan.valid or not view.valid:
    return ServiceProofResult[bool](status: ServiceProofError.Uninitialized)
  if plan.len != view.len:
    return ServiceProofResult[bool](status: ServiceProofError.None, completed: false)
  for i in 0..<plan.len:
    # Immutable view enumeration is canonical and retains both positive and negative facts.
    if comparePlanKey(plan.keyAt(i).value, view.lookupAt(i).value.key) != 0:
      return ServiceProofResult[bool](status: ServiceProofError.None, completed: false)
  ServiceProofResult[bool](status: ServiceProofError.None, completed: true)

proc verifyServiceProofs*(plan: ServiceProofPlan, queries: openArray[StateProofQuery],
    expectedRoot: StateRoot, limits: StateProofLimits, aggregate: StateProofBatchLimits,
    viewLimits: ProofViewLimits): ServiceProofResult[ProofView] =
  ## Authenticate exactly this semantic plan under caller-selected root authority, all or neither.
  if not plan.valid:
    return ServiceProofResult[ProofView](status: ServiceProofError.Uninitialized)
  if queries.len != plan.len:
    return ServiceProofResult[ProofView](status: ServiceProofError.InvalidInput)
  for i in 0..<plan.len:
    # Refuse omitted, substituted, duplicated or reordered selectors before any crypto work.
    if comparePlanKey(plan.keyAt(i).value, queries[i].key) != 0:
      return ServiceProofResult[ProofView](status: ServiceProofError.InvalidInput)
  let effective = StateProofBatchLimits(
    items: ElementLimit(min(uint64(aggregate.items), uint64(viewLimits.items))),
    nodes: aggregate.nodes,
    valueBytes: ByteLimit(min(uint64(aggregate.valueBytes), uint64(viewLimits.valueBytes))))
  let verified = verifyStateProofs(queries, expectedRoot, limits, effective)
  if verified.error != StateProofError.None:
    return ServiceProofResult[ProofView](status: ServiceProofError.ProofFailure,
      proofReason: verified.error)
  let captured = captureProofView(verified.value, expectedRoot, viewLimits)
  if captured.error == ProofViewError.LimitExceeded:
    return ServiceProofResult[ProofView](status: ServiceProofError.LimitExceeded)
  if captured.error != ProofViewError.None:
    return ServiceProofResult[ProofView](status: ServiceProofError.InvalidValue)
  ServiceProofResult[ProofView](status: ServiceProofError.None, completed: captured.value)

proc viewFailure[T](outcome: ProofViewResult[T]): ServiceProofResult[T] =
  ## Preserve proof authentication details; local framing errors remain malformed values, not absent state.
  case outcome.error
  of ProofViewError.ProofFailure:
    ServiceProofResult[T](status: ServiceProofError.ProofFailure, proofReason: outcome.proofError)
  of ProofViewError.LimitExceeded, ProofViewError.LengthOverflow:
    ServiceProofResult[T](status: ServiceProofError.LimitExceeded)
  of ProofViewError.Uninitialized:
    ServiceProofResult[T](status: ServiceProofError.Uninitialized)
  else:
    ServiceProofResult[T](status: ServiceProofError.InvalidValue)

proc encodeServiceProofs*(view: ProofView, plan: ServiceProofPlan, viewLimits: ProofViewLimits,
    perProof: StateProofLimits, wireBytes: ByteLimit): ServiceProofResult[seq[byte]] =
  ## Encode existing RPV1 only for the exact requested key set; no new root authority is embedded.
  let matched = matchesProofPlan(view, plan)
  if matched.error != ServiceProofError.None:
    return ServiceProofResult[seq[byte]](status: matched.error)
  if not matched.value:
    return ServiceProofResult[seq[byte]](status: ServiceProofError.InvalidInput)
  let encoded = encodeProofView(view, viewLimits, perProof, wireBytes)
  if encoded.error != ProofViewError.None:
    return viewFailure(encoded)
  ServiceProofResult[seq[byte]](status: ServiceProofError.None, completed: encoded.value)

proc decodeServiceProofs*(input: openArray[byte], plan: ServiceProofPlan,
    expectedRoot: StateRoot, viewLimits: ProofViewLimits, perProof: StateProofLimits,
    aggregate: StateProofBatchLimits, wireBytes: ByteLimit): ServiceProofResult[ProofView] =
  ## Decode existing canonical RPV1, reverify its witnesses under explicit root authority and match the plan.
  if not plan.valid:
    return ServiceProofResult[ProofView](status: ServiceProofError.Uninitialized)
  if input.len >= 8:
    # Declared count cannot grow the requested work or conceal an omitted response before decoding.
    var count = 0'u64
    for i in 0..<4: count = count or (uint64(input[4+i]) shl (8*i))
    if count != uint64(plan.len):
      return ServiceProofResult[ProofView](status: ServiceProofError.InvalidInput)
  let effective = StateProofBatchLimits(
    items: ElementLimit(min(uint64(aggregate.items), uint64(viewLimits.items))),
    nodes: aggregate.nodes,
    valueBytes: ByteLimit(min(uint64(aggregate.valueBytes), uint64(viewLimits.valueBytes))))
  let decoded = decodeProofView(input, expectedRoot, viewLimits, perProof, effective, wireBytes)
  if decoded.error != ProofViewError.None:
    return viewFailure(decoded)
  if not matchesProofPlan(decoded.value, plan).value:
    return ServiceProofResult[ProofView](status: ServiceProofError.InvalidInput)
  ServiceProofResult[ProofView](status: ServiceProofError.None, completed: decoded.value)
