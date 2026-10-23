# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual collected logical raw identities produce the maintained startup syntax without payload export and requalify against the exact selected original source.
import std/[assertions, syncio, envvars, cmdline, monotimes, times]
import std/posix/posix
import ../support/[collected_native_context, collected_logical_services_context,
    managed_supplied_context, current_logical_proof_context, supplied_services_context, current_namespace_refresh_context]
import ../support/current_logical_cli_context
import ../../src/app/[logical_source_export, current_logical_startup, logical_export]
import ../../src/state/accumulation_current_update
import ../../src/app/[logical_code, full_logical_proof, logical_proof, proof_query, services,
    current_block_input, proof_worker]
import ../../src/state/[code_availability, current_logical, current_state, current_globals,
    current_profile, proof_plan, planned_proof, proof_view, proof_state_import, store,
    global_snapshot, manifest,
    supplied_logical_inventory, supplied_services]
import ../../src/codec/[bounded, state_layout, state_trie, state_requests]
import ../../src/chain/[provider, genesis]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Selector/query admission remains hash-free after genuine execution and qualification finish.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe whole-selector refusal before any new primitive work.
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Scalar monotonic polling cannot observe or retire leased canonical graphs.
proc waitProof(owner: var Services) =
  ## Actual Done remains leased until exact matching collection.
  let started = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    discard pauseMicros(1000)
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(LogicalSourceExportResult[LogicalSourceExportPlan])
  if mode == "value":
    discard empty.value
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let fixture = collectedNativeFixture()
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  var path = "application-logical-source-export-chain.json"
  discard startLogicalServices(owner, fixture.fixture, path)
  defer:
    owner.close()
    discard posix.unlink(path.toCString())
  let head = array[32, byte](owner.chainView.bestBlock.value.blockHash)
  let logical = collectManagedSupplied(owner, input, fixture.fixture)
  let source = logical.currentLogicalContext.value.state
  let root = source.commitment.root
  let limits = LogicalSourceExportLimits(services: ElementLimit(2), facts: ElementLimit(128),
      perKey: ByteLimit(65536), bytes: ByteLimit(65536))
  fail(1)
  let plan = owner.planLogicalSourceExport(logical, limits).value
  let info = plan.logicalSourceExportInfo.value
  assert info.services == 2 and info.facts > 2 and info.bytes > 32 and info.copyBytes >=
      info.bytes and calls() == 0
  var exact = limits
  exact.services = ElementLimit(uint64(info.services))
  exact.facts = ElementLimit(uint64(info.facts))
  exact.bytes = ByteLimit(info.copyBytes)
  assert planLogicalSourceExport(logical, exact).error == LogicalSourceExportError.None and calls() == 0
  exact.bytes = ByteLimit(info.copyBytes-1)
  assert planLogicalSourceExport(logical, exact).error == LogicalSourceExportError.LimitExceeded and
      calls() == 0
  exact = limits
  exact.facts = ElementLimit(uint64(info.facts)-1)
  assert planLogicalSourceExport(logical, exact).error == LogicalSourceExportError.LimitExceeded and
      calls() == 0
  exact = limits
  exact.services = ElementLimit(1)
  assert planLogicalSourceExport(logical, exact).error == LogicalSourceExportError.LimitExceeded and
      calls() == 0
  exact = limits
  exact.perKey = ByteLimit(0)
  assert planLogicalSourceExport(logical, exact).error == LogicalSourceExportError.LimitExceeded and
      calls() == 0
  assert planLogicalSourceExport(default(CurrentLogicalState), limits).error ==
      LogicalSourceExportError.InvalidLogical
  assert default(LogicalSourceExportPlan).logicalSourceExportInfo.error ==
      LogicalSourceExportError.InvalidPlan
  assert executeLogicalSourceExport(default(LogicalSourceExportPlan)).error ==
      LogicalSourceExportError.InvalidPlan
  assert planLogicalSourceExport(logical, LogicalSourceExportLimits(services: ElementLimit(high(
      uint64)), facts: ElementLimit(high(uint64)), perKey: ByteLimit(high(uint64)),
      bytes: ByteLimit(high(uint64)))).error == LogicalSourceExportError.None
  let text = owner.executeLogicalSourceExport(plan).value
  assert uint64(text.len) == info.bytes and calls() == 0
  let copied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert text == logicalDeclarationText(copied) # Independent maintained test serializer supplies exact syntax/order/empty-key/length expectations.
  var changed = text
  changed[0] = 'X'
  assert executeLogicalSourceExport(plan).value ==
      text # Detached caller mutation cannot retag the source or future export.
  let declarations = decodeCurrentLogicalDeclarations(text, suppliedServicesTestLimits).value
  assert calls() == 0 # Parsing/export never hash or copy service values; the actual startup qualification below does its own admitted content work.
  fail(0)
  let retention = logical.currentLogicalViewInfo.value
  assert retention.owners <= 16 and retention.bytes <= 33554432
  let selected = logical.currentLogicalUpdate.value.currentUpdateView
  assert captureCurrentLogicalStartup(selected, declarations, logicalStartupTestLimits()).error ==
      CurrentLogicalStartupError.None
  var shortParser = suppliedServicesTestLimits
  shortParser.facts = ElementLimit(uint64(info.facts)-1)
  assert decodeCurrentLogicalDeclarations(text, shortParser).error ==
      CurrentLogicalStartupError.LimitExceeded
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == head
  owner.close() # Joined native borrowing retires before frozen declaration aliases can be copied again.
  assert executeLogicalSourceExport(plan).value == text
  echo "application-logical-source-export: ok"
try:
  main()
except:
  quit(2) # Ordinary fixture/startup refusal cannot impersonate strict extraction rejection.
