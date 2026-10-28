# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime guard probes require actual extraction/destruction defects and a nonfailing control.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/app/preparation_worker as app_preparation_worker

proc main() {.raises.} =
  ## Each invalid mode must fail before any unavailable payload or unjoined thread can escape.
  case paramStr(1)
  of "admission":
    let admission = default(PreparationAdmission)
    discard admission.value # Defaults cannot grant authority over a graph.
  of "completion":
    let completion = default(PreparationCompletion)
    discard completion.value # Defaults cannot publish a prepared candidate.
  of "current":
    let completion = default(PreparationCompletion)
    discard completion.currentValue # No current alternative exists in a default result.
  of "unclosed":
    var worker = default(PreparationWorker)
    assert worker.start(), "start for destructor contract"
    discard # Scope retirement must reject a live native borrower owner.
  else:
    var worker = default(PreparationWorker)
    assert worker.start(), "positive worker startup"
    worker.close() # Explicit join satisfies destruction without a candidate or native peer.
try:
  main() # Raised startup errors fail the positive control independently of assertion defects.
except:
  quit(2)
