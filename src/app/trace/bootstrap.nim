# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Initialize a trace replay chain only from independently supplied header/state anchors and full Parameters.
## The published Genesis file cannot select its own trust or infer a chain profile.
import std/assertions
import ../chain
import ../../chain/[genesis, parameters, provider]
import ../../codec/[header, bounded]
import ../../codec/state/trie as state_trie
import ../../state/trace/[genesis as trace_genesis, state as trace_state]
import ../../state/store

type
  TraceBootstrapTrust* = object ## Independent configuration must anchor both full header identity and its separately supplied posterior map.
    header*: BlockHash
    state*: StateRoot
  TraceBootstrapError* {.pure.} = enum ## Identity, profile and actual chain-capture refusals expose no initialized application chain.
    Uninitialized, None, InvalidOwner, InvalidParameters, CaptureFailure, HeaderMismatch,
      StateMismatch, FinalizationFailure, ChainFailure
  TraceBootstrapResult* = object ## Only complete capture plus both independent anchors grants a new configured initial chain.
    case status: TraceBootstrapError
    of None: completed: ApplicationChain
    of CaptureFailure: captureReason: GenesisError
    of FinalizationFailure: finalizationReason: ViewFinalizeError
    of ChainFailure: chainReason: ApplicationChainResult[ApplicationChain]
    else: discard # Default/profile/anchor refusals retain no usable startup prefix.

func error*(outcome: TraceBootstrapResult): TraceBootstrapError =
  ## Read the immutable selected stage without extracting an unrelated payload.
  outcome.status
func value*(outcome: TraceBootstrapResult): ApplicationChain {.inline,
    requires: outcome.status == TraceBootstrapError.None.} =
  ## Extract only a new chain bound to externally configured identity and full Parameters.
  outcome.completed
func captureFailure*(outcome: TraceBootstrapResult): GenesisError {.inline,
    requires: outcome.status == TraceBootstrapError.CaptureFailure.} =
  ## Preserve actual structural/profile capture refusal.
  outcome.captureReason
func finalizationFailure*(outcome: TraceBootstrapResult): ViewFinalizeError {.inline,
    requires: outcome.status == TraceBootstrapError.FinalizationFailure.} =
  ## Preserve a genuine initial-view refusal without publishing a partially selected chain.
  outcome.finalizationReason
func chainFailure*(outcome: TraceBootstrapResult): ApplicationChainResult[
    ApplicationChain] {.inline, requires: outcome.status == TraceBootstrapError.ChainFailure.} =
  ## Retain only the actual failed application initializer and its guarded nested reason.
  outcome.chainReason

proc bootstrapTraceChain*(source: TraceGenesis, trust: TraceBootstrapTrust,
    parameters: Parameters): TraceBootstrapResult =
  ## Capture the exact header/map against the configured full profile, require both independent anchors, then initialize the explicitly trusted finalized genesis; never replace an existing chain.
  if source.traceGenesisBytes.error != TraceGenesisError.None:
    return TraceBootstrapResult(status: TraceBootstrapError.InvalidOwner)
  if not parameters.valid:
    return TraceBootstrapResult(status: TraceBootstrapError.InvalidParameters)
  let header = source.traceGenesisHeader.value
  var wire = newSeq[byte](header.headerInfo.value.consumed)
  let encoded = header.encodeOwnedHeader(wire)
  assert encoded.error == HeaderError.None
  let state = source.traceGenesisState.value.traceStateSnapshot.value
  let captured = captureBlockSnapshot(wire, state, parameters)
  if captured.error != GenesisError.None:
    return TraceBootstrapResult(status: TraceBootstrapError.CaptureFailure,
        captureReason: captured.error)
  if array[32, byte](captured.value.blockHash) != array[32, byte](trust.header):
    return TraceBootstrapResult(status: TraceBootstrapError.HeaderMismatch)
  if array[32, byte](state.commitment.root) != array[32, byte](trust.state):
    return TraceBootstrapResult(status: TraceBootstrapError.StateMismatch) # The header commits its parent's state, so its hash alone cannot authenticate this posterior map.
  let selected = genesisView(captured).finalizeView(captured.value.blockHash)
  if selected.error != ViewFinalizeError.None:
    return TraceBootstrapResult(status: TraceBootstrapError.FinalizationFailure,
        finalizationReason: selected.error)
  let chain = initApplicationChain(selected.value)
  if chain.error != ApplicationChainError.None:
    return TraceBootstrapResult(status: TraceBootstrapError.ChainFailure, chainReason: chain)
  TraceBootstrapResult(status: TraceBootstrapError.None, completed: chain.value)
