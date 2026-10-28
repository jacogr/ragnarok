# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict guarded reconstruction result alternatives with actual original/current positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_current_refresh_context
import ../../src/state/current_refresh as state_current_refresh
import ../../src/state/current_refresh_plan as state_current_refresh_plan
import ../../src/codec/report_owned as codec_report_owned
proc extract(value: CurrentRefreshResult) {.noinline.} =
  ## No default or refused frozen-plan execution exposes partial mutable declarations.
  discard value.value
proc metadata(value: CurrentRefreshResult) {.noinline.} =
  ## Only actual failed metadata decoding exposes its original codec reason.
  discard value.metadataError
proc request(value: CurrentRefreshResult) {.noinline.} =
  ## Only actual failed request decoding exposes its original tagged-history reason.
  discard value.requestError
proc main() {.raises.} =
  ## Genuine actual source/key/plan preparation must succeed before a positive result can be observed.
  case paramStr(1)
  of "default": extract(default(CurrentRefreshResult))
  of "invalid": extract(executeCurrentRefresh(default(CurrentRefreshPlan)))
  of "metadata": metadata(default(CurrentRefreshResult))
  of "request": request(default(CurrentRefreshResult))
  else:
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let plan = planCurrentRefresh(namespaceRefreshKeys(decodeOwnedReport(bytes, 2).value),
        currentRefreshTestLimits).value
    extract(executeCurrentRefresh(plan))
    echo "state-current-refresh-execution-results: ok"
try:
  main()
except:
  quit(2) # Actual original/current setup failure cannot become a result guard verdict.
