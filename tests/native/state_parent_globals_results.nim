# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Guard selected-parent global evidence with a genuine signed configured-parent positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_accumulation_current_chain_context
import ../support/state_parent_profile_context
import ../support/state_parent_globals_context
import ../../src/state/parent_globals as state_parent_globals
import ../../src/state/parent_profile as state_parent_profile
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/chain/provider as chain_provider
import ../../src/codec/report_owned as codec_report_owned
proc extract(outcome: ParentGlobalsResult[SelectedParentGlobals]) {.noinline.} =
  ## No failed/default result grants complete selected-parent globals.
  discard outcome.value
proc reason(outcome: ParentGlobalsResult[SelectedParentGlobals]) {.noinline.} =
  ## Only genuinely failed global validation grants this nested reason.
  discard outcome.globalFailure
proc profile(owner: SelectedParentGlobals) {.noinline.} =
  ## Default handles expose no original selection.
  discard owner.parentGlobalsProfile.value
proc globals(owner: SelectedParentGlobals) {.noinline.} =
  ## Default handles expose no complete globals.
  discard owner.parentGlobals.value
proc main() {.raises.} =
  ## Signed input construction belongs only to genuine initialized extraction control.
  case paramStr(1)
  of "default": extract(default(ParentGlobalsResult[SelectedParentGlobals]))
  of "invalid": extract(qualifyParentGlobals(default(SelectedParentProfile),
      parentGlobalsTestLimits))
  of "reason": reason(default(ParentGlobalsResult[SelectedParentGlobals]))
  of "profile": profile(default(SelectedParentGlobals))
  of "globals": globals(default(SelectedParentGlobals))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let original = currentChainFixture(decodeOwnedReport(bytes, 2).value,
        completeState = true).currentChainSeeded
    let selected = captureParentProfile(original, parentProfileTestLimits).value
    let completed = qualifyParentGlobals(selected, parentGlobalsTestLimits)
    extract(completed)
    profile(completed.value)
    globals(completed.value)
    echo "state-parent-globals-results: ok"
  else: quit(2) # Invalid selector does not satisfy guard evidence.
try:
  main()
except:
  quit(2) # Setup failure cannot replace strict extraction rejection.
