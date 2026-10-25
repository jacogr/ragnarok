# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Materialize only explicit native resource policy for process-level fuzzer interface checks.
import std/[cmdline, syncio]
import ../support/trace_check_context
import ../../src/app/current_download_policy
proc main() {.raises.} =
  ## Parameters and all expected state/block bytes remain independently calculated by the Python test reference.
  writeFile(paramStr(1), encodeCurrentDownloadPolicy(traceCheckTestPolicy()))
try:
  main() # A failed policy write cannot leave a successful E2E precondition.
except:
  quit(2)
