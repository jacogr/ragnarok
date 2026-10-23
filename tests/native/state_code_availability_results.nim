# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent literal code hashes, complete source association, history boundaries and copy/work policies qualify the full-state catalogue.
import std/[assertions, syncio, envvars, cmdline]
import ../support/[state_inventory_context, arc_evidence]
import ../../src/state/[code_availability, inventory]
import ../../src/codec/[bounded, state_accounts, state_composition, state_requests]
include composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset primitive counters and force real content backend failures after source capture.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe complete preflight before any selected content hash.
const limits = CodeAvailabilityLimits(services: ElementLimit(2), visits: ElementLimit(4),
    descriptors: ByteLimit(65536), perCode: ByteLimit(3), totalCodeBytes: ByteLimit(3))
proc captured(chapters: seq[seq[byte]], rows: seq[StateService]): StateInventory =
  ## Match all explicitly supplied declarations to their genuine complete physical source before auditing code.
  captureStateInventory(inventoryManifest(chapters, rows), rows, inventoryCaptureLimits).value
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(CodeAvailabilityResult[StateCodeAvailability])
  if mode == "value":
    discard empty.value
    return
  if mode == "offender":
    discard empty.failedService
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  if getEnv("RAGNAROK_COMPOSITION_FIXTURE").len == 0:
    putEnv("RAGNAROK_COMPOSITION_FIXTURE", "build/state11-composition.hex") # Strict drivers use the same independently authored chapter equations as native units.
  let chapters = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var rows = inventoryServices()
  rows[0].metadata.codeHash = CodeHash(array[32, byte](rows[0].preimages[0].hash))
  let source = captured(chapters, rows)
  var wrong = rows
  wrong[0].preimages[0].value[2] = 100
  let mismatch = captured(chapters, wrong)
  var missing = rows
  missing[0].requests = @[]
  let unlinked = captured(chapters, missing)
  fail(1)
  var short = limits
  short.visits = ElementLimit(3)
  assert auditCodeAvailability(source, RequestSlot(3), short).error ==
      CodeAvailabilityError.LimitExceeded
  short = limits
  short.totalCodeBytes = ByteLimit(2)
  assert auditCodeAvailability(source, RequestSlot(3), short).error ==
      CodeAvailabilityError.LimitExceeded and calls() == 0
  short = limits
  short.descriptors = ByteLimit(0)
  assert auditCodeAvailability(source, RequestSlot(3), short).error ==
      CodeAvailabilityError.LimitExceeded and calls() == 0
  short = limits
  short.services = ElementLimit(1)
  assert auditCodeAvailability(source, RequestSlot(3), short).error ==
      CodeAvailabilityError.LimitExceeded and calls() == 0
  short = limits
  short.perCode = ByteLimit(2)
  assert auditCodeAvailability(source, RequestSlot(3), short).error ==
      CodeAvailabilityError.LimitExceeded and calls() == 0
  let refused = auditCodeAvailability(source, RequestSlot(3), limits)
  assert refused.error == CodeAvailabilityError.BackendFailure and uint32(refused.failedService) == 7
  fail(0)
  assert auditCodeAvailability(mismatch, RequestSlot(3), limits).error ==
      CodeAvailabilityError.HashMismatch
  assert auditCodeAvailability(unlinked, RequestSlot(3), limits).error ==
      CodeAvailabilityError.MissingRequest
  let table = auditCodeAvailability(source, RequestSlot(3), limits).value
  assert table.codeAvailabilityInfo.value.services == 2 and
      table.codeAvailabilityInfo.value.available == 1
  var exact = limits
  exact.descriptors = ByteLimit(table.codeAvailabilityInfo.value.descriptors)
  assert auditCodeAvailability(source, RequestSlot(3), exact).error == CodeAvailabilityError.None
  exact.descriptors = ByteLimit(table.codeAvailabilityInfo.value.descriptors-1)
  fail(1)
  assert auditCodeAvailability(source, RequestSlot(3), exact).error ==
      CodeAvailabilityError.LimitExceeded and calls() == 0
  fail(0)
  var two = rows
  two[1].metadata.codeHash = two[0].metadata.codeHash
  two[1].preimages = two[0].preimages
  two[1].requests = two[0].requests
  let later = captured(chapters, two)
  var aggregate = limits
  aggregate.visits = ElementLimit(8)
  aggregate.totalCodeBytes = ByteLimit(5)
  fail(1)
  assert auditCodeAvailability(later, RequestSlot(3), aggregate).error ==
      CodeAvailabilityError.LimitExceeded and calls() == 0
  fail(0)
  assert sameStateInventory(table.codeAvailabilityInventory.value, source)
  assert table.serviceCodeAt(0).value.state == ServiceCodeState.Available
  assert table.serviceCodeAt(1).value.state == ServiceCodeState.Absent
  assert table.findServiceCode(ServiceIndex(7)).value == 0
  assert table.findServiceCode(ServiceIndex(999)).error == CodeAvailabilityError.NoService
  var output = table.copyServiceCode(0, ByteLimit(3)).value
  output[0] = 0
  assert table.copyServiceCode(0, ByteLimit(3)).value == @[97'u8, 98, 99]
  assert table.copyServiceCode(0, ByteLimit(2)).error == CodeAvailabilityError.LimitExceeded
  assert table.copyServiceCode(1, ByteLimit(3)).error == CodeAvailabilityError.Unavailable
  assert table.serviceCodeAt(-1).error == CodeAvailabilityError.InvalidIndex
  assert table.serviceCodeAt(2).error == CodeAvailabilityError.InvalidIndex
  assert auditCodeAvailability(source, RequestSlot(2), limits).value.serviceCodeAt(0).value.state ==
      ServiceCodeState.Unavailable
  for shape in 0..<4:
    rows[0].requests[0].history = case shape
      of 0: requestedHistory()
      of 1: availableHistory(RequestSlot(3))
      of 2: unavailableHistory(RequestSlot(3), RequestSlot(5))
      else: reavailableHistory(RequestSlot(3), RequestSlot(5), RequestSlot(
          7)) # Explicit interval oracles preserve inclusive starts and exclusive removal.
    let original = captured(chapters, rows)
    for time in 0..8:
      let expected = case shape
        of 0: false
        of 1: time >= 3
        of 2: time >= 3 and time < 5
        else: (time >= 3 and time < 5) or time >= 7
      let observed = auditCodeAvailability(original, RequestSlot(uint32(time)), limits).value
      assert (observed.serviceCodeAt(0).value.state == ServiceCodeState.Available) == expected
  rows[0].requests[0].history = availableHistory(RequestSlot(0))
  rows[0].preimages[0].value = @[]
  rows[0].preimages[0].hash = ServicePreimageHash([byte(14), 87, 81, 192, 38, 229, 67, 178, 232,
      171, 46, 176, 96, 153, 218, 161, 209, 229, 223, 71, 119, 143, 119, 135, 250, 171, 69, 205,
      241, 47, 227, 168])
  rows[0].metadata.codeHash = CodeHash(array[32, byte](rows[0].preimages[0].hash))
  rows[0].requests[0].hash = rows[0].preimages[0].hash
  rows[0].requests[0].length = RequestLength(0)
  let emptyCode = auditCodeAvailability(captured(chapters, rows), RequestSlot(0), limits).value
  assert emptyCode.serviceCodeAt(0).value.state == ServiceCodeState.Available and
      emptyCode.copyServiceCode(0, ByteLimit(0)).value.len == 0
  assert auditCodeAvailability(default(StateInventory), RequestSlot(0), limits).error ==
      CodeAvailabilityError.InvalidSource
  assert default(StateCodeAvailability).codeAvailabilityInfo.error ==
      CodeAvailabilityError.Uninitialized
  let noServices = captured(chapters, @[])
  fail(1)
  let noCodes = auditCodeAvailability(noServices, RequestSlot(0), default(
      CodeAvailabilityLimits)).value
  assert noCodes.codeAvailabilityInfo.value.services == 0 and calls() == 0
  assert noCodes.findServiceCode(ServiceIndex(7)).error == CodeAvailabilityError.NoService
  assert default(StateCodeAvailability).copyServiceCode(0, ByteLimit(0)).error ==
      CodeAvailabilityError.Uninitialized
  fail(0)
  for i in 0..<25: discard auditCodeAvailability(source, RequestSlot(3),
      limits).value # Warm only this isolated acyclic audit/copy path.
  let before = getOccupiedMem()
  for i in 0..<1000:
    let retained = auditCodeAvailability(source, RequestSlot(3), limits).value
    assert retained.copyServiceCode(0, ByteLimit(3)).value.len == 3
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_code_availability", 1000, before, after)
  echo "state-code-availability: ok"
try:
  main()
except:
  quit(2) # Source setup failure never satisfies a strict result rejection.
