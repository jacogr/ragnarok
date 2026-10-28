# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published exact C(10) projections plus post-assurance ordering, captured time, budgets and
## ownership boundaries.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "report_assignments_arc_release"}

import std/assertions
import std/envvars
import std/strutils
import std/syncio
import ../../../src/state/report_assignments as state_report_assignments
import ../../../src/state/guarantee_credentials as state_guarantee_credentials
import ../../../src/state/availability as state_availability
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/guarantees as codec_guarantees
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/disputes as codec_disputes
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_availability as codec_state_availability
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/owned as codec_owned
import ../../../src/codec/work_report as codec_work_report
import ../../../src/codec/composite as codec_composite
import ../../../src/crypto/assurance_context as crypto_assurance_context
import ../../support/testing_arc_evidence
import ../../support/state_report_context

## Refuse hashes after preparing valid credentials: pure planning must still succeed.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Explicit profile plus independent nested-guarantee, present-record and complete-chapter budgets.
proc config(cores = 2'u64): AvailabilityConfig =
  AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(cores), validators: ValidatorCount(cores*3),
    maxBytes: ByteLimit(1000000)), maxPresent: ElementLimit(cores), maxBytes: ByteLimit(10000000))

## Capture authored fixed core tables through production framing, never by constructing private owners.
proc capture(rows: seq[AvailabilityAssignment], cfg: AvailabilityConfig): AvailabilitySnapshot =
  let entry = availabilityStateEntry(rows, cfg).value
  decodeAvailabilityState(entry.value, cfg).value.snapshot

## Recover exact bytes from a read-only table while retaining every complete guarantee child.
proc bytes(owner: AvailabilitySnapshot, cfg: AvailabilityConfig): seq[byte] =
  var rows = newSeq[AvailabilityAssignment](availabilityInfo(owner).value.cores)
  # Fixed copied assignments retain their report owner and original timestamps.
  for i in 0..<rows.len: rows[i] = availabilityAt(owner, AssignmentCoreIndex(i)).value
  availabilityStateEntry(rows, cfg).value.value

## Check untouched originals and full expected C(10), including previous-rotation guarantee slots/signatures.
proc official(): OwnedReport {.raises.} =
  result = default(OwnedReport)
  var pools: seq[seq[byte]] = @[]
  var total = 0
  var accepted = 0
  # Every tiny/full vector supplies its own roster, original signatures and exact pre/post chapter.
  for row in readFile(getEnv("RAGNAROK_REPORT_ASSIGNMENTS")).splitLines:
    if row.len == 0: continue # Ignore only the trailing transport newline.
    let f = row.splitWhitespace
    if f[0] == "pool":
      pools.add(unhex(f[1])) # Share immutable repeated roster bytes, not verdicts.
      continue
    inc total
    let cores = uint64(parseInt(f[2]))
    let cc = credentialConfig(cores)
    let active = decodeStateValidators(pools[parseInt(f[5])], cc.assignments.roster).value.value
    let previous = decodeStateValidators(pools[parseInt(f[6])], cc.assignments.roster).value.value
    let entropy = decodeStateEntropy(unhex(f[7])).value.value
    let raw = unhex(f[8])
    var offenders = newSeq[OffenderKey](raw.len div 32)
    # Preserve original offender ordering and key identities.
    for i in 0..<offenders.len:
      var key = default(array[32, byte])
      for j in 0..<32: key[j] = raw[i*32+j] # Exact source octets.
      offenders[i] = OffenderKey(key)
    let cfg = config(cores)
    let decoded = decodeGuarantees(unhex(f[9]), cfg.guarantee)
    assert decoded.error == GuaranteeError.None, f[1]
    let credentials = verifyGuaranteeCredentials(records(decoded.value), active, previous, entropy,
      StateTime(parseInt(f[4])), offenders, cc)
    assert credentials.error == GuaranteeCredentialError.None, f[1]
    let original = unhex(f[13])
    let source = decodeAvailabilityState(original, cfg)
    assert source.error == AvailabilityError.None and source.value.consumed == original.len
    let planned = planReportAssignments(credentials.value, source.value.snapshot, cfg)
    if f[3] == "ok":
      assert planned.error == ReportAssignmentError.None, f[1]
      let entry = planned.value.reportAssignmentEntry.value
      assert entry.value == unhex(f[14]), f[1] # Full original signatures, old slots and new registration times.
      assert bytes(planned.value.reportAssignmentState.value, cfg) == entry.value
      assert bytes(planned.value.reportAssignmentSource.value, cfg) == original
      result = credentials.value.verifiedGuaranteeAt(0).value.report
      inc accepted
    else:
      assert f[3] == "core_engaged"
      assert planned.error == ReportAssignmentError.OccupiedCore, f[1] # No partial first report or eviction.
    assert bytes(source.value.snapshot, cfg) == original # Source remains identical on either outcome.
  assert total == 10 and accepted == 8

## Build structurally captured invalid staged input to test inactive/wrong-row refusal, not historical credential acceptance.
proc changedCore(report: OwnedReport, core: int): OwnedReport =
  let original = reportBytes(report)
  var value = decodeReportBorrowed(original, 3).value
  value.core = CoreIndex(core)
  var output = newSeq[byte](original.len+16)
  let encoded = encodeReportBorrowed(value, original, 3, output)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(output.toOpenArray(0, encoded.written-1), 3).value

## Empty assurances let the real earlier stage exercise timeout/resize clearing without fabricated votes.
proc cleared(source: AvailabilitySnapshot, parentCount: int,
    cfg: AvailabilityConfig): AvailabilitySnapshot =
  let rosterCfg = ValidatorStateConfig(cores: cfg.guarantee.cores, validators: ElementLimit(uint64(
      cfg.guarantee.validators)), maxBytes: ByteLimit(100000))
  let wire = validatorEntry(ValidatorChapter.Active, newSeq[StateValidator](parentCount),
      rosterCfg).value.value
  let roster = decodeStateValidators(wire, rosterCfg).value.value
  let policy = AvailabilityTransitionConfig(rosters: rosterCfg, assignments: cfg,
      availableReports: ElementLimit(3))
  let plan = planAvailability(source, roster, ValidatorCount(6), [], default(AssuranceParent),
      StateTime(12), policy)
  assert plan.error == AvailabilityTransitionError.None
  plan.value.assuredAssignments

## A scoped success or late core conflict must release the proposed owner and every temporary table.
proc releaseCycle(credentials: VerifiedGuaranteeCredentials, source: AvailabilitySnapshot,
    expected: ReportAssignmentError) =
  assert planReportAssignments(credentials, source, config()).error == expected # No plan escapes.

## Verify phase ordering, complete record preservation, captured context and whole-batch refusal under tight policy.
proc boundaries(base: OwnedReport) =
  let cfg = config()
  let first = reportFor(base, 0, [10'u64])
  let second = reportFor(base, 1, [10'u64])
  let credentials = certify([first, second])
  let context = credentials.verifiedGuaranteeContext.value
  assert uint32(context.slot) == 12 and uint64(context.population) == 6
  var rows = newSeq[AvailabilityAssignment](2)
  let source = capture(rows, cfg)
  let planned = planReportAssignments(credentials, source, cfg).value
  let expected = planned.reportAssignmentEntry.value.value
  let candidate = planned.reportAssignmentState.value
  assert availabilityInfo(candidate).value.present == 2
  # New registration uses the captured candidate clock; each original guarantee remains complete.
  for i in 0..<2:
    let entry = availabilityAt(candidate, AssignmentCoreIndex(i)).value
    assert uint32(entry.registered) == 12
    assert reportBytes(entry.guarantee.report) == reportBytes(credentials.verifiedGuaranteeAt(
        i).value.report)
  let old = certify([second], 8).verifiedGuaranteeAt(0).value
  rows[1] = presentAssignment(old, AssignmentSlot(9))
  let occupied = capture(rows, cfg)
  assert planReportAssignments(credentials, occupied, cfg).error ==
      ReportAssignmentError.OccupiedCore
  let one = certify([first])
  let retained = planReportAssignments(one, occupied, cfg).value.reportAssignmentState.value
  let untouched = availabilityAt(retained, AssignmentCoreIndex(1)).value
  assert uint32(untouched.registered) == 9 and uint32(untouched.guarantee.slot) == 8
  assert reportBytes(untouched.guarantee.report) == reportBytes(old.report)
  let expired = certify([first], 4).verifiedGuaranteeAt(0).value
  rows = newSeq[AvailabilityAssignment](2)
  rows[0] = presentAssignment(expired, AssignmentSlot(6))
  let beforeTimeout = capture(rows, cfg)
  assert planReportAssignments(one, beforeTimeout, cfg).error == ReportAssignmentError.OccupiedCore
  let afterTimeout = cleared(beforeTimeout, 6, cfg)
  assert planReportAssignments(one, afterTimeout, cfg).error == ReportAssignmentError.None
  var resizedRows = newSeq[AvailabilityAssignment](3)
  var inactive = expired
  inactive.report = changedCore(expired.report, 2)
  resizedRows[2] = presentAssignment(inactive, AssignmentSlot(12))
  let beforeResize = capture(resizedRows, config(3))
  assert planReportAssignments(one, beforeResize, config(3)).error ==
      ReportAssignmentError.InactiveCore
  let afterResize = cleared(beforeResize, 9, config(3))
  assert planReportAssignments(one, afterResize, config(3)).error == ReportAssignmentError.None
  rows = newSeq[AvailabilityAssignment](2)
  rows[1] = presentAssignment(expired, AssignmentSlot(7))
  let wrongRow = capture(rows, cfg)
  assert planReportAssignments(one, wrongRow, cfg).error == ReportAssignmentError.InvalidAssignments
  let noCredentials = default(VerifiedGuaranteeCredentials)
  assert planReportAssignments(noCredentials, source, cfg).error ==
      ReportAssignmentError.InvalidCredentials
  let noAssignments = default(AvailabilitySnapshot)
  assert planReportAssignments(one, noAssignments, cfg).error ==
      ReportAssignmentError.InvalidAssignments
  assert planReportAssignments(one, source, config(3)).error == ReportAssignmentError.InvalidConfig
  assert default(ReportAssignmentPlan).reportAssignmentSource.error ==
      ReportAssignmentError.Uninitialized
  assert default(ReportAssignmentPlan).reportAssignmentState.error ==
      ReportAssignmentError.Uninitialized
  assert default(ReportAssignmentPlan).reportAssignmentEntry.error ==
      ReportAssignmentError.Uninitialized
  let empty = certify([])
  let noChange = planReportAssignments(empty, occupied, cfg).value
  assert noChange.reportAssignmentEntry.value.value == bytes(occupied, cfg)
  let maximum = certify([first], high(uint32))
  let atMaximum = planReportAssignments(maximum, source, cfg).value.reportAssignmentState.value
  assert uint32(availabilityAt(atMaximum, AssignmentCoreIndex(0)).value.registered) == high(uint32)
  var tight = cfg
  tight.maxPresent = ElementLimit(1)
  assert planReportAssignments(credentials, source, tight).error ==
      ReportAssignmentError.LimitExceeded
  tight = cfg
  tight.maxBytes = ByteLimit(expected.len)
  assert planReportAssignments(credentials, source, tight).error == ReportAssignmentError.None
  tight.maxBytes = ByteLimit(expected.len-1)
  assert planReportAssignments(credentials, source, tight).error ==
      ReportAssignmentError.LimitExceeded
  tight = cfg
  tight.guarantee.maxBytes = ByteLimit(1)
  assert planReportAssignments(credentials, source, tight).error ==
      ReportAssignmentError.LimitExceeded
  tight = cfg
  tight.guarantee.validators = ValidatorCount(3)
  assert planReportAssignments(credentials, source, tight).error ==
      ReportAssignmentError.InvalidConfig
  var detached = planned.reportAssignmentEntry.value
  detached.value[0] = 0
  assert planned.reportAssignmentEntry.value.value == expected
  rows[1] = absentAssignment()
  assert bytes(planned.reportAssignmentSource.value, cfg) == bytes(source, cfg)
  failHash(1)
  assert planReportAssignments(credentials, source, cfg).error == ReportAssignmentError.None
  failHash(0) # Pure planning cannot require provider hashes after credential certification.
  releaseCycle(credentials, source, ReportAssignmentError.None)
  releaseCycle(credentials, occupied, ReportAssignmentError.OccupiedCore)
  let before = getOccupiedMem()
  for i in 0..<1000:
    if i mod 2 == 0:
      releaseCycle(credentials, source, ReportAssignmentError.None) # Complete candidate release.
    else:
      releaseCycle(credentials, occupied, ReportAssignmentError.OccupiedCore) # Earlier core was free before a later conflict.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_report_assignments", 1000, before, after)

## Any assertion or fixture failure must fail the supported native runner.
proc main() {.raises.} =
  boundaries(official())
  echo "PASS report assignments: ten published C(10) projections, post-assurance capacity and captured registration time"
try:
  main() # Protocol assertions execute natively.
except:
  quit(2) # Missing transport cannot become a skipped successful suite.
