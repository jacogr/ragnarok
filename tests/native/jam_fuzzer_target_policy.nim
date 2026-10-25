# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Materialize only explicit native resource policy for process-level fuzzer interface checks.
import std/[cmdline, syncio]
import ../support/[trace_check_context, fuzz_guest_replay_context]
import ../../src/app/current_download_policy
proc main() {.raises.} =
  ## Parameters and all expected state/block bytes remain independently calculated by the Python test reference.
  var policy = traceCheckTestPolicy()
  # Resource policy covers the exact known queue/code envelopes; GP parameters retain each source profile.
  policy.candidate = fuzzGuestReplayConfig().candidate
  writeFile(paramStr(1), encodeCurrentDownloadPolicy(policy))
try:
  main() # A failed policy write cannot leave a successful E2E precondition.
except:
  quit(2)
