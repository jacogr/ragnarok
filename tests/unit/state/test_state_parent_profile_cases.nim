# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete selected parent profile refusals, independent previous population and detached full-view/context ownership.
# @@Verification={"arc": "state_parent_profile_cases_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[accumulation_current_chain_context, current_checkpoint_context,
    parent_profile_context, arc_evidence]
import ../../../src/state/[parent_profile, store, accumulation_current_update]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[bounded, report_owned, state_layout, state_trie, state_safrole,
    state_consensus, state_composition, assurances, header]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## All changed maps and genuine transitions are constructed before hash-free qualification begins.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Malformed/absent C9 refusal and independent population decoding hash nothing.
proc altered(context: CurrentChainFixture, mode: int): ChainView =
  ## Structural negative sources recompute complete maps honestly; they are not signed-valid transitions or replacement execution certificates.
  let original = context.parent.value
  let key = chapterKey(StateChapter(9))
  var raw = original.stateSnapshot.lookup(key).value.bytes
  if mode == 1:
    raw = @[] # Present-empty C9 is malformed rather than absent.
  elif mode == 2:
    raw.add(byte(0)) # Valid prefix plus suffix must refuse exact-consumption qualification.
  elif mode == 3:
    let config = ValidatorStateConfig(cores: CoreCount(3), validators: ElementLimit(1024),
        maxBytes: ByteLimit(65536))
    let roster = decodeStateValidators(raw, config).value.value
    var rows: seq[StateValidator] = @[]
    for i in 0..<9:
      rows.add(roster.validatorAt(StateValidatorIndex(uint64(i mod 6))).value)
    raw = validatorEntry(ValidatorChapter.Previous, rows,
        config).value.value # Previous9 is independent of captured active6.
  var entries: seq[StateEntry] = @[]
  for entry in context.entries:
    if array[31, byte](entry.key) == array[31, byte](key):
      if mode != 0: entries.add(StateEntry(key: key,
          value: raw)) # Missing mode removes only the original C9 entry.
    else:
      entries.add(entry)
  let state = newStateStore(entries, genesisStoreLimits()).value.snapshot.value
  var parameters = original.chainParameters
  if mode == 3:
    var wire = parameters.encodeParameters
    wire[24] = 3 # Explicit third core admits independently authored previous9; global validity is outside this structural witness.
    parameters = decodeParameters(wire).value
  let captured = captureBlockSnapshot(currentChainBytes(original.header), state, parameters)
  assert captured.error == GenesisError.None
  genesisView(captured).finalizeView(captured.value.blockHash).value
proc cycle(view: ChainView, previous: uint64) =
  ## Retire all original-view/index copies and independent previous9 decode arrays each cycle.
  let captured = captureParentProfile(view, parentProfileTestLimits).value
  assert uint64(captured.parentStateProfile.value.previous) == previous
proc main() {.raises.} =
  ## Preserve full genuine history/finality separately from explicitly constructed structural negative-map witnesses.
  let text = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](text.len)
  for i in 0..<text.len: bytes[i] = byte(text[i])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, completeState = true)
  let original = context.currentChainSeeded
  let missing = altered(context, 0)
  let malformed = altered(context, 1)
  let trailing = altered(context, 2)
  let nine = altered(context, 3)
  let rebuilt = altered(context, 4)
  let update = currentCheckpointPrepared(context)
  let full = update.currentUpdateView
  assert full.retainedCount == 2
  fail(1)
  assert captureParentProfile(missing, parentProfileTestLimits).error ==
      ParentProfileError.MissingPrevious
  let bad = captureParentProfile(malformed, parentProfileTestLimits)
  assert bad.error == ParentProfileError.PreviousFailure
  assert bad.previousError == StateComponentError.Truncated
  assert captureParentProfile(trailing, parentProfileTestLimits).error ==
      ParentProfileError.TrailingPrevious
  let independent = captureParentProfile(nine, parentProfileTestLimits).value
  assert uint64(independent.parentStateProfile.value.current) == 6
  assert uint64(independent.parentStateProfile.value.previous) == 9
  var short = parentProfileTestLimits
  short.validators = ElementLimit(8)
  assert captureParentProfile(nine, short).previousError == StateComponentError.LimitExceeded
  let selected = captureParentProfile(full, parentProfileTestLimits).value
  let info = selected.parentProfileInfo.value
  assert info.view.history == 2 and info.view.owners == 3 and info.view.finalized
  short = parentProfileTestLimits
  short.blocks = ElementLimit(2)
  assert captureParentProfile(full, short).error == ParentProfileError.LimitExceeded
  var copied = selected.copyParentView(ByteLimit(info.view.bytes)).value
  assert sameChainView(copied, full)
  copied = copied.finalizeView(full.bestBlockContext.hash).value
  assert not sameChainView(copied, full)
  assert sameChainView(selected.copyParentView(ByteLimit(info.view.bytes)).value, full)
  var facts = selected.parentContext.value
  facts.state = rebuilt.bestBlockContext.state
  facts.parameters = default(Parameters)
  facts.slot = 0
  assert sameStateSnapshot(selected.parentContext.value.state, full.bestBlockContext.state)
  assert selected.parentContext.value.parameters.valid and selected.parentContext.value.slot == 2
  var cardinalities = independent.parentStateProfile.value
  cardinalities.previous = ValidatorCount(0)
  assert not cardinalities.valid and uint64(independent.parentStateProfile.value.previous) == 9
  var observation = selected.parentProfileInfo.value
  observation.view.bytes = 0
  observation.view.owners = 0
  assert selected.copyParentView(ByteLimit(0)).error == ParentProfileError.LimitExceeded
  let first = captureParentProfile(original, parentProfileTestLimits).value
  let second = captureParentProfile(rebuilt, parentProfileTestLimits).value
  assert array[32, byte](first.parentContext.value.state.commitment.root) == array[32, byte](
      second.parentContext.value.state.commitment.root)
  assert not sameStateSnapshot(first.parentContext.value.state, second.parentContext.value.state)
  assert not sameChainView(first.copyParentView(parentProfileTestLimits.viewBytes).value,
      second.copyParentView(parentProfileTestLimits.viewBytes).value)
  assert calls() == 0
  for i in 0..<25:
    cycle(nine, 9)
    cycle(full, 6)
  let before = getOccupiedMem()
  for i in 0..<1000:
    cycle(nine, 9)
    cycle(full, 6)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_parent_profile_cases", 1000, before, finalBytes)
  fail(0)
  echo "state-parent-profile-cases: ok"
try:
  main()
except:
  quit(2) # Failed structural source creation cannot qualify profile/identity/refusal evidence.
