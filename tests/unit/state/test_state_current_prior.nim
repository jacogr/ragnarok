# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine prepared update projections preserve exact original state/view and allocation-free retention facts.
# @@Verification={"arc":"state_current_prior_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_accumulation_current_chain_context
import ../../support/state_current_checkpoint_context
import ../../support/testing_arc_evidence
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/store as state_store
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/genesis as chain_genesis
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/bounded as codec_bounded
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Genuine current preparation happens before projection hash-free probes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observing original/posterior context cannot hash or reconstruct a state.
proc cycle(update: PreparedCurrentChainUpdate) =
  ## Retire original and posterior view/index copies with the same original state owner.
  let prior = update.currentUpdatePriorView
  assert sameStateSnapshot(update.currentUpdatePriorState, prior.bestBlockContext.state)
  assert update.currentUpdatePriorViewInfo.bytes == prior.viewRetentionInfo.bytes
  assert update.currentUpdateViewInfo.bytes == update.currentUpdateView.viewRetentionInfo.bytes
proc main() {.raises.} =
  ## Both explicit parent finality and its absence remain observable, never inferred from a root.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = currentChainFixture(decodeOwnedReport(bytes, 2).value, completeState = true)
  let final = currentCheckpointPrepared(fixture)
  let absent = currentCheckpointPrepared(fixture, finalized = false)
  fail(1)
  assert sameStateSnapshot(final.currentUpdatePriorState, fixture.parent.value.stateSnapshot)
  assert sameChainView(final.currentUpdatePriorView, fixture.currentChainSeeded)
  assert sameChainView(absent.currentUpdatePriorView, genesisView(fixture.parent))
  assert not sameChainView(final.currentUpdatePriorView, absent.currentUpdatePriorView)
  assert final.currentUpdatePriorViewInfo.history == 1 and
      final.currentUpdatePriorViewInfo.owners == 2
  assert final.currentUpdateViewInfo.history == 2 and final.currentUpdateViewInfo.owners == 3
  assert absent.currentUpdatePriorViewInfo.owners == 1 and absent.currentUpdateViewInfo.owners == 2
  let allocation = getOccupiedMem()
  for i in 0..<1000:
    assert final.currentUpdatePriorViewInfo.bytes > 0 and final.currentUpdateViewInfo.bytes > 0
  assert allocation == getOccupiedMem() # Fixed facts do not allocate retained or temporary view indexes.
  for i in 0..<25: cycle(final)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(final)
  let after = getOccupiedMem()
  assert before == after and calls() == 0
  recordArcRelease("state_current_prior", 1000, before, after)
  fail(0)
  echo "state-current-prior: ok"
try:
  main()
except:
  quit(2) # Invalid genuine update preparation/projection cannot become original-parent evidence.
