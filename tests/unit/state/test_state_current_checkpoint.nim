# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current checkpoint capsules bind exact execution provenance, posterior bytes and separate explicit finality under bounded hash-free export.
# @@Verification={"arc": "state_current_checkpoint_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_checkpoint_context, accumulation_current_chain_context, arc_evidence]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, report_owned, state_trie]
import ../../../src/state/[current_checkpoint, checkpoint, store, accumulation_current_update, accumulation_current_consensus]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashing after genuine current execution/capture has completed on the stable host graph.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Cached-root serialization and retained-owner projections must perform no hashes.
proc detached(context: CurrentChainFixture): CurrentUpdateCheckpoint =
  ## Return only a capsule after local preparation aliases and application handles leave scope.
  captureCurrentUpdateCheckpoint(currentCheckpointPrepared(context), ByteLimit(524288)).value
proc cycle(source: PreparedCurrentChainUpdate, expected: seq[byte]) =
  ## Retire captured bytes, copied aliases, projections and exported independent buffers every cycle.
  let captured = captureCurrentUpdateCheckpoint(source, ByteLimit(524288)).value
  let copy = captured
  assert copy.copyCurrentCheckpoint(ByteLimit(524288)).value == expected
  assert copy.currentCheckpointSource.value.ready
proc main() {.raises.} =
  ## Genuine signed current fixtures establish producer authority before serialization qualification begins.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for i in 0..<raw.len: report[i] = byte(raw[i])
  let context = currentChainFixture(decodeOwnedReport(report, 2).value, available = true)
  let prepared = currentCheckpointPrepared(context)
  let unfinalized = currentCheckpointPrepared(context, finalized = false)
  let outside = detached(context)
  let expected = encodeFullCheckpoint(context.source.currentConsensusState.value, ByteLimit(524288)).value
  fail(1)
  assert captureCurrentUpdateCheckpoint(default(PreparedCurrentChainUpdate), ByteLimit(
      524288)).error == CurrentCheckpointError.InvalidUpdate
  assert default(CurrentUpdateCheckpoint).currentCheckpointInfo.error ==
      CurrentCheckpointError.Uninitialized
  assert default(CurrentUpdateCheckpoint).currentCheckpointFinalized.error ==
      CurrentCheckpointError.Uninitialized
  let captured = captureCurrentUpdateCheckpoint(prepared, ByteLimit(524288)).value
  let info = captured.currentCheckpointInfo.value
  assert array[32, byte](info.posterior.root) == array[32, byte](
      prepared.currentUpdateState.commitment.root)
  assert array[32, byte](info.prior) == array[32, byte](context.parent.value.stateRoot)
  assert array[32, byte](info.prior) != array[32, byte](info.posterior.root)
  assert array[32, byte](info.child) == array[32, byte](prepared.currentUpdateChild.blockHash)
  assert array[32, byte](info.parent) == array[32, byte](context.parent.value.blockHash)
  assert captured.copyCurrentCheckpoint(ByteLimit(info.wireBytes)).value == expected
  assert outside.copyCurrentCheckpoint(ByteLimit(info.wireBytes)).value == expected
  assert sameStateSnapshot(captured.currentCheckpointSource.value.currentUpdateState,
      prepared.currentUpdateState)
  let refused = captureCurrentUpdateCheckpoint(prepared, ByteLimit(info.wireBytes-1))
  assert refused.error == CurrentCheckpointError.EncodingFailure
  assert refused.encodingError == CheckpointError.LimitExceeded
  assert captured.copyCurrentCheckpoint(ByteLimit(info.wireBytes-1)).error ==
      CurrentCheckpointError.LimitExceeded
  let parent = captured.currentCheckpointFinalized.value
  assert array[32, byte](parent) == array[32, byte](context.parent.value.blockHash)
  assert array[32, byte](parent) != array[32, byte](info.child)
  assert captureCurrentUpdateCheckpoint(unfinalized, ByteLimit(
      524288)).value.currentCheckpointFinalized.error == CurrentCheckpointError.NoFinality
  var disposable = captured.copyCurrentCheckpoint(ByteLimit(info.wireBytes)).value
  disposable[disposable.len-1] = disposable[disposable.len-1] xor 1
  assert captured.copyCurrentCheckpoint(ByteLimit(info.wireBytes)).value == expected
  assert calls() == 0
  for i in 0..<25: cycle(prepared, expected)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(prepared, expected)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_current_checkpoint", 1000, before, finalBytes)
  fail(0)
  echo "state-current-checkpoint: ok"
try:
  main()
except:
  quit(2) # Authenticated fixture/setup failure cannot qualify serialization or finality observations.
