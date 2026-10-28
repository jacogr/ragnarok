# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_chain_coordinator_arc_release"}

## Current composed state and chain view install together only after exact ownership/profile and all private child stages succeed.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/header as codec_header
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/state/accumulation_current_chain as state_accumulation_current_chain
import ../../../src/state/accumulation_current_publication as state_accumulation_current_publication
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
import ../../support/state_accumulation_current_chain_context
import ../../support/testing_arc_evidence
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc unchanged(state: StateStore, view: ChainView, prior: StateStoreSnapshot, old: ChainView) =
  ## Every refused private stage preserves both exact live owners, complete history and finality.
  assert sameStateSnapshot(state.snapshot.value, prior)
  assert sameChainView(view, old)
proc witness(context: CurrentChainFixture) =
  ## Independently spell private adoption, sealed-header capture and direct-child append without guest replay.
  let parent = context.parent.value.stateSnapshot
  let original = context.currentChainSeeded
  let binding = context.source.currentChainAdmission.reportBlockStage.value.value.admitted
  var expectedState = forkStateStore(parent).value
  assert publishCurrentAccumulationState(expectedState, context.source).error ==
      CurrentAccumulationPublicationError.None
  failHash(0)
  let child = captureBlockSnapshot(currentChainBytes(binding.admittedHeader),
      expectedState.snapshot.value, currentChainSettings())
  assert child.error == GenesisError.None
  let expected = original.advanceView(child).value
  let expectedHashes = hashCalls()
  assert expectedHashes > 0, "child identity requires sealed-header hashing"
  var state = forkStateStore(parent).value
  var view = original
  let alias = state
  failHash(0)
  let applied = applyCurrentAccumulationChain(state, view, context.source, ByteLimit(100000))
  assert applied.error == CurrentAccumulationChainError.None, $applied.error
  assert hashCalls() == expectedHashes, "coordinator never reruns current guests or state composition"
  assert sameStateSnapshot(applied.value.stateSnapshot, context.source.currentConsensusState.value)
  assert sameStateSnapshot(state.snapshot.value, applied.value.stateSnapshot)
  assert sameStateSnapshot(view.bestBlock.value.stateSnapshot, applied.value.stateSnapshot)
  assert sameChainView(view, expected)
  assert sameStateSnapshot(alias.snapshot.value, parent), "old state alias stays historical"
  assert sameChainView(original, context.currentChainSeeded), "old view alias retains head/finality"
  assert applied.value.chainParameters.encodeParameters == currentChainSettings().encodeParameters
  let installed = state.snapshot.value
  let selected = view
  failHash(1)
  assert applyCurrentAccumulationChain(state, view, context.source, ByteLimit(100000)).error ==
      CurrentAccumulationChainError.StaleState
  unchanged(state, view, installed, selected)
  assert hashCalls() == 0, "replay refuses before all hashing"
  failHash(0)
proc refusals(context, foreign: CurrentChainFixture) =
  ## Original owner, selected head and exact parameter fields are independent preconditions.
  let parent = context.parent.value.stateSnapshot
  let original = context.currentChainSeeded
  var state = forkStateStore(parent).value
  var view = original
  failHash(1)
  let invalid = applyCurrentAccumulationChain(state, view, default(
      PreparedCurrentAccumulationConsensus), ByteLimit(100000))
  assert invalid.error == CurrentAccumulationChainError.InvalidSource
  unchanged(state, view, parent, original)
  let short = applyCurrentAccumulationChain(state, view, context.source, ByteLimit(0))
  assert short.error == CurrentAccumulationChainError.LimitExceeded
  unchanged(state, view, parent, original)
  let wrongSource = applyCurrentAccumulationChain(state, view, foreign.source, ByteLimit(100000))
  assert wrongSource.error == CurrentAccumulationChainError.StaleState
  unchanged(state, view, parent, original)
  var emptyState = default(StateStore)
  let absent = applyCurrentAccumulationChain(emptyState, view, context.source, ByteLimit(100000))
  assert absent.error == CurrentAccumulationChainError.StateFailure and absent.stateError ==
      StateStoreError.Uninitialized
  assert emptyState.snapshot.error == StateStoreError.Uninitialized and sameChainView(view, original)
  var emptyView = default(ChainView)
  let noHead = applyCurrentAccumulationChain(state, emptyView, context.source, ByteLimit(100000))
  assert noHead.error == CurrentAccumulationChainError.UninitializedView
  assert sameStateSnapshot(state.snapshot.value, parent) and emptyView.bestBlock.error !=
      GenesisError.None
  var wrongView = foreign.currentChainSeeded
  let oldWrong = wrongView
  let wrongHead = applyCurrentAccumulationChain(state, wrongView, context.source, ByteLimit(100000))
  assert wrongHead.error == CurrentAccumulationChainError.StaleView
  unchanged(state, wrongView, parent, oldWrong)
  assert hashCalls() == 0
  failHash(0)
  let binding = context.source.currentChainAdmission.reportBlockStage.value.value.admitted
  let wrongParameters = captureBlockSnapshot(currentChainBytes(binding.admittedParent), parent,
    currentChainSettings(alteredPrice = true))
  assert wrongParameters.error == GenesisError.None
  var wrongProfile = genesisView(wrongParameters)
  let priorProfile = wrongProfile
  assert uint64(wrongProfile.bestBlock.value.cores) == uint64(context.parent.value.cores)
  assert uint64(wrongProfile.bestBlock.value.epochSlots) == uint64(context.parent.value.epochSlots)
  failHash(1)
  let priceMismatch = applyCurrentAccumulationChain(state, wrongProfile, context.source, ByteLimit(100000))
  assert priceMismatch.error == CurrentAccumulationChainError.ProfileMismatch, "matching core/epoch/population does not authorize altered deposit prices"
  unchanged(state, wrongProfile, parent, priorProfile)
  assert hashCalls() == 0
  failHash(0)
  var changed = currentChainBytes(binding.admittedParent)
  changed[0] = changed[0] xor 1 # A structurally captured different parent header retains the exact same state owner.
  let differentHeader = captureBlockSnapshot(changed, parent, currentChainSettings())
  assert differentHeader.error == GenesisError.None
  var lateView = genesisView(differentHeader)
  let priorLate = lateView
  let late = applyCurrentAccumulationChain(state, lateView, context.source, ByteLimit(100000))
  assert late.error == CurrentAccumulationChainError.ViewFailure
  unchanged(state, lateView, parent, priorLate)
  failHash(1)
  let capture = applyCurrentAccumulationChain(state, view, context.source, ByteLimit(100000))
  assert capture.error == CurrentAccumulationChainError.CaptureFailure
  unchanged(state, view, parent, original)
  failHash(0)
proc cycle(context: CurrentChainFixture) =
  ## Scoped child captures and both live-handle copies release before the next iteration.
  var state = forkStateStore(context.parent.value.stateSnapshot).value
  var view = context.currentChainSeeded
  let applied = applyCurrentAccumulationChain(state, view, context.source, ByteLimit(100000))
  assert applied.error == CurrentAccumulationChainError.None
proc main() {.raises.} =
  ## Real signed current scenarios cover all consensus components alongside guest-provided and lookup effects.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve exact report transport.
  let base = decodeOwnedReport(wire, 2).value
  let quiet = currentChainFixture(base)
  let combined = currentChainFixture(base, uses = 2, available = true, blobs = true)
  witness(quiet)
  witness(combined)
  witness(currentChainFixture(base, uses = 2, disputed = true))
  witness(currentChainFixture(base, rotated = true))
  witness(currentChainFixture(base, ticket = true))
  refusals(quiet, combined)
  cycle(combined)
  let occupied = getOccupiedMem()
  for iteration in 0..<1000: cycle(combined) # Every child/view owner remains local to one cycle.
  let after = getOccupiedMem()
  assert occupied == after, "current state/view coordinator releases"
  recordArcRelease("pvm_current_chain_coordinator", 1000, occupied, after)
  echo "PVM current chain coordinator passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected source/setup/capture failures fail the suite.
except:
  quit(2)
