# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Custom HALT guests use complete signed namespaces and explicit existing code-preimage/request linkage.
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_namespace_execution_context
import ../../support/state_accumulation_execution_context
import ../../support/state_parent_profile_context
import ../../support/state_parent_globals_context
import ../../support/codec_supplied_logical_context
import ../../support/state_inventory_context
import ../../../src/state/parent_profile as state_parent_profile
import ../../../src/state/parent_globals as state_parent_globals
import ../../../src/state/parent_logical as state_parent_logical
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/inventory as state_inventory
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_accounts as codec_state_accounts
proc main() {.raises.} =
  ## No account metadata override, synthetic current update or duplicate C255/code preimage is used.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let code = namespaceHaltCode()
  let fixture = namespaceExecutionFixture(decodeOwnedReport(bytes, 2).value, code, code)
  assert fixture.source.entries.len == 34
  let prior = captureParentProfile(fixture.parent, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(prior, parentGlobalsTestLimits).value
  let services = fixture.executableNamespaceServices(prior.parentContext.value.state)
  assert services[0].requests.len == 3 and services[0].preimages.len == 3
  assert uint32(services[0].metadata.storageItems) == 8
  assert uint64(services[0].metadata.storageBytes) == 317'u64+uint64(code.len)
  assert captureLogicalParent(globals, services, suppliedLogicalTestLimits).error ==
      ParentLogicalError.None
  let current = captureCurrentProfile(fixture.update, CurrentProfileLimits(validators: ElementLimit(
      1024), bytes: ByteLimit(65536))).value
  let after = qualifyCurrentGlobals(current, parentGlobalsTestLimits).value
  let declarations = fixture.executableNamespaceServices(fixture.update.currentUpdateState)
  let state = qualifyCurrentState(after, declarations, inventoryCaptureLimits).value
  assert captureCurrentLogicalState(state, declarations, suppliedLogicalTestLimits).error ==
      CurrentLogicalError.None
  assert uint32(declarations[1].metadata.storageItems) == 8
  assert uint64(declarations[1].metadata.storageBytes) == 314'u64+uint64(code.len)
  echo "state-current-namespace-execution: ok"
try:
  main()
except:
  quit(2) # Actual custom guest/current completion and whole-map/code linkage must succeed together.
