# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict frozen plan/default result guards with a genuine nonempty actual successor control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_current_refresh_context
import ../../src/state/current_refresh_plan as state_current_refresh_plan
import ../../src/codec/report_owned as codec_report_owned
proc extract(value: CurrentRefreshPlanResult[CurrentRefreshPlan]) {.noinline.} =
  ## No default/refused result carries an executable admitted plan.
  discard value.value
proc reason(value: CurrentRefreshPlanResult[CurrentRefreshPlan]) {.noinline.} =
  ## Defaults cannot fabricate a resource refusal boundary.
  discard value.refusedPhase
proc observe(mode: string, value: CurrentRefreshPlan) {.noinline.} =
  ## Default plans expose no original source, frozen policies or successful copy accounting.
  case mode
  of "source": discard value.refreshPlanSource.value
  of "limits": discard value.refreshPlanLimits.value
  else: discard value.refreshPlanInfo.value
proc main() {.raises.} =
  ## Positive control derives bounded cached keys and the plan from actual original/genuine update matching.
  case paramStr(1)
  of "default": extract(default(CurrentRefreshPlanResult[CurrentRefreshPlan]))
  of "reason": reason(default(CurrentRefreshPlanResult[CurrentRefreshPlan]))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let plan = planCurrentRefresh(namespaceRefreshKeys(decodeOwnedReport(bytes, 2).value), currentRefreshTestLimits)
    extract(plan)
    for mode in ["source", "limits", "info"]: observe(mode, plan.value)
    echo "state-current-refresh-plan-results: ok"
  else: observe(paramStr(1), default(CurrentRefreshPlan))
try:
  main()
except:
  quit(2) # Actual source qualification failures cannot satisfy a plan/result guard.
