# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete selected service namespaces authenticate against an independently selected actual posterior root with bounded request hashing.
import std/assertions
import std/syncio
import std/envvars
import std/cmdline
import ../support/app_collected_native_context
import ../support/app_collected_supplied_context
import ../support/state_current_logical_proof_context
import ../../src/app/logical_service_proof as app_logical_service_proof
import ../../src/app/logical_proof as app_logical_proof
import ../../src/app/proof_query as app_proof_query
import ../../src/state/current_logical as state_current_logical
import ../../src/state/proof_plan as state_proof_plan
import ../../src/state/planned_proof as state_planned_proof
import ../../src/state/proof_view as state_proof_view
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_requests as codec_state_requests
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Fail request-key hashing only after genuine complete source qualification.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Whole key/work refusal precedes all native primitive calls.
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(LogicalServiceProofResult[LogicalServiceProof])
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.requestError
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  let limits = LogicalServiceProofLimits(services: ElementLimit(2), keys: ElementLimit(32),
      requests: ElementLimit(8), bytes: ByteLimit(4096))
  fail(1)
  var short = limits
  short.requests = ElementLimit(0)
  assert planLogicalServiceProof(logical, ServiceIndex(99), short).error ==
      LogicalServiceProofError.LimitExceeded and calls() == 0
  let rejected = planLogicalServiceProof(logical, ServiceIndex(99), limits)
  assert rejected.error == LogicalServiceProofError.KeyFailure and rejected.requestError ==
      RequestError.BackendFailure
  fail(0)
  let selected = planLogicalServiceProof(logical, ServiceIndex(99), limits).value
  let info = selected.logicalServiceProofInfo.value
  assert info.keys > 1 and info.requests > 0
  let keys = selected.logicalServiceProofKeys.value
  let queryLimits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  let response = executeProofQuery(captureLogicalProofQuery(
      selected.logicalServiceProofSource.value, keys, queryLimits).value).value
  let snapshot = logical.currentLogicalContext.value.state
  let wire = response.bytes(queryLimits.query.wireBytes).value
  let view = decodePlannedProofs(wire, keys, snapshot.commitment.root, queryLimits.query.view,
    queryLimits.query.proof, queryLimits.query.aggregate, queryLimits.query.wireBytes).value
  assert view.len == info.keys
  for i in 0..<keys.len:
    let key = keys.keyAt(i).value
    assert view.lookup(key).value.present
    assert view.lookup(key).value.bytes == snapshot.lookup(key).value.bytes
  var exact = limits
  exact.keys = ElementLimit(uint64(info.keys))
  exact.requests = ElementLimit(uint64(info.requests))
  exact.bytes = ByteLimit((uint64(info.keys)*2+uint64(info.keys) div 2)*uint64(sizeof(StateKey)))
  assert planLogicalServiceProof(logical, ServiceIndex(99), exact).error ==
      LogicalServiceProofError.None
  exact.bytes = ByteLimit((uint64(info.keys)*2+uint64(info.keys) div 2)*uint64(sizeof(StateKey))-1)
  assert planLogicalServiceProof(logical, ServiceIndex(99), exact).error ==
      LogicalServiceProofError.LimitExceeded
  assert planLogicalServiceProof(logical, ServiceIndex(123456), limits).error ==
      LogicalServiceProofError.NoService
  assert default(LogicalServiceProof).logicalServiceProofKeys.error ==
      LogicalServiceProofError.InvalidLogical
  echo "application-logical-service-proofs: ok"
try:
  main()
except:
  quit(2) # Unrelated setup or verification errors cannot impersonate selected strict failures.
