# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fuzzer-owned ephemeral complete maps feed the ordinary current candidate pipeline without production bootstrap trust.
import std/assertions
import ./[chain, candidate]
import ../chain/[genesis, parameters, provider]
import ../codec/[bounded, header]
import ../crypto/primitives
import ../state/[fuzz_protocol, store, accumulation_current_update]

type
  FuzzBackendConfig* = object ## Parameters and every execution/codec ceiling are explicit trusted host configuration.
    parameters*: Parameters
    candidate*: CurrentCandidateLimits
    wire*: FuzzLimits
  FuzzBackendError* {.pure.} = enum ## Local refusals expose no reply and are never implicitly translated to consensus Error.
    Uninitialized, None, InvalidConfiguration, InvalidRequest, AlreadyInitialized,
    MissingSeed, UnsupportedFeature, HashFailure, SeedContextFailure, UnknownState,
    CandidateFailure, StateChanged, ReplyFailure, LimitExceeded
  FuzzBackendResult*[T] = object ## Success owns one complete value; candidate refusal preserves only its actual failed stage.
    case status: FuzzBackendError
    of None: completed: T
    of CandidateFailure: candidateReason: CurrentCandidateResult
    else: discard # No other refusal grants a prepared prefix, selected chain or response.
  FuzzBackend* = object ## Copies form independent ephemeral branches sharing only immutable prior snapshots.
    configured, seeded, executing: bool
    config: FuzzBackendConfig
    seedHeader: OwnedHeader
    seedHash: BlockHash
    seedState: StateStoreSnapshot
    chain: ApplicationChain
    older: seq[OwnedHeader]
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
func refused[T](reason: FuzzBackendError): FuzzBackendResult[T] =
  ## Failed/default operations retain no successful reply or chain prefix.
  FuzzBackendResult[T](status: reason)
proc initFuzzBackend*(config: FuzzBackendConfig): FuzzBackendResult[FuzzBackend] =
  ## Select explicit profile agreement before admitting any supplied seed.
  let frame = config.wire.frame
  let admission = config.candidate.reporting.admission.frame
  if not config.parameters.valid or uint64(frame.cores) != config.parameters.get(coreCount) or
      uint64(frame.epochSlots) != config.parameters.get(epochPeriod) or
      uint64(frame.cores) != uint64(admission.cores) or uint64(frame.validators) != uint64(
          admission.validators) or
      uint64(frame.epochSlots) != uint64(admission.epochSlots) or
      uint64(config.candidate.reporting.reports.ancestors.headers) == 0:
    return refused[FuzzBackend](FuzzBackendError.InvalidConfiguration)
  FuzzBackendResult[FuzzBackend](status: FuzzBackendError.None,
      completed: FuzzBackend(configured: true, config: config))
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
    if request.fuzzAncestors.value.len != 0: return refused[FuzzMessage](
        FuzzBackendError.UnsupportedFeature)
    let owned = request.fuzzHeader.value
    var bytes = newSeq[byte](owned.headerInfo.value.consumed)
    assert owned.encodeOwnedHeader(bytes).error == HeaderError.None
    let identity = blake2b256(bytes)
    if identity.error != CryptoError.None: return refused[FuzzMessage](FuzzBackendError.HashFailure)
    let state = request.fuzzState.value
    let reply = backend.response(newFuzzRoot(state.commitment.root, config.wire))
    if reply.error != FuzzBackendError.None: return reply
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
    if selected.error != GenesisError.None: return refused[FuzzMessage](
        FuzzBackendError.UnknownState)
    backend.response(newFuzzState(selected.value.stateSnapshot, config.wire))
  of FuzzKind.ImportBlock:
    if not backend.seeded: return refused[FuzzMessage](FuzzBackendError.MissingSeed)
    var chain = backend.chain
    if not backend.executing:
      var bytes = newSeq[byte](backend.seedHeader.headerInfo.value.consumed)
      assert backend.seedHeader.encodeOwnedHeader(bytes).error == HeaderError.None
      let captured = captureBlockSnapshot(bytes, backend.seedState, config.parameters)
      if captured.error != GenesisError.None: return refused[FuzzMessage](
          FuzzBackendError.SeedContextFailure)
      let initialized = initApplicationChain(genesisView(captured))
      if initialized.error != ApplicationChainError.None: return refused[FuzzMessage](
          FuzzBackendError.SeedContextFailure)
      chain = initialized.value # Lazy application capture cannot reject or rewrite the accepted protocol seed.
    let prepared = prepareCurrentCandidate(chain, request.fuzzBlock.value, backend.older,
        config.candidate)
    if prepared.error != CurrentCandidateError.None:
      return FuzzBackendResult[FuzzMessage](status: FuzzBackendError.CandidateFailure,
          candidateReason: prepared) # The caller must inspect the precise failed stage; resource/context failures are not consensus Errors.
    let state = prepared.value.currentUpdateState
    let reply = backend.response(newFuzzRoot(state.commitment.root, config.wire))
    if reply.error != FuzzBackendError.None: return reply
    if not chain.canInstallPrepared(prepared.value): return refused[FuzzMessage](
        FuzzBackendError.StateChanged)
    let before = chain.chainView.bestBlock.value.header
    let policy = config.candidate.reporting.reports.ancestors
    let nextSize = uint64(prepared.value.currentUpdateChild.header.headerInfo.value.consumed)
    if nextSize > uint64(policy.maxBytes): return refused[FuzzMessage](
        FuzzBackendError.LimitExceeded)
    var available = uint64(policy.maxBytes)-nextSize
    var older: seq[OwnedHeader] = @[]
    let maximum = min(24'u64, uint64(policy.headers)-1)
    for index in 0..backend.older.len:
      let source = if index == 0: before else: backend.older[index-1]
      let size = uint64(source.headerInfo.value.consumed)
      if uint64(older.len) >= maximum or size > available: break # Keep a contiguous newest-first prefix within both quotas.
      older.add(source)
      available -= size
    chain.installPrepared(prepared.value)
    backend.chain = chain
    backend.older = older
    backend.executing = true # Publish exact state/history together only after all local reply/retention checks succeed.
    reply
  else:
    refused[FuzzMessage](FuzzBackendError.InvalidRequest) # PeerInfo and responses belong to the session layer, never STF execution.
