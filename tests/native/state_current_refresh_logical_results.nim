# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict plan/stage result guards with an actual fully matched current logical positive control.
import std/[assertions, cmdline, syncio]
import ../support/current_logical_refresh_context
import ../../src/state/current_logical_refresh
import ../../src/codec/report_owned
proc planned(value: LogicalRefreshPlanResult[CurrentLogicalRefreshPlan]) {.noinline.} =
  ## No default/failed admission exposes an executable complete-current plan.
  discard value.value
proc planning(mode: string, value: LogicalRefreshPlanResult[
    CurrentLogicalRefreshPlan]) {.noinline.} =
  ## Planning reasons require their exact actual selected failed stage.
  case mode
  of "plan-phase": discard value.refusedPhase
  of "plan-profile": discard value.profileFailure
  else: discard value.globalsFailure
proc observe(mode: string, value: CurrentLogicalRefreshPlan) {.noinline.} =
  ## Default plans cannot expose successful original sources, quotas or accounting.
  case mode
  of "plan-source": discard value.logicalRefreshPlanSource.value
  of "plan-limits": discard value.logicalRefreshPlanLimits.value
  else: discard value.logicalRefreshPlanInfo.value
proc completed(value: LogicalRefreshResult) {.noinline.} =
  ## Failed/default execution exposes no complete current logical state.
  discard value.value
proc failure(mode: string, value: LogicalRefreshResult) {.noinline.} =
  ## Reconstruction/current/raw-key reasons are available only on their genuinely failed selected branch.
  case mode
  of "execution-refresh": discard value.refreshFailure
  of "execution-state": discard value.stateFailure
  else: discard value.logicalFailure
proc main() {.raises.} =
  ## Actual positive source completes full original/current matching and frozen qualification before extraction.
  case paramStr(1)
  of "plan-default": planned(default(LogicalRefreshPlanResult[CurrentLogicalRefreshPlan]))
  of "plan-phase", "plan-profile", "plan-globals": planning(paramStr(1), default(
      LogicalRefreshPlanResult[CurrentLogicalRefreshPlan]))
  of "plan-source", "plan-limits", "plan-info": observe(paramStr(1), default(CurrentLogicalRefreshPlan))
  of "execution-default": completed(default(LogicalRefreshResult))
  of "execution-invalid": completed(executeCurrentLogicalRefresh(default(
      CurrentLogicalRefreshPlan)))
  of "execution-refresh", "execution-state", "execution-logical": failure(paramStr(1), default(LogicalRefreshResult))
  else:
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let plan = namespaceLogicalRefreshPlan(decodeOwnedReport(bytes, 2).value)
    planned(plan)
    for mode in ["plan-source", "plan-limits", "plan-info"]: observe(mode, plan.value)
    completed(executeCurrentLogicalRefresh(plan.value))
    echo "state-current-refresh-logical-results: ok"
try:
  main()
except:
  quit(2) # Actual complete setup failure is not a successful guard/control verdict.
