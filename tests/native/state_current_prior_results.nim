# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checked default projections and genuine signed original/posterior positive controls.
import std/[assertions, cmdline, syncio]
import ../support/[accumulation_current_chain_context, current_checkpoint_context]
import ../../src/state/accumulation/current/update as accumulation_current_update
import ../../src/chain/provider
import ../../src/codec/report_owned
proc extract(mode: string, update: PreparedCurrentChainUpdate) {.noinline.} =
  ## Dynamic noinline calls preserve actual runtime precondition evidence.
  case mode
  of "state": discard update.currentUpdatePriorState
  of "view": discard update.currentUpdatePriorView
  of "prior-info": discard update.currentUpdatePriorViewInfo
  else: discard update.currentUpdateViewInfo
proc main() {.raises.} =
  ## Positive control retains actual full state/view completion rather than manufacturing readiness.
  if paramStr(1) == "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let update = currentCheckpointPrepared(currentChainFixture(decodeOwnedReport(bytes, 2).value,
        completeState = true))
    for name in ["state", "view", "prior-info", "view-info"]: extract(name, update)
    echo "state-current-prior-results: ok"
  else:
    extract(paramStr(1), default(PreparedCurrentChainUpdate))
try:
  main()
except:
  quit(2) # Setup failures cannot satisfy projection precondition diagnostics.
