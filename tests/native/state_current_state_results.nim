# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict result and source guards use a real signed complete successor as positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_current_checkpoint_context
import ../support/state_current_typed_context
import ../support/state_accumulation_current_chain_context
import ../support/state_inventory_context
import ../../src/state/current_state as state_current_state
import ../../src/state/current_globals as state_current_globals
import ../../src/state/current_profile as state_current_profile
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/state_composition as codec_state_composition
proc extract(outcome: CurrentStateResult[CurrentStateSerialization]) {.noinline.} =
  ## Failed/default alternatives cannot expose payloads.
  discard outcome.value
proc manifest(outcome: CurrentStateResult[CurrentStateSerialization]) {.noinline.} =
  ## Only genuinely failed matching supplies this reason.
  discard outcome.manifestFailure
proc inventory(outcome: CurrentStateResult[CurrentStateSerialization]) {.noinline.} =
  ## Only genuinely failed fact capture supplies this reason.
  discard outcome.inventoryFailure
proc globals(source: CurrentStateSerialization) {.noinline.} =
  ## Default wrappers cannot grant producer identity.
  discard source.currentStateGlobals.value
proc facts(source: CurrentStateSerialization) {.noinline.} =
  ## Default wrappers cannot grant logical inventory.
  discard source.currentStateInventory.value
proc main() {.raises.} =
  ## Trusted fixture I/O is separate from intentional guard failures.
  case paramStr(1)
  of "default": extract(default(CurrentStateResult[CurrentStateSerialization]))
  of "invalid": extract(qualifyCurrentState(default(CurrentGlobalSerialization), [],
      inventoryCaptureLimits))
  of "manifest": manifest(default(CurrentStateResult[CurrentStateSerialization]))
  of "inventory": inventory(default(CurrentStateResult[CurrentStateSerialization]))
  of "globals": globals(default(CurrentStateSerialization))
  of "facts": facts(default(CurrentStateSerialization))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let source = currentCheckpointPrepared(currentChainFixture(decodeOwnedReport(bytes, 2).value,
        available = true, completeState = true))
    let profile = captureCurrentProfile(source, CurrentProfileLimits(validators: ElementLimit(1024),
        bytes: ByteLimit(65536))).value
    let qualified = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
        items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
    let result = qualifyCurrentState(qualified, currentSuppliedServices(source.currentUpdateState), inventoryCaptureLimits)
    extract(result)
    globals(result.value)
    facts(result.value)
    echo "state-current-state-results: ok"
  else: quit(2) # Invalid selector cannot satisfy a failure witness.
try:
  main()
except:
  quit(2) # Setup failure cannot stand in for guarded extraction.
