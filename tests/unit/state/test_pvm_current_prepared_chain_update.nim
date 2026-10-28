# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_prepared_chain_update_arc_release"}

## Opaque current updates prepare on private copies and install exact state/view candidates only while all original owners remain current.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_current_chain as state_accumulation_current_chain
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/store as state_store
import ../../support/state_accumulation_current_chain_context
import ../../support/state_report_context
import ../../support/testing_arc_evidence
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc witness(context: CurrentChainFixture) =
  ## Preparation retains exact originals and independent candidate owners before either live handle changes.
  let parent = context.parent.value.stateSnapshot
  var state = forkStateStore(parent).value
  var view = context.currentChainSeeded
  let old = view
  let prepared = prepareCurrentChainUpdate(state, view, context.source, ByteLimit(100000))
  assert prepared.error == CurrentChainPreparationError.None
  let update = prepared.value
  assert update.ready and canInstallCurrentChainUpdate(state, view, update)
  assert sameStateSnapshot(state.snapshot.value, parent) and sameChainView(view, old)
  let candidate = update.currentUpdateState
  assert sameStateSnapshot(candidate, context.source.currentConsensusState.value)
  assert sameStateSnapshot(update.currentUpdateChild.stateSnapshot, candidate)
  assert sameStateSnapshot(update.currentUpdateView.bestBlock.value.stateSnapshot, candidate)
  let expectedView = update.currentUpdateView
  failHash(3)
  installCurrentChainUpdate(state, view, update)
  assert hashCalls() == 0, "installation performs no capture, composition or hashing"
  assert sameStateSnapshot(state.snapshot.value, candidate) and sameChainView(view, expectedView)
  assert not canInstallCurrentChainUpdate(state, view, update), "replay cannot replace original parent ownership"
  assert not canInstallCurrentChainUpdate(state, old, update), "one advanced live handle cannot authorize partial installation"
  failHash(0)
proc refusals(context: CurrentChainFixture) =
  ## Failed prepare/can-install checks expose no prefix and preserve current live handles independently.
  let parent = context.parent.value.stateSnapshot
  var state = forkStateStore(parent).value
  var view = context.currentChainSeeded
  let original = view
  let owner = prepareCurrentChainUpdate(state, view, context.source, ByteLimit(100000)).value
  let uninitialized = default(PreparedCurrentChainUpdate)
  assert not uninitialized.ready
  assert not canInstallCurrentChainUpdate(state, view, uninitialized)
  var absent = default(StateStore)
  assert not canInstallCurrentChainUpdate(absent, view, owner)
  var noView = default(ChainView)
  assert not canInstallCurrentChainUpdate(state, noView, owner)
  let invalid = prepareCurrentChainUpdate(state, view, default(
      PreparedCurrentAccumulationConsensus), ByteLimit(100000))
  assert invalid.error == CurrentChainPreparationError.ChainFailure
  assert invalid.chainFailure.error == CurrentAccumulationChainError.InvalidSource
  failHash(1)
  let short = prepareCurrentChainUpdate(state, view, context.source, ByteLimit(0))
  assert short.error == CurrentChainPreparationError.ChainFailure
  assert short.chainFailure.error == CurrentAccumulationChainError.LimitExceeded
  assert hashCalls() == 0
  let refused = prepareCurrentChainUpdate(state, view, context.source, ByteLimit(100000))
  assert refused.error == CurrentChainPreparationError.ChainFailure
  assert refused.chainFailure.error == CurrentAccumulationChainError.CaptureFailure
  assert sameStateSnapshot(state.snapshot.value, parent) and sameChainView(view, original)
  failHash(0)
  var rebuilt = newStateStore(context.entries, state_report_context.limits()).value
  assert array[32, byte](rebuilt.snapshot.value.commitment.root) == array[32, byte](
      parent.commitment.root)
  assert not canInstallCurrentChainUpdate(rebuilt, view, owner), "equal complete roots cannot substitute version identity"
  assert not canInstallCurrentChainUpdate(state, owner.currentUpdateView, owner), "changed view alone cannot replace the retained complete prior view"
  let badHeader = context.parent.value.header
  let priced = captureBlockSnapshot(currentChainBytes(badHeader), parent,
    currentChainSettings(alteredPrice = true))
  assert priced.error == GenesisError.None
  let wrongProfile = genesisView(priced)
  assert not canInstallCurrentChainUpdate(state, wrongProfile, owner), "can-install also binds complete retained parameter tuples"
  let mismatch = prepareCurrentChainUpdate(state, wrongProfile, context.source, ByteLimit(100000))
  assert mismatch.error == CurrentChainPreparationError.ChainFailure
  assert mismatch.chainFailure.error == CurrentAccumulationChainError.ProfileMismatch
proc cycle(context: CurrentChainFixture) =
  ## All private preparation/capture/installation handles die before the next lifetime observation.
  var state = forkStateStore(context.parent.value.stateSnapshot).value
  var view = context.currentChainSeeded
  let owner = prepareCurrentChainUpdate(state, view, context.source, ByteLimit(100000)).value
  installCurrentChainUpdate(state, view, owner)
  assert sameStateSnapshot(state.snapshot.value, owner.currentUpdateState)
proc main() {.raises.} =
  ## Real signed current sources cover empty and mixed guest/preimage/guarantee successors.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve exact signed transport.
  let base = decodeOwnedReport(wire, 2).value
  let quiet = currentChainFixture(base)
  let context = currentChainFixture(base, uses = 2, available = true, blobs = true)
  witness(quiet)
  witness(context)
  refusals(context)
  var retained = default(PreparedCurrentChainUpdate)
  var sourceState = default(StateStore)
  var sourceView = default(ChainView)
  block:
    let local = currentChainFixture(base, rotated = true)
    sourceState = forkStateStore(local.parent.value.stateSnapshot).value
    sourceView = local.currentChainSeeded
    retained = prepareCurrentChainUpdate(sourceState, sourceView, local.source, ByteLimit(100000)).value
  let copy = retained
  retained = default(PreparedCurrentChainUpdate)
  assert copy.ready and canInstallCurrentChainUpdate(sourceState, sourceView, copy), "copied prepared owner survives source scope and handle reset"
  failHash(3)
  installCurrentChainUpdate(sourceState, sourceView, copy)
  assert sameStateSnapshot(sourceState.snapshot.value, copy.currentUpdateState)
  assert hashCalls() == 0
  failHash(0)
  cycle(context)
  let occupied = getOccupiedMem()
  for iteration in 0..<1000: cycle(context) # Every candidate/view/child lifetime stays local to one cycle.
  let after = getOccupiedMem()
  assert occupied == after, "current prepared chain update releases"
  recordArcRelease("pvm_current_prepared_chain_update", 1000, occupied, after)
  echo "PVM current prepared chain update passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected signature/setup/capture/ownership failures fail the suite.
except:
  quit(2)
