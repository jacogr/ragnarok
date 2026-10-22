# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Guard current logical parent/source extraction with a genuine signed complete successor positive control.
import std/[assertions, cmdline, syncio]
import ../support/[current_checkpoint_context, current_state_context, current_typed_context,
    accumulation_current_chain_context, supplied_logical_context]
import ../../src/state/[current_logical, current_state, supplied_logical_inventory, inventory, manifest]
import ../../src/codec/report_owned
proc extract(outcome: CurrentLogicalResult[CurrentLogicalState]) {.noinline.} =
  ## Failed/default results grant no logical owner.
  discard outcome.value
proc reason(outcome: CurrentLogicalResult[CurrentLogicalState]) {.noinline.} =
  ## Only actual failed capture grants its nested reason.
  discard outcome.logicalFailure
proc source(owner: CurrentLogicalState) {.noinline.} =
  ## Default owners grant no current parameter/producer provenance.
  discard owner.currentLogicalSource.value
proc logical(owner: CurrentLogicalState) {.noinline.} =
  ## Default owners grant no supplied raw-key owner.
  discard owner.currentLogicalInventory.value
proc main() {.raises.} =
  ## Fixture I/O is outside strict negative guard verdicts.
  case paramStr(1)
  of "default": extract(default(CurrentLogicalResult[CurrentLogicalState]))
  of "invalid": extract(captureCurrentLogicalState(default(CurrentStateSerialization), [],
      suppliedLogicalTestLimits))
  of "reason": reason(default(CurrentLogicalResult[CurrentLogicalState]))
  of "source": source(default(CurrentLogicalState))
  of "logical": logical(default(CurrentLogicalState))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let qualified = currentQualifiedState(currentCheckpointPrepared(currentChainFixture(
        decodeOwnedReport(bytes, 2).value, available = true, completeState = true)))
    let services = currentSuppliedServices(qualified.currentStateInventory.value.inventorySource.value.manifestSource.value)
    let result = captureCurrentLogicalState(qualified, services, suppliedLogicalTestLimits)
    extract(result)
    source(result.value)
    logical(result.value)
    echo "state-current-logical-results: ok"
  else: quit(2) # Invalid selectors do not qualify guards.
try:
  main()
except:
  quit(2) # Setup failure cannot replace runtime guard evidence.
