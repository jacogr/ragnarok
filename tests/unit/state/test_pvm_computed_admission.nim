# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_admission_arc_release"}

## Genuine computed package admission preserves original semantic policy and exact child failures.

import std/assertions
import std/syncio
import ../../../src/state/computed_admission as state_computed_admission
import ../../../src/state/computed_inclusion as state_computed_inclusion
import ../../../src/state/computed_batch as state_computed_batch
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/report_policy as state_report_policy
import ../../../src/state/report_packages as state_report_packages
import ../../../src/state/guarantors as state_guarantors
import ../../../src/state/report_anchors as state_report_anchors
import ../../../src/state/guarantee_credentials as state_guarantee_credentials
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../support/pvm_computed_admission
import ../../support/testing_arc_evidence

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Detect any unintended crypto before original semantic-profile gates.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Copy actual backend observations without faking successful crypto.
proc expect[T](outcome: ComputedAdmissionResult[T], reason: ComputedAdmissionError) =
  ## Verify exact refusal alternative before extracting successful data or child causes.
  if outcome.error != reason:
    # Print the originating typed stage only on unexpected failure; successful suite output stays exact.
    echo "expected ", reason, " got ", outcome.error
    if outcome.error == ComputedAdmissionError.AdmissionFailure:
      let child = outcome.admissionError
      echo "report stage ", child.error
      if child.error == ReportAdmissionError.PolicyFailure: echo "policy ", child.policyError
      if child.error == ReportAdmissionError.PackageFailure: echo "package ", child.packageError
      if child.error == ReportAdmissionError.AnchorFailure: echo "anchor ", child.anchorError
      if child.error == ReportAdmissionError.CredentialFailure: echo "credential ",
          child.credentialError.error
  assert outcome.error == reason, "computed admission reason"
let source = admissionFixture()
let config = computedAdmissionConfig(source)
let outcome = admitComputedReports(source, config)
expect(outcome, ComputedAdmissionError.None)
let done = outcome.value
let reports = done.computedAdmissionReports.value
assert reports.reportCredentials.value.verifiedGuaranteeCount.value == 2
assert reports.reportCredentials.value.verifiedReporterCount.value == 6
assert done.computedAdmissionSource.value.computedInclusionSource.value.computedBatchInfo.value.guarantees == 2
let parent = source.computedInclusionStage.value.value.admitted.admittedState
assert sameStateSnapshot(parent, reports.reportBlockStage.value.value.admitted.admittedState)
let duplicate = admissionFixture(distinctPackages = false)
let rejected = admitComputedReports(duplicate, computedAdmissionConfig(duplicate))
expect(rejected, ComputedAdmissionError.AdmissionFailure)
assert rejected.admissionError.error == ReportAdmissionError.PackageFailure
assert rejected.admissionError.packageError == ReportPackageError.DuplicatePackage
for variant in 0..<3:
  var wrong = config
  case variant
  of 0: wrong.policy.reportGas = ReportGasLimit(0) # Original accumulation ceiling cannot be replaced.
  of 1: wrong.credentials.assignments.rotationSlots = GuarantorRotationSlots(
      1) # Selection domain remains original.
  else: wrong.anchors.lookupAge = LookupAge(0) # Original maximum lookup age participates.
  reset(1)
  expect(admitComputedReports(source, wrong), ComputedAdmissionError.ProfileMismatch)
  assert hashes() == 0, "profile refusal precedes verification"
  reset(0)
expect(admitComputedReports(default(IncludedComputedGuarantees), config),
    ComputedAdmissionError.InvalidSource)
var short = config
short.ancestors.headers = ElementLimit(1)
expect(admitComputedReports(source, short), ComputedAdmissionError.LimitExceeded)
short = config
short.credentials.reporters = ElementLimit(5)
let constrained = admitComputedReports(source, short)
expect(constrained, ComputedAdmissionError.AdmissionFailure)
assert constrained.admissionError.error == ReportAdmissionError.CredentialFailure
expect(default(AdmittedComputedReports).computedAdmissionSource,
    ComputedAdmissionError.Uninitialized)
expect(default(AdmittedComputedReports).computedAdmissionReports,
    ComputedAdmissionError.Uninitialized)
proc detached(): AdmittedComputedReports =
  ## Retain source computations and complete admission after all caller-owned configuration/fixtures retire.
  let source = admissionFixture()
  admitComputedReports(source, computedAdmissionConfig(source)).value
let retained = detached()
assert retained.computedAdmissionReports.value.reportCredentials.value.verifiedGuaranteeCount.value == 2
proc cycle(source: IncludedComputedGuarantees, config: ReportAdmissionConfig) =
  ## Release independently verified credentials, policy/package indexes and original source sharing every iteration.
  let done = admitComputedReports(source, config).value
  discard done.computedAdmissionReports.value
  discard done.computedAdmissionSource.value
cycle(source, config)
let before = getOccupiedMem()
for i in 0..<1000: cycle(source, config) # New complete admission certificates retire on each bounded cycle.
let after = getOccupiedMem()
assert before == after, "computed admission ARC release"
recordArcRelease("pvm_computed_admission", 1000, before, after)
echo "PVM computed admission passed"
echo "ARC_RELEASE cycles=1000 unchanged"
