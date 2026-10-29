# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Materialize only explicit native resource policy for process-level fuzzer interface checks.
import std/[assertions, cmdline, syncio]
import ../support/[trace_check_context, fuzz_guest_replay_context, fuzz_full_replay_context]
import ../../src/app/current/download/policy as current_download_policy
proc main() {.raises.} =
  ## Parameters and all expected state/block bytes remain independently calculated by the Python test reference.
  var policy = traceCheckTestPolicy()
  # Resource policy covers the exact known queue/code envelopes; GP parameters retain each source profile.
  if paramCount() == 2:
    assert paramStr(2) in ["full", "fuzz"] # Only explicit known profiles select geometry.
    if paramStr(2) == "fuzz":
      policy.candidate = fuzzNetworkReplayConfig().candidate
    else:
      policy.candidate = fuzzFullReplayConfig().candidate
  else:
    assert paramCount() == 1
    policy.candidate = fuzzGuestReplayConfig().candidate
  writeFile(paramStr(1), encodeCurrentDownloadPolicy(policy))
try:
  main() # A failed policy write cannot leave a successful E2E precondition.
except:
  quit(2)
