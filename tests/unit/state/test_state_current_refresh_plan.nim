# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen actual successor copy admission is exact, independently bounded and hash-free before any payload allocation/decode.
# @@Verification={"arc":"state_current_refresh_plan_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_refresh_context, arc_evidence]
import ../../../src/state/current/refresh/plan as current_refresh_plan
import ../../../src/state/current/request_keys as current_request_keys
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/composition as state_composition
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Complete actual source/key derivation precedes hash-free planning observations.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Fixed inventory and actual cached extent planning invoke no primitive.
proc cycle(source: CurrentRequestKeys) =
  ## Retire frozen fixed plans and source aliases without copying payloads.
  assert planCurrentRefresh(source, currentRefreshTestLimits).value.refreshPlanInfo.value.requests == 4
proc refuse(source: CurrentRequestKeys, limits: CurrentRefreshLimits,
    phase: CurrentRefreshRefusal) =
  ## Original policy boundary remains guarded and typed for every one-short refusal.
  let result = planCurrentRefresh(source, limits)
  assert result.error == CurrentRefreshPlanError.LimitExceeded and result.refusedPhase == phase
proc main() {.raises.} =
  ## Two original services have four storage/preimage/request rows and actual same-identity successor values.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let source = namespaceRefreshKeys(decodeOwnedReport(bytes, 2).value)
  fail(1)
  var limits = currentRefreshTestLimits
  let plan = planCurrentRefresh(source, limits).value
  let info = plan.refreshPlanInfo.value
  let expected = uint64(2*sizeof(StateService)+4*sizeof(StateStorageItem)+4*sizeof(
      StatePreimageItem)+4*sizeof(StateRequestItem)+9)
  assert info.services == 2 and info.facts == 14 and info.checks == 14 and info.requests == 4
  assert info.bytes == expected and info.wireBytes == 230
  assert info.rawKeyBytes == 3 and info.storageBytes == 2 and info.preimageBytes == 4
  limits.projection.bytes = ByteLimit(expected)
  assert planCurrentRefresh(source, limits).error == CurrentRefreshPlanError.None
  var short = limits
  short.projection.services = ElementLimit(1)
  refuse(source, short, CurrentRefreshRefusal.Projection)
  short = limits
  short.projection.facts = ElementLimit(13)
  refuse(source, short, CurrentRefreshRefusal.Projection)
  short = limits
  short.projection.bytes = ByteLimit(expected-1)
  refuse(source, short, CurrentRefreshRefusal.Projection)
  short = limits
  short.projection.perValue = ByteLimit(2)
  refuse(source, short, CurrentRefreshRefusal.Projection)
  short = limits
  short.checks = ElementLimit(13)
  refuse(source, short, CurrentRefreshRefusal.Planning)
  short = limits
  short.wireBytes = ByteLimit(229)
  refuse(source, short, CurrentRefreshRefusal.Wire)
  var copied = plan.refreshPlanLimits.value
  copied.checks = ElementLimit(0)
  assert uint64(plan.refreshPlanLimits.value.checks) == 14
  var observation = plan.refreshPlanInfo.value
  observation.bytes = 0
  assert plan.refreshPlanInfo.value.bytes == expected
  assert planCurrentRefresh(default(CurrentRequestKeys), limits).error ==
      CurrentRefreshPlanError.InvalidSource
  assert calls() == 0
  for i in 0..<25: cycle(source)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source)
  let after = getOccupiedMem()
  assert before == after and calls() == 0
  recordArcRelease("state_current_refresh_plan", 1000, before, after)
  fail(0)
  echo "state-current-refresh-plan: ok"
try:
  main()
except:
  quit(2) # Real source and complete admission are mandatory for frozen-plan evidence.
