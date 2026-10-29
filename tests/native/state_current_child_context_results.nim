# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checked default fixed child access with a genuine signed/current positive control.
import std/[assertions, cmdline, syncio]
import ../support/[accumulation_current_chain_context, current_checkpoint_context]
import ../../src/state/accumulation/current/update as accumulation_current_update
import ../../src/codec/report_owned
proc extract(update: PreparedCurrentChainUpdate) {.noinline.} =
  ## No default update grants an original child context.
  discard update.currentUpdateChildContext
proc main() {.raises.} =
  ## Positive readiness is obtained only from actual candidate completion.
  if paramStr(1) == "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    extract(currentCheckpointPrepared(currentChainFixture(decodeOwnedReport(bytes, 2).value,
        completeState = true)))
    echo "state-current-child-context-results: ok"
  else:
    extract(default(PreparedCurrentChainUpdate))
try:
  main()
except:
  quit(2) # Invalid signed setup cannot stand in for the absent-owner precondition.
