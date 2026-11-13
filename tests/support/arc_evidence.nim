# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Check and record test-owned snapshots of the calling thread's occupied memory.

import std/[envvars, syncio, assertions]

proc assertArcRelease*(before, after: int, context: string) =
  ## Compare the caller's snapshots exactly and report both counts on failure.
  ## The allocator can defer accounting for cross-thread frees, so these counts
  ## alone cannot establish a worker leak.
  assert before == after, context & ": occupied bytes before=" & $before & " after=" & $after

proc recordArcRelease*(name: string, cycles, before, after: int, schemas = 0) =
  ## Write copied live-allocation measurements after the caller's isolated release workload.
  ## A bare Hastur invocation may omit the evidence directory; the supported launcher supplies it.
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
