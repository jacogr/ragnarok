# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current capsule payload guards retain an actually prepared current producer as positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_current_checkpoint_context
import ../support/state_accumulation_current_chain_context
import ../../src/state/current_checkpoint as state_current_checkpoint
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
proc extract(outcome: CurrentCheckpointResult[CurrentUpdateCheckpoint]) {.noinline.} =
  ## Default/source/encoding failure grants no retained capsule.
  discard outcome.value
proc reason(outcome: CurrentCheckpointResult[CurrentUpdateCheckpoint]) {.noinline.} =
  ## Wrong alternatives grant no encoding cause.
  discard outcome.encodingError
proc info(source: CurrentUpdateCheckpoint) {.noinline.} =
  ## A default owner grants no copied identities.
  discard source.currentCheckpointInfo.value
proc bytes(source: CurrentUpdateCheckpoint) {.noinline.} =
  ## A default owner grants no exported bytes.
  discard source.copyCurrentCheckpoint(ByteLimit(524288)).value
proc finality(source: CurrentUpdateCheckpoint) {.noinline.} =
  ## A default owner grants no finalized identity.
  discard source.currentCheckpointFinalized.value
proc origin(source: CurrentUpdateCheckpoint) {.noinline.} =
  ## A default owner grants no producer provenance.
  discard source.currentCheckpointSource.value
proc main() {.raises.} =
  ## Keep trusted positive fixture I/O inside an explicit failure boundary.
  case paramStr(1)
  of "default": extract(default(CurrentCheckpointResult[CurrentUpdateCheckpoint]))
  of "invalid": extract(captureCurrentUpdateCheckpoint(default(PreparedCurrentChainUpdate),
      ByteLimit(524288)))
  of "reason": reason(default(CurrentCheckpointResult[CurrentUpdateCheckpoint]))
  of "info": info(default(CurrentUpdateCheckpoint))
  of "bytes": bytes(default(CurrentUpdateCheckpoint))
  of "finality": finality(default(CurrentUpdateCheckpoint))
  of "origin": origin(default(CurrentUpdateCheckpoint))
  of "ok":
    let raw = readFile(paramStr(2))
    var report = newSeq[byte](raw.len)
    for i in 0..<raw.len: report[i] = byte(raw[i])
    let context = currentChainFixture(decodeOwnedReport(report, 2).value, available = true)
    let source = currentCheckpointPrepared(context)
    let result = captureCurrentUpdateCheckpoint(source, ByteLimit(524288))
    extract(result)
    assert result.value.currentCheckpointInfo.value.wireBytes > 57
    assert result.value.copyCurrentCheckpoint(ByteLimit(524288)).value.len > 57
    echo "state-current-checkpoint-results: ok"
  else: quit(2) # Unknown cases cannot count as intended guard evidence.
try:
  main()
except:
  quit(2) # Fixture failure cannot satisfy a guard or its genuine control.
