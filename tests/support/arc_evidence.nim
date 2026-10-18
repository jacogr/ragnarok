# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only numeric observations: ownership assertions remain in the calling Nim suite.
##
## Exposes recordArcRelease to write per-suite allocation observations for the verification
## harness.

import std/[envvars, syncio, assertions]

# Write copied live-allocation measurements after the caller's isolated release workload.
# A bare Hastur invocation may omit the evidence directory; the supported launcher supplies it.
proc recordArcRelease*(name: string, cycles, before, after: int, schemas = 0) =
  let directory = getEnv("RAGNAROK_TEST_EVIDENCE")
  if directory.len > 0:
    # Only trusted test labels select a filename; no protocol or foreign input reaches this helper.
    var data = "{\"cycles\":" & $cycles & ",\"occupied_before\":" & $before &
        ",\"occupied_after\":" & $after
    if schemas > 0:
      # The five-schema snapshot workload retains its historical report field.
      data.add ",\"schemas\":" & $schemas
    data.add "}\n"
    try:
      # Reporting failure must fail the native test instead of leaving an old observation usable.
      writeFile(directory & "/" & name & ".json", data)
    except:
      # Nimony requires explicit handling of fallible file I/O; test evidence cannot be silently lost.
      assert false, "ARC evidence write failed"
