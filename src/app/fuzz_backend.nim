# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fuzzer-owned ephemeral complete maps feed the ordinary current candidate pipeline without production bootstrap trust.
import std/assertions
import ./chain as app_chain
import ./candidate as app_candidate
import ../chain/genesis as chain_genesis
import ../chain/parameters as chain_parameters
import ../chain/provider as chain_provider
import ../codec/bounded as codec_bounded
import ../codec/header as codec_header
import ../codec/block_codec as codec_block_codec
import ../crypto/primitives as crypto_primitives
import ../state/fuzz_ancestry as state_fuzz_ancestry
import ../state/fuzz_protocol as state_fuzz_protocol
import ../state/store as state_store
import ../state/accumulation_current_update as state_accumulation_current_update
import ../state/report_anchors as state_report_anchors

type
  FuzzBackendConfig* = object ## Parameters and every execution/codec ceiling are explicit trusted host configuration.
    parameters*: Parameters
    candidate*: CurrentCandidateLimits
    wire*: FuzzLimits
    initialAncestry*: bool ## Negotiated feature1 permits explicit initial hash/slot membership.
    forkStates*: ElementLimit ## Zero selects linear execution; 1..64 bounds the current sibling GetState window.
  FuzzBackendError* {.pure.} = enum ## Local refusals expose no reply and are never implicitly translated to consensus Error.
    Uninitialized, None, InvalidConfiguration, InvalidRequest, AlreadyInitialized,
    MissingSeed, UnsupportedFeature, HashFailure, SeedContextFailure, UnknownState,
    CandidateFailure, StateChanged, ReplyFailure, LimitExceeded, UnknownParent, AncestryFailure
  FuzzBackendResult*[T] = object ## Success owns one complete value; candidate refusal preserves only its actual failed stage.
    case status: FuzzBackendError
    of None: completed: T
    of CandidateFailure: candidateReason: CurrentCandidateResult
    of AncestryFailure: ancestryReason: FuzzAncestryError
    else: discard # No other refusal grants a prepared prefix, selected chain or response.
  ForkState = object ## A retained sibling owns its exact header identity and independent complete map.
    hash: BlockHash
    state: StateStoreSnapshot
  FuzzBackend* = object ## Copies form independent ephemeral branches sharing only immutable prior snapshots.
    configured, seeded, executing: bool
    config: FuzzBackendConfig
    seedHeader: OwnedHeader
    seedHash: BlockHash
    seedState: StateStoreSnapshot
    chain: ApplicationChain
    ancestry: FuzzAncestry
    hasForkParent: bool
    forkParent: ApplicationChain
    forkAncestry: FuzzAncestry
    siblings: seq[ForkState]
func error*[T](outcome: FuzzBackendResult[T]): FuzzBackendError =
  ## Inspect the immutable selected stage.
  outcome.status
func value*[T](outcome: FuzzBackendResult[T]): T {.inline,
    requires: outcome.status == FuzzBackendError.None.} =
  ## Extract only a completed backend value.
  outcome.completed
func candidateFailure*[T](outcome: FuzzBackendResult[T]): CurrentCandidateResult {.inline,
    requires: outcome.status == FuzzBackendError.CandidateFailure.} =
  ## Preserve the actual failure for conservative consensus-versus-internal classification.
  outcome.candidateReason
func ancestryFailure*[T](outcome: FuzzBackendResult[T]): FuzzAncestryError {.inline,
    requires: outcome.status == FuzzBackendError.AncestryFailure.} =
  ## Report missing/invalid local context without converting it into a consensus rejection.
  outcome.ancestryReason
func ancestryLimits(config: FuzzBackendConfig): FuzzAncestryLimits =
  ## Share the exact configured report-context profile and retention budget.
  let policy = config.candidate.reporting.reports.ancestors
  FuzzAncestryLimits(header: policy.header, records: policy.headers, bytes: policy.maxBytes)
func refused[T](reason: FuzzBackendError): FuzzBackendResult[T] =
  ## Failed/default operations retain no successful reply or chain prefix.
  FuzzBackendResult[T](status: reason)
proc initFuzzBackend*(config: FuzzBackendConfig): FuzzBackendResult[FuzzBackend] =
  ## Select explicit profile agreement before admitting any supplied seed.
  let frame = config.wire.frame
  let admission = config.candidate.reporting.admission.frame
  if uint64(config.forkStates) > 64 or not config.parameters.valid:
    return refused[FuzzBackend](FuzzBackendError.InvalidConfiguration)
  let parameterCores = config.parameters.get(coreCount)
  let parameterEpoch = config.parameters.get(epochPeriod)
  if uint64(frame.cores) != parameterCores or uint64(frame.epochSlots) != parameterEpoch:
    return refused[FuzzBackend](FuzzBackendError.InvalidConfiguration)
  let sameCores = uint64(frame.cores) == uint64(admission.cores)
  let sameValidators = uint64(frame.validators) == uint64(admission.validators)
  let sameEpoch = uint64(frame.epochSlots) == uint64(admission.epochSlots)
  let headers = uint64(config.candidate.reporting.reports.ancestors.headers)
  if not sameCores or not sameValidators or not sameEpoch or headers == 0:
    return refused[FuzzBackend](FuzzBackendError.InvalidConfiguration)
  var selected = config
  selected.candidate.reporting.reports.anchors.lookupAge = LookupAge(
      config.parameters.get(maxLookupAnchorAge)) # GP reporting_assurance limitlookupanchorage uses the host protocol tuple.
  FuzzBackendResult[FuzzBackend](status: FuzzBackendError.None,
      completed: FuzzBackend(configured: true, config: selected))
proc fuzzBackendHeader*(backend: FuzzBackend): FuzzBackendResult[OwnedHeader] =
  ## Expose only an immutable selected header; this is no prepared update or production trust receipt.
  if not backend.seeded: return refused[OwnedHeader](FuzzBackendError.MissingSeed)
  let owner = if backend.executing: backend.chain.chainView.bestBlock.value.header else: backend.seedHeader
  FuzzBackendResult[OwnedHeader](status: FuzzBackendError.None, completed: owner)
proc response(backend: FuzzBackend, message: FuzzResult[FuzzMessage]): FuzzBackendResult[FuzzMessage] =
  ## Output budget/backend construction failures stay local rather than becoming protocol Error text.
  if message.error != FuzzError.None: return refused[FuzzMessage](FuzzBackendError.ReplyFailure)
  FuzzBackendResult[FuzzMessage](status: FuzzBackendError.None, completed: message.value)
proc executeFuzz*(backend: var FuzzBackend, request: FuzzMessage): FuzzBackendResult[FuzzMessage] =
  ## Execute one session-ordered host request synchronously outside transport ticks, preserving atomic import publication.
  if not backend.configured: return refused[FuzzMessage](FuzzBackendError.Uninitialized)
  let info = request.fuzzInfo
  if info.error != FuzzError.None: return refused[FuzzMessage](FuzzBackendError.InvalidRequest)
  if uint64(info.value.bytes) > uint64(backend.config.wire.bytes):
    return refused[FuzzMessage](FuzzBackendError.LimitExceeded)
  let config = backend.config
  case info.value.kind
  of FuzzKind.Initialize:
    if backend.seeded: return refused[FuzzMessage](FuzzBackendError.AlreadyInitialized)
    if request.fuzzAncestors.value.len != 0 and not config.initialAncestry: return refused[
        FuzzMessage](FuzzBackendError.UnsupportedFeature)
    let owned = request.fuzzHeader.value
    var bytes = newSeq[byte](owned.headerInfo.value.consumed)
    assert owned.encodeOwnedHeader(bytes).error == HeaderError.None
    let identity = blake2b256(bytes)
    if identity.error != CryptoError.None: return refused[FuzzMessage](FuzzBackendError.HashFailure)
    let ancestry = captureFuzzAncestry(owned, request.fuzzAncestors.value, config.ancestryLimits)
    if ancestry.error != FuzzAncestryError.None:
      return FuzzBackendResult[FuzzMessage](status: FuzzBackendError.AncestryFailure,
          ancestryReason: ancestry.error)
    let state = request.fuzzState.value
    let reply = backend.response(newFuzzRoot(state.commitment.root, config.wire))
    if reply.error != FuzzBackendError.None: return reply
    backend.ancestry = ancestry.value
    backend.seedHeader = owned
    backend.seedHash = BlockHash(array[32, byte](identity.value))
    backend.seedState = state
    backend.seeded = true # Exact supplied map becomes the explicit fuzz seed only after a complete reply can be owned.
    reply
  of FuzzKind.GetState:
    if not backend.seeded: return refused[FuzzMessage](FuzzBackendError.MissingSeed)
    let hash = BlockHash(array[32, byte](request.fuzzRequestedHeader.value))
    if array[32, byte](hash) == array[32, byte](backend.seedHash):
      return backend.response(newFuzzState(backend.seedState, config.wire))
    if not backend.executing: return refused[FuzzMessage](FuzzBackendError.UnknownState)
    let selected = backend.chain.chainView.blockAt(hash)
    if selected.error == GenesisError.None:
      return backend.response(newFuzzState(selected.value.stateSnapshot, config.wire))
    for sibling in backend.siblings:
      if array[32, byte](sibling.hash) == array[32, byte](hash):
        return backend.response(newFuzzState(sibling.state, config.wire))
    refused[FuzzMessage](FuzzBackendError.UnknownState)
  of FuzzKind.ImportBlock:
    if not backend.seeded: return refused[FuzzMessage](FuzzBackendError.MissingSeed)
    var chain = backend.chain
    var ancestry = backend.ancestry
    var sibling = false
    let body = request.fuzzBlock.value
    if backend.executing and uint64(config.forkStates) > 0:
      let fields = readHeader(blockHeader(body).value).value.owner.headerInfo.value.unsigned
      let head = backend.chain.chainView.bestBlock.value
      if array[32, byte](fields.parent) == array[32, byte](head.blockHash):
        discard # A direct extension starts a new sibling group only after actual successful execution.
      elif backend.hasForkParent and array[32, byte](fields.parent) ==
          array[32, byte](backend.forkParent.chainView.bestBlock.value.blockHash):
        chain = backend.forkParent
        ancestry = backend.forkAncestry
        sibling = true # Restoring the exact immutable parent also restores its full header context.
      else:
        return refused[FuzzMessage](FuzzBackendError.UnknownParent)
    if not backend.executing:
      var bytes = newSeq[byte](backend.seedHeader.headerInfo.value.consumed)
      assert backend.seedHeader.encodeOwnedHeader(bytes).error == HeaderError.None
      let captured = captureFuzzSeedSnapshot(bytes, backend.seedState, config.parameters)
      if captured.error != GenesisError.None: return refused[FuzzMessage](
          FuzzBackendError.SeedContextFailure)
      let initialized = initApplicationChain(fuzzSeedView(captured))
      if initialized.error != ApplicationChainError.None: return refused[FuzzMessage](
          FuzzBackendError.SeedContextFailure)
      chain = initialized.value # Lazy application capture cannot reject or rewrite the accepted protocol seed.
    let prepared = prepareFuzzCurrentCandidate(chain, body, ancestry,
        config.candidate)
    if prepared.error != CurrentCandidateError.None:
      return FuzzBackendResult[FuzzMessage](status: FuzzBackendError.CandidateFailure,
          candidateReason: prepared) # The caller must inspect the precise failed stage; resource/context failures are not consensus Errors.
    let state = prepared.value.currentUpdateState
    let reply = backend.response(newFuzzRoot(state.commitment.root, config.wire))
    if reply.error != FuzzBackendError.None: return reply
    if not chain.canInstallPrepared(prepared.value): return refused[FuzzMessage](
        FuzzBackendError.StateChanged)
    let nextAncestry = extendFuzzAncestry(ancestry, prepared.value.currentUpdateChild.header,
        config.ancestryLimits)
    if nextAncestry.error != FuzzAncestryError.None:
      return FuzzBackendResult[FuzzMessage](status: FuzzBackendError.AncestryFailure,
          ancestryReason: nextAncestry.error)
    var siblings: seq[ForkState] = @[]
    let identity = prepared.value.currentUpdateChild.blockHash
    if uint64(config.forkStates) > 0:
      if sibling:
        for saved in backend.siblings:
          if array[32, byte](saved.hash) != array[32, byte](identity):
            siblings.add(saved) # A duplicate replay refreshes one identity instead of consuming another slot.
      if uint64(siblings.len) == uint64(config.forkStates):
        var retained: seq[ForkState] = @[]
        for index in 1..<siblings.len: retained.add(siblings[
            index]) # Evict only the oldest sibling map before adding this one.
        siblings = retained
      siblings.add(ForkState(hash: identity, state: state))
      backend.forkParent = chain
      backend.forkAncestry = ancestry
      backend.hasForkParent = true # Commit group-parent selection only after every preparation/reply/retention check succeeds.
    chain.installPrepared(prepared.value)
    backend.siblings = siblings
    backend.chain = chain
    backend.ancestry = nextAncestry.value
    backend.executing = true # Publish exact state/history together only after all local reply/retention checks succeed.
    reply
  else:
    refused[FuzzMessage](FuzzBackendError.InvalidRequest) # PeerInfo and responses belong to the session layer, never STF execution.
