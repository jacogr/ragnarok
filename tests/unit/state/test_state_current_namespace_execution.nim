# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Custom HALT guests use complete signed namespaces and explicit existing code-preimage/request linkage.
import std/[assertions, envvars, syncio]
import ../../support/[current_namespace_execution_context, accumulation_execution_context,
    parent_profile_context, parent_globals_context, supplied_logical_context, state_inventory_context]
import ../../../src/state/[parent_profile, parent_globals, parent_logical, current_profile,
    current_globals, current_state, current_logical, accumulation_current_update,
    supplied_logical_inventory, inventory]
import ../../../src/codec/[bounded, report_owned, state_accounts]
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
