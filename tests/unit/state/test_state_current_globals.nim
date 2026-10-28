# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine ordinary/dispute/ticket/epoch current successors qualify all sixteen globals under their original derived profiles.
# @@Verification={"arc": "state_current_globals_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_checkpoint_context
import ../../support/state_accumulation_current_chain_context
import ../../support/testing_arc_evidence
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/global_snapshot as state_global_snapshot
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_composition as codec_state_composition
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Disable hash primitives only after genuine current execution finishes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Global framing and identity projection must not rehash completed current state.
const
  projection = CurrentProfileLimits(validators: ElementLimit(1024), bytes: ByteLimit(65536))
  limits = GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(10000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))
proc verify(source: PreparedCurrentChainUpdate) =
  ## Derive exact complete extents independently from cached immutable lookups, then test exact and one-short policies.
  let profile = captureCurrentProfile(source, projection).value
  let qualified = qualifyCurrentGlobals(profile, limits)
  assert qualified.error == CurrentGlobalsError.None
  let result = qualified.value
  assert sameStateSnapshot(result.qualifiedGlobals.value.globalSource.value,
      source.currentUpdateState)
  assert sameStateSnapshot(result.qualifiedCurrentProfile.value.derivedUpdate.value.currentUpdateState,
      source.currentUpdateState)
  var maximum = 0'u64
  var total = 0'u64
  for i in 1..16:
    let size = uint64(source.currentUpdateState.lookup(chapterKey(StateChapter(uint8(
        i)))).value.byteLength)
    assert size <= uint64(limits.totalBytes)-total
    total += size
    if size > maximum: maximum = size
  assert result.qualifiedGlobals.value.globalByteLength.value == total
  let exact = GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(10000),
      maxBytes: ByteLimit(maximum)), totalBytes: ByteLimit(total))
  assert qualifyCurrentGlobals(profile, exact).error == CurrentGlobalsError.None
  var short = exact
  short.totalBytes = ByteLimit(total-1)
  let refused = qualifyCurrentGlobals(profile, short)
  assert refused.error == CurrentGlobalsError.GlobalFailure
  assert refused.globalFailure.error == GlobalStateError.LimitExceeded
  short = exact
  short.chapter.maxBytes = ByteLimit(maximum-1)
  assert qualifyCurrentGlobals(profile, short).globalFailure.error == GlobalStateError.LimitExceeded
  short = limits
  short.chapter.items = ElementLimit(0)
  let items = qualifyCurrentGlobals(profile, short)
  assert items.error == CurrentGlobalsError.GlobalFailure
  assert items.globalFailure.error == GlobalStateError.ChapterFailure
  assert items.globalFailure.chapterError == StateCompositionError.LimitExceeded
proc cycle(profile: DerivedCurrentProfile) =
  ## Retire all copied chapter storage and qualified owner aliases each cycle.
  let source = qualifyCurrentGlobals(profile, limits).value
  assert source.qualifiedGlobals.value.globalByteLength.value > 0
proc main() {.raises.} =
  ## All input fixtures execute through the existing authenticating current candidate entry point.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let plain = currentCheckpointPrepared(currentChainFixture(base))
  let assuredContext = currentChainFixture(base, available = true)
  let assured = currentCheckpointPrepared(assuredContext)
  let other = currentCheckpointPrepared(assuredContext)
  let disputed = currentCheckpointPrepared(currentChainFixture(base, available = true,
      disputed = true))
  let ticketed = currentCheckpointPrepared(currentChainFixture(base, available = true,
      ticket = true))
  let rotated = currentCheckpointPrepared(currentChainFixture(base, available = true,
      rotated = true))
  fail(1)
  assert qualifyCurrentGlobals(default(DerivedCurrentProfile), limits).error ==
      CurrentGlobalsError.InvalidProfile
  assert default(CurrentGlobalSerialization).qualifiedGlobals.error ==
      CurrentGlobalsError.Uninitialized
  assert default(CurrentGlobalSerialization).qualifiedCurrentProfile.error ==
      CurrentGlobalsError.Uninitialized
  for source in [plain, assured, disputed, ticketed, rotated]: verify(source)
  let profile = captureCurrentProfile(assured, projection).value
  let qualified = qualifyCurrentGlobals(profile, limits).value
  assert not sameStateSnapshot(qualified.qualifiedGlobals.value.globalSource.value,
      other.currentUpdateState)
  assert calls() == 0
  for i in 0..<25: cycle(profile)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(profile)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_current_globals", 1000, before, finalBytes)
  fail(0)
  echo "state-current-globals: ok"
try:
  main()
except:
  quit(2) # Authenticated fixture failure cannot qualify downstream framing or ownership.
