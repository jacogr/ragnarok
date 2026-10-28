# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_publication_handoff_arc_release"}

## Publishing freezes one genuine current update; only its exact installed child can complete the bounded host handoff.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/app/chain as app_chain
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../support/state_accumulation_current_chain_context
import ../../support/testing_arc_evidence
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Host publication bookkeeping cannot repeat primitive work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Actual primitive counts distinguish cached authority checks from recomputation.
proc cycle(original: ApplicationChain, update: PreparedCurrentChainUpdate) =
  ## External canonical installation is acknowledged without granting any storage receipt authority.
  var owner = original
  var slot = default(CurrentAccumulationHandoff)
  assert slot.enqueue(owner, update) == CurrentHandoffAdmission.None
  slot.markPublishing()
  assert slot.phase == CurrentHandoffPhase.Publishing
  assert not slot.cancel()
  slot.process(owner) # Ordinary processing must not install a job owned by external publication.
  assert sameStateSnapshot(owner.stateSnapshot.value, original.stateSnapshot.value)
  owner.installPrepared(update) # This host-only fixture installs after its external phase; no disk IO is claimed.
  slot.completePublication(owner.installedPrepared(update))
  assert slot.phase == CurrentHandoffPhase.Finished and not slot.cancel()
  let result = slot.take()
  assert result.error == CurrentHandoffError.None
  assert sameStateSnapshot(result.value.stateSnapshot, update.currentUpdateState)
  assert slot.phase == CurrentHandoffPhase.Idle
proc transitions(original: ApplicationChain, update: PreparedCurrentChainUpdate) =
  ## Publishing and Finished retain capacity; actual refusal needs acknowledgment and never becomes cancellation rollback.
  var owner = original
  var slot = default(CurrentAccumulationHandoff)
  let absent = default(ApplicationChain)
  let invalid = default(PreparedCurrentChainUpdate)
  failHash(3)
  assert slot.enqueue(owner, update) == CurrentHandoffAdmission.None
  slot.markPublishing()
  assert slot.enqueue(absent, invalid) == CurrentHandoffAdmission.Busy
  slot.process(owner)
  assert sameStateSnapshot(owner.stateSnapshot.value, original.stateSnapshot.value)
  assert slot.phase == CurrentHandoffPhase.Publishing and not slot.cancel()
  let noResult = default(ApplicationChainResult[BlockSnapshot])
  slot.completePublication(noResult)
  assert slot.phase == CurrentHandoffPhase.Finished
  assert slot.enqueue(absent, invalid) == CurrentHandoffAdmission.Busy
  assert slot.take.error == CurrentHandoffError.DurabilityRefused
  for reason in [CurrentHandoffError.StaleState, CurrentHandoffError.RpcRefused,
      CurrentHandoffError.DurabilityRefused]:
    for publishing in [false, true]:
      assert slot.enqueue(owner, update) == CurrentHandoffAdmission.None
      if publishing: slot.markPublishing() # Both pre-entry and post-retirement failures remain typed terminal refusals.
      slot.refusePublication(reason)
      assert slot.phase == CurrentHandoffPhase.Finished and not slot.cancel()
      assert slot.take.error == reason
  cycle(original, update)
  assert hashCalls() == 0, "publication handoff neither hashes nor executes"
  failHash(0)
proc foreignReceipt(original: ApplicationChain, update: PreparedCurrentChainUpdate,
    foreignOriginal: ApplicationChain, foreignUpdate: PreparedCurrentChainUpdate) =
  ## Equal complete roots and sealed hashes still cannot replace the expected exact state owner.
  assert array[32, byte](update.currentUpdateState.commitment.root) ==
    array[32, byte](foreignUpdate.currentUpdateState.commitment.root)
  assert array[32, byte](update.currentUpdateChild.blockHash) ==
    array[32, byte](foreignUpdate.currentUpdateChild.blockHash)
  assert not sameStateSnapshot(update.currentUpdateState, foreignUpdate.currentUpdateState)
  var foreignOwner = foreignOriginal
  foreignOwner.installPrepared(foreignUpdate)
  let receipt = foreignOwner.installedPrepared(foreignUpdate)
  assert receipt.error == ApplicationChainError.None
  var slot = default(CurrentAccumulationHandoff)
  assert slot.enqueue(original, update) == CurrentHandoffAdmission.None
  slot.markPublishing()
  slot.completePublication(receipt)
  assert slot.take.error == CurrentHandoffError.StaleState
  assert sameStateSnapshot(original.stateSnapshot.value, update.currentUpdateView.parentOf(
    update.currentUpdateChild.blockHash).value.stateSnapshot)
proc main() {.raises.} =
  ## Independently constructed genuine current fixtures provide exact and equal-hash/different-owner outcomes.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[
      index]) # Initialize every pinned fixture byte before decoding.
  let base = decodeOwnedReport(bytes, 2).value
  let context = currentChainFixture(base, available = true, blobs = true)
  let other = currentChainFixture(base, available = true, blobs = true)
  let original = initApplicationChain(context.currentChainSeeded).value
  let foreign = initApplicationChain(other.currentChainSeeded).value
  let update = original.prepareAccumulation(context.source, ByteLimit(100000)).value
  let foreignUpdate = foreign.prepareAccumulation(other.source, ByteLimit(100000)).value
  transitions(original, update)
  foreignReceipt(original, update, foreign, foreignUpdate)
  cycle(original, update)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(original, update) # Every external/terminal source alias retires at the activation boundary.
  let after = getOccupiedMem()
  assert before == after, "publication handoff releases"
  recordArcRelease("pvm_current_publication_handoff", 1000, before, after)
  echo "PVM current publication handoff passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Any genuine preparation, root identity or guarded completion failure remains a failed witness.
except:
  quit(2)
