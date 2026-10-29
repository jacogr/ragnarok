# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual child fixed facts preserve full profile/state/Parameters without RPC index copies before resource refusal.
# @@Verification={"arc":"state_current_child_context_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[accumulation_current_chain_context, current_checkpoint_context, arc_evidence]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/current/profile as current_profile
import ../../../src/state/store
import ../../../src/chain/[genesis, parameters]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/composition as state_composition
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Genuine signed/current preparation precedes every fixed-only observation.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Reading original child context and refusing C9 policy cannot hash.
proc verify(update: PreparedCurrentChainUpdate) =
  ## Copy-out fixed fields remain observations; changing them cannot mutate the retained real child or derived profile.
  let child = update.currentUpdateChild
  var context = update.currentUpdateChildContext
  assert sameStateSnapshot(context.state, child.stateSnapshot)
  assert array[32, byte](context.hash) == array[32, byte](child.blockHash)
  assert context.slot == child.slot and uint64(context.validators) == uint64(child.activeValidators)
  assert context.parameters.encodeParameters == child.chainParameters.encodeParameters
  let original = context.parameters
  context.parameters = default(Parameters)
  context.slot = 0
  assert update.currentUpdateChildContext.parameters.encodeParameters == original.encodeParameters
  assert update.currentUpdateChildContext.slot > 0
  let refused = captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(6),
      bytes: ByteLimit(0)))
  assert refused.error == CurrentProfileError.LimitExceeded
proc cycle(update: PreparedCurrentChainUpdate) =
  ## Fixed facts and immediate C9 extent refusal allocate no copied child indexes or payload arrays.
  assert update.currentUpdateChildContext.slot > 0
  assert captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(6),
      bytes: ByteLimit(0))).error == CurrentProfileError.LimitExceeded
proc main() {.raises.} =
  ## Ordinary and epoch selected children retain their exact original source context.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let normal = currentCheckpointPrepared(currentChainFixture(base, completeState = true))
  let rotated = currentCheckpointPrepared(currentChainFixture(base, available = true,
      rotated = true, completeState = true))
  fail(1)
  verify(normal)
  verify(rotated)
  for i in 0..<25: cycle(normal)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(normal)
  let after = getOccupiedMem()
  assert before == after and calls() == 0
  recordArcRelease("state_current_child_context", 1000, before, after)
  fail(0)
  echo "state-current-child-context: ok"
try:
  main()
except:
  quit(2) # Genuine current preparation and original fixed child identity are mandatory.
