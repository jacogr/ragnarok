# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit operator trust binds a complete recovered map to one sealed head.
## Recovery creates one retained head with unset finality; no ancestor or consensus proof is inferred.

import std/assertions
import ../chain
import ./[identity as checkpoint_identity, codec as checkpoint_codec, file as checkpoint_file]
import ../../codec/bounded
import ../../chain/[genesis, provider]
import ../../state/store

type
  ApplicationRecoveryError* {.pure.} = enum ## Refusals expose no partial canonical owner.
    Uninitialized, None, MissingTrust, StateFailure, ContextMismatch, HeaderFailure, HeaderMismatch,
      EnvelopeFailure, FileFailure
  ApplicationRecoveryResult* = object ## Only an exact trusted head/map pair grants an independent application branch.
    case status: ApplicationRecoveryError
    of None:
      completed: ApplicationChain
    of StateFailure:
      stateReason: StateStoreError
    of EnvelopeFailure:
      envelopeReason: ApplicationCheckpointResult[StateStore]
    of FileFailure:
      fileReason: ApplicationCheckpointFileResult[StateStore]
    else:
      discard # Missing trust and mismatches retain no recovered graph.
func error*(outcome: ApplicationRecoveryResult): ApplicationRecoveryError =
  ## Inspect status without exposing result construction or replacement state.
  outcome.status
func value*(outcome: ApplicationRecoveryResult): ApplicationChain {.inline,
    requires: outcome.status == ApplicationRecoveryError.None.} =
  ## Only successful recovery permits canonical startup.
  outcome.completed
func stateError*(outcome: ApplicationRecoveryResult): StateStoreError {.inline,
    requires: outcome.status == ApplicationRecoveryError.StateFailure.} =
  ## Preserve an actual absent or refused complete map.
  outcome.stateReason
proc recoverApplicationChain*(state: StateStoreSnapshot, sealedHeader: openArray[byte],
    expected: ApplicationCheckpointIdentity): ApplicationRecoveryResult =
  ## The operator supplies independent trust; never derive it from the map or checkpoint being recovered.
  if not expected.ready:
    return ApplicationRecoveryResult(status: ApplicationRecoveryError.MissingTrust)
  let forked = forkStateStore(state)
  if forked.error != StateStoreError.None:
    return ApplicationRecoveryResult(status: ApplicationRecoveryError.StateFailure,
      stateReason: forked.error) # Initialization is checked before reading any snapshot accessor.
  if array[32, byte](state.commitment.root) != array[32, byte](expected.stateRoot):
    return ApplicationRecoveryResult(status: ApplicationRecoveryError.ContextMismatch)
  let captured = captureBlockSnapshot(sealedHeader, state, expected.parameters)
  if captured.error != GenesisError.None:
    return ApplicationRecoveryResult(status: ApplicationRecoveryError.HeaderFailure)
  if array[32, byte](captured.value.blockHash) != array[32, byte](expected.blockHash):
    return ApplicationRecoveryResult(status: ApplicationRecoveryError.HeaderMismatch)
  if captured.value.slot != uint32(expected.slot):
    return ApplicationRecoveryResult(status: ApplicationRecoveryError.ContextMismatch)
  let resumed = initApplicationChain(genesisView(captured))
  assert resumed.error == ApplicationChainError.None # Exact initialized capture permits a policy-preserving fork.
  ApplicationRecoveryResult(status: ApplicationRecoveryError.None, completed: resumed.value)

func envelopeFailure*(outcome: ApplicationRecoveryResult): ApplicationCheckpointResult[
    StateStore] {.inline, requires: outcome.status == ApplicationRecoveryError.EnvelopeFailure.} =
  ## Preserve precise context/identity/map failure without returning any recovered state.
  outcome.envelopeReason
proc decodeRecoveryCheckpoint*(bytes, sealedHeader: openArray[byte],
    expected: ApplicationCheckpointIdentity, limits: StateStoreLimits,
    limit: ByteLimit): ApplicationRecoveryResult =
  ## Independent trust and explicit recovery policy precede complete-map allocation and canonical construction.
  if not expected.ready:
    return ApplicationRecoveryResult(status: ApplicationRecoveryError.MissingTrust)
  let restored = decodeApplicationCheckpoint(bytes, expected, limits, limit)
  if restored.error != ApplicationCheckpointError.None:
    return ApplicationRecoveryResult(status: ApplicationRecoveryError.EnvelopeFailure,
      envelopeReason: restored) # Failure owns only typed reasons; no decoded map is retained.
  recoverApplicationChain(restored.value.snapshot.value, sealedHeader, expected)

func fileFailure*(outcome: ApplicationRecoveryResult): ApplicationCheckpointFileResult[
    StateStore] {.inline, requires: outcome.status == ApplicationRecoveryError.FileFailure.} =
  ## Preserve bounded native/context/map read errors without granting a recovered owner.
  outcome.fileReason
proc loadRecoveryCheckpoint*(path: string, sealedHeader: openArray[byte],
    expected: ApplicationCheckpointIdentity, limits: StateStoreLimits,
    limit: ByteLimit): ApplicationRecoveryResult =
  ## Startup alone schedules synchronous bounded reads; default trust refuses before opening any path.
  if not expected.ready:
    return ApplicationRecoveryResult(status: ApplicationRecoveryError.MissingTrust)
  let restored = loadApplicationCheckpoint(path, expected, limits, limit)
  if restored.error != ApplicationCheckpointFileError.None:
    return ApplicationRecoveryResult(status: ApplicationRecoveryError.FileFailure,
      fileReason: restored) # Read failures never trigger repair, fallback or canonical replacement.
  recoverApplicationChain(restored.value.snapshot.value, sealedHeader, expected)
