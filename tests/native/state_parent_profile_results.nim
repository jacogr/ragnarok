# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/source/reason/view guards use an actual signed selected parent as genuine positive control.
import std/[assertions, cmdline, syncio]
import ../support/[accumulation_current_chain_context, parent_profile_context]
import ../../src/state/parent_profile
import ../../src/chain/[provider, genesis]
import ../../src/codec/[bounded, report_owned]
proc extract(outcome: ParentProfileResult[SelectedParentProfile]) {.noinline.} =
  ## No default/failed result grants a configured selected parent.
  discard outcome.value
proc reason(outcome: ParentProfileResult[SelectedParentProfile]) {.noinline.} =
  ## Only an actual previous-roster refusal grants its nested reason.
  discard outcome.previousError
proc profile(owner: SelectedParentProfile) {.noinline.} =
  ## Default owners grant no selected cardinalities.
  discard owner.parentStateProfile.value
proc context(owner: SelectedParentProfile) {.noinline.} =
  ## Default owners grant no selected physical/configuration facts.
  discard owner.parentContext.value
proc info(owner: SelectedParentProfile) {.noinline.} =
  ## Default owners grant no successful copied extent observations.
  discard owner.parentProfileInfo.value
proc view(owner: SelectedParentProfile) {.noinline.} =
  ## Default owners grant no original full view.
  discard owner.copyParentView(ByteLimit(high(uint64))).value
proc rawContext(original: ChainView) {.noinline.} =
  ## The allocation-free head context projection still requires a selected head.
  discard original.bestBlockContext
proc rawRetention(original: BlockSnapshotResult) {.noinline.} =
  ## Fixed index observations still require genuine successful structural capture.
  discard original.blockSnapshotRetention
proc main() {.raises.} =
  ## Positive setup runs original signed parent preparation, never a fabricated current update.
  case paramStr(1)
  of "raw-context": rawContext(genesisView(unavailableGenesis()))
  of "raw-retention": rawRetention(default(BlockSnapshotResult))
  of "default": extract(default(ParentProfileResult[SelectedParentProfile]))
  of "missing": extract(captureParentProfile(genesisView(unavailableGenesis()),
      parentProfileTestLimits))
  of "reason": reason(default(ParentProfileResult[SelectedParentProfile]))
  of "profile": profile(default(SelectedParentProfile))
  of "context": context(default(SelectedParentProfile))
  of "info": info(default(SelectedParentProfile))
  of "view": view(default(SelectedParentProfile))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let original = currentChainFixture(decodeOwnedReport(bytes, 2).value,
        completeState = true).currentChainSeeded
    let captured = captureParentProfile(original, parentProfileTestLimits)
    extract(captured)
    profile(captured.value)
    context(captured.value)
    info(captured.value)
    view(captured.value)
    echo "state-parent-profile-results: ok"
  else: quit(2) # Unknown selectors cannot qualify guard enforcement.
try:
  main()
except:
  quit(2) # Setup failures cannot replace exact contract evidence.
