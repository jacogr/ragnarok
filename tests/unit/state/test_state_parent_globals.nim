# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original selected parent globals preserve source/view identity, cached exact limits and missing-chapter distinction.
# @@Verification={"arc": "state_parent_globals_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[accumulation_current_chain_context, parent_profile_context,
    parent_globals_context, arc_evidence]
import ../../../src/state/parent/[profile as parent_profile, globals as parent_globals]
import ../../../src/state/[global_snapshot, store]
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/[layout as state_layout, composition as state_composition]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Global seed qualification and copied source observations require no hashing after fixture setup.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Every original selected parent global decode must be hash-free.
proc verify(view: ChainView) =
  ## The same original configured source supplies cardinalities and all required global bytes, with explicit complete-view retention.
  let profile = captureParentProfile(view, parentProfileTestLimits).value
  let qualified = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  assert sameStateSnapshot(qualified.parentGlobals.value.globalSource.value,
      view.bestBlockContext.state)
  assert sameStateSnapshot(qualified.parentGlobalsProfile.value.parentContext.value.state,
      view.bestBlockContext.state)
  assert sameChainView(qualified.parentGlobalsProfile.value.copyParentView(
      parentProfileTestLimits.viewBytes).value, view)
  var total = 0'u64
  var maximum = 0'u64
  for i in 1..16:
    let size = uint64(view.bestBlockContext.state.lookup(chapterKey(StateChapter(uint8(
        i)))).value.byteLength)
    total+=size
    if size > maximum: maximum = size
  assert qualified.parentGlobals.value.globalByteLength.value == total
  let exact = GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(10000),
      maxBytes: ByteLimit(maximum)), totalBytes: ByteLimit(total))
  assert qualifyParentGlobals(profile, exact).error == ParentGlobalsError.None
  var short = exact
  short.totalBytes = ByteLimit(total-1)
  let refused = qualifyParentGlobals(profile, short)
  assert refused.error == ParentGlobalsError.GlobalFailure
  assert refused.globalFailure.error == GlobalStateError.LimitExceeded
  short = exact
  short.chapter.maxBytes = ByteLimit(maximum-1)
  assert qualifyParentGlobals(profile, short).globalFailure.error == GlobalStateError.LimitExceeded
proc cycle(profile: SelectedParentProfile) =
  ## Retire all decoded chapter owners and retained original selected-view aliases every cycle.
  let qualified = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  assert qualified.parentGlobals.value.globalByteLength.value > 0
proc main() {.raises.} =
  ## Complete authored signed parent modes and legacy missing-C16 control preserve their original maps without repair.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let ordinary = currentChainFixture(base, completeState = true)
  let views = [genesisView(ordinary.parent), ordinary.currentChainSeeded,
    currentChainFixture(base, available = true, disputed = true,
        completeState = true).currentChainSeeded,
    currentChainFixture(base, available = true, ticket = true,
        completeState = true).currentChainSeeded,
    currentChainFixture(base, available = true, rotated = true,
        completeState = true).currentChainSeeded]
  let legacy = currentChainFixture(base)
  let legacyProfile = captureParentProfile(legacy.currentChainSeeded, parentProfileTestLimits).value
  let profile = captureParentProfile(ordinary.currentChainSeeded, parentProfileTestLimits).value
  fail(1)
  for view in views: verify(view)
  let missing = qualifyParentGlobals(legacyProfile, parentGlobalsTestLimits)
  assert missing.error == ParentGlobalsError.GlobalFailure
  assert missing.globalFailure.error == GlobalStateError.MissingChapter
  assert qualifyParentGlobals(default(SelectedParentProfile), parentGlobalsTestLimits).error ==
      ParentGlobalsError.InvalidProfile
  assert default(SelectedParentGlobals).parentGlobals.error == ParentGlobalsError.Uninitialized
  assert default(SelectedParentGlobals).parentGlobalsProfile.error ==
      ParentGlobalsError.Uninitialized
  assert calls() == 0
  for i in 0..<25: cycle(profile)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(profile)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_parent_globals", 1000, before, finalBytes)
  fail(0)
  echo "state-parent-globals: ok"
try:
  main()
except:
  quit(2) # Setup failures cannot qualify original selected parent serialization.
