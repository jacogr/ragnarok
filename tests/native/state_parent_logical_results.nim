# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict selected logical-parent result/source guards retain real signed complete-parent positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_accumulation_current_chain_context
import ../support/state_parent_logical_context
import ../support/codec_supplied_logical_context
import ../../src/state/parent_logical as state_parent_logical
import ../../src/state/parent_globals as state_parent_globals
import ../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../src/codec/report_owned as codec_report_owned
proc extract(outcome: ParentLogicalResult[SelectedLogicalParent]) {.noinline.} =
  ## Failed/default seed grants no logical parent.
  discard outcome.value
proc manifest(outcome: ParentLogicalResult[SelectedLogicalParent]) {.noinline.} =
  ## Only failed exact-map matching grants this reason.
  discard outcome.manifestFailure
proc logical(outcome: ParentLogicalResult[SelectedLogicalParent]) {.noinline.} =
  ## Only failed raw-key capture grants this reason.
  discard outcome.logicalFailure
proc source(owner: SelectedLogicalParent) {.noinline.} =
  ## Default seed grants no original selected view/profile/global evidence.
  discard owner.logicalParentGlobals.value
proc inventory(owner: SelectedLogicalParent) {.noinline.} =
  ## Default seed grants no complete supplied identities/raw keys.
  discard owner.logicalParentInventory.value
proc main() {.raises.} =
  ## Actual signed parent construction is confined to genuine initialized extraction control.
  case paramStr(1)
  of "default": extract(default(ParentLogicalResult[SelectedLogicalParent]))
  of "invalid": extract(captureLogicalParent(default(SelectedParentGlobals), [],
      suppliedLogicalTestLimits))
  of "manifest": manifest(default(ParentLogicalResult[SelectedLogicalParent]))
  of "logical": logical(default(ParentLogicalResult[SelectedLogicalParent]))
  of "source": source(default(SelectedLogicalParent))
  of "inventory": inventory(default(SelectedLogicalParent))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let completed = selectedLogicalParent(currentChainFixture(decodeOwnedReport(bytes, 2).value,
        completeState = true).currentChainSeeded)
    extract(completed)
    let owner = completed.value
    source(owner)
    inventory(owner)
    echo "state-parent-logical-results: ok"
  else: quit(2) # Invalid selectors cannot qualify guards.
try:
  main()
except:
  quit(2) # Setup failure cannot replace strict result/source rejection.
