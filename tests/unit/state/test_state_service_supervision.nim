# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal incarnation cases prove complete-source one-hop supervisor selection and detached decision ownership.
# @@Verification={"arc": "state_service_supervision_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, service_directory_context, arc_evidence]
import ../../../src/state/service/[supervision as service_supervision,
    directory as service_directory]
import ../../../src/state/inventory
import ../../../src/codec/state/[accounts as state_accounts, composition as state_composition]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse all hashes after fixtures and complete directory construction.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Supervision decisions must use only fixed complete-source observations.
proc directory(fixture: seq[seq[byte]], services: seq[StateService]): StateServiceDirectory =
  ## Construct a real bounded source for each independently varied metadata case.
  buildStateServiceDirectory(captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value, directoryTestLimits).value
proc cycle(source: StateServiceDirectory) =
  ## Retire a successful selected-source graph and copied observation each iteration.
  let chosen = resolveServiceSupervision(source, ServiceIndex(8)).value
  assert uint32(chosen.supervisionInfo.value.effective) == 7
proc main() {.raises.} =
  ## Source fixtures preserve complete metadata provenance independently of expected selection literals.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = directory(fixture, services)
  services[0].metadata.created = AccountSlot(3)
  let recreated = directory(fixture, services)
  services = inventoryServices()
  services[1].metadata.supervisor = ServiceIndex(99)
  let absent = directory(fixture, services)
  services = inventoryServices()
  services[0].metadata.supervisorCreated = AccountSlot(3)
  let staleSelf = directory(fixture, services)
  services = inventoryServices()
  services[0].metadata.supervisor = ServiceIndex(8)
  services[0].metadata.supervisorCreated = AccountSlot(4)
  let cycleSource = directory(fixture, services)
  fail(1)
  let result = resolveServiceSupervision(source, ServiceIndex(8))
  assert result.error == ServiceSupervisionError.None
  let selected = result.value
  let info = selected.supervisionInfo.value
  assert uint32(info.service) == 8 and uint32(info.designated) == 7 and uint32(info.effective) == 7
  assert info.decision == SupervisionDecision.Designated and uint32(info.expectedCreated) == 2
  assert sameStateInventory(selected.supervisionDirectory.value.directoryInventory.value,
      source.directoryInventory.value)
  let self = resolveServiceSupervision(source, ServiceIndex(7)).value.supervisionInfo.value
  assert uint32(self.effective) == 7 and self.decision == SupervisionDecision.Designated
  let replaced = resolveServiceSupervision(recreated, ServiceIndex(8)).value.supervisionInfo.value
  assert uint32(replaced.effective) == 8 and replaced.decision ==
      SupervisionDecision.RecreatedNominee
  let missing = resolveServiceSupervision(absent, ServiceIndex(8)).value.supervisionInfo.value
  assert uint32(missing.effective) == 8 and missing.decision == SupervisionDecision.AbsentNominee
  let stale = resolveServiceSupervision(staleSelf, ServiceIndex(7)).value.supervisionInfo.value
  assert uint32(stale.effective) == 7 and stale.decision == SupervisionDecision.RecreatedNominee
  assert uint32(resolveServiceSupervision(cycleSource, ServiceIndex(
      7)).value.supervisionInfo.value.effective) == 8
  assert uint32(resolveServiceSupervision(cycleSource, ServiceIndex(
      8)).value.supervisionInfo.value.effective) == 7
  for id in [0'u32, 99, high(uint32)]:
    assert resolveServiceSupervision(source, ServiceIndex(id)).error ==
        ServiceSupervisionError.NoService # Proven target absence is not a successful fallback.
  assert resolveServiceSupervision(default(StateServiceDirectory), ServiceIndex(7)).error ==
      ServiceSupervisionError.InvalidSource
  assert default(ServiceSupervision).supervisionInfo.error == ServiceSupervisionError.Uninitialized
  assert default(ServiceSupervision).supervisionDirectory.error ==
      ServiceSupervisionError.Uninitialized
  var copied = info
  copied.effective = ServiceIndex(123)
  assert uint32(selected.supervisionInfo.value.effective) == 7
  assert calls() == 0
  for i in 0..<25: cycle(source) # Warm the exact retained-directory observation path.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source) # Every observation handle retires without accumulating directory references.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_service_supervision", 1000, before, finalBytes)
  fail(0)
  echo "state-service-supervision: ok"
try:
  main()
except:
  quit(2) # Fixture failure cannot qualify source-bound authority observations.
