# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Selected parent capture budgets full view/index retention before hash-free same-source C9/profile decoding.
# @@Verification={"arc": "state_parent_profile_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[accumulation_current_chain_context, parent_profile_context, arc_evidence]
import ../../../src/state/[parent_profile, store]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[bounded, report_owned, state_layout, state_composition, state_accounts]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Disable hashing only after the signed parent and chain view exist.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Fixed view projections, profile decode and copy admission hash nothing.
proc cycle(view: ChainView) =
  ## Retire the captured full original view and all temporary previous-roster buffers each cycle.
  let owner = captureParentProfile(view, parentProfileTestLimits).value
  assert owner.parentStateProfile.value.valid
proc verify(view: ChainView) =
  ## Exact and one-short native descriptor/index and previous-roster policies preserve full finality/configuration.
  let observed = view.viewRetentionInfo
  let source = view.bestBlockContext
  let extent = uint64(source.state.lookup(chapterKey(StateChapter(9))).value.byteLength)
  let exact = ParentProfileLimits(blocks: ElementLimit(uint64(observed.owners)),
      validators: ElementLimit(6), viewBytes: ByteLimit(observed.bytes), previousBytes: ByteLimit(extent))
  let selected = captureParentProfile(view, exact).value
  assert selected.parentProfileInfo.value.view.bytes == observed.bytes
  assert sameStateSnapshot(selected.parentContext.value.state, source.state)
  assert sameChainView(selected.copyParentView(ByteLimit(observed.bytes)).value, view)
  assert selected.copyParentView(ByteLimit(observed.bytes-1)).error ==
      ParentProfileError.LimitExceeded
  assert selected.parentProfileInfo.value.view.finalized == (view.finalizedBlock.error ==
      GenesisError.None)
  for field in low(Parameter)..high(Parameter):
    assert selected.parentContext.value.parameters.get(field) == source.parameters.get(field)
  assert uint64(selected.parentStateProfile.value.previous) == 6
  for phase in 0..<4:
    var short = exact
    case phase
    of 0: short.blocks = ElementLimit(uint64(observed.owners-1))
    of 1: short.viewBytes = ByteLimit(observed.bytes-1)
    of 2: short.previousBytes = ByteLimit(extent-1)
    else: short.validators = ElementLimit(5)
    let refused = captureParentProfile(view, short)
    if phase == 3:
      assert refused.error == ParentProfileError.PreviousFailure
    else:
      assert refused.error == ParentProfileError.LimitExceeded
proc main() {.raises.} =
  ## Both explicitly finalized and unfinalized selected views retain the original complete signed parent.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let source = currentChainFixture(decodeOwnedReport(bytes, 2).value, completeState = true)
  let retention = source.parent.blockSnapshotRetention
  assert retention.keys == 18 and retention.services == 2
  assert retention.indexBytes == 18'u64 * uint64(sizeof(StateKey)) + 2'u64 * uint64(sizeof(ServiceIndex))
  let unfinalized = genesisView(source.parent)
  let finalized = source.currentChainSeeded
  fail(1)
  verify(unfinalized)
  verify(finalized)
  assert captureParentProfile(genesisView(unavailableGenesis()), parentProfileTestLimits).error ==
      ParentProfileError.MissingHead
  assert default(SelectedParentProfile).parentStateProfile.error == ParentProfileError.Uninitialized
  assert default(SelectedParentProfile).parentContext.error == ParentProfileError.Uninitialized
  assert default(SelectedParentProfile).parentProfileInfo.error == ParentProfileError.Uninitialized
  assert default(SelectedParentProfile).copyParentView(ByteLimit(high(uint64))).error ==
      ParentProfileError.Uninitialized
  assert calls() == 0
  for i in 0..<25: cycle(finalized)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(finalized)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_parent_profile", 1000, before, finalBytes)
  fail(0)
  echo "state-parent-profile: ok"
try:
  main()
except:
  quit(2) # Fixture failure cannot qualify selected original parent provenance.
