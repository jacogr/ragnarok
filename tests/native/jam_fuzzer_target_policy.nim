# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Materialize only explicit native resource policy for process-level fuzzer interface checks.
import std/[cmdline, syncio]
import ../support/trace_check_context
import ../../src/app/current_download_policy
import ../../src/codec/bounded
proc main() {.raises.} =
  ## Parameters and all expected state/block bytes remain independently calculated by the Python test reference.
  var policy = traceCheckTestPolicy()
  policy.candidate.completion.composition.validators.projection.assurances = ElementLimit(6)
  policy.candidate.completion.composition.validators.projection.reporters = ElementLimit(6)
  policy.candidate.completion.composition.validators.projection.comparisons = ElementLimit(36)
  policy.candidate.completion.composition.activity.available = ElementLimit(2)
  policy.candidate.completion.composition.activity.assurances = ElementLimit(6)
  writeFile(paramStr(1), encodeCurrentDownloadPolicy(policy))
try:
  main() # A failed policy write cannot leave a successful E2E precondition.
except:
  quit(2)
