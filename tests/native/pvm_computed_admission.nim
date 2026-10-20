# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized admission/result-reason guards retain genuine included computed reports as positive controls.

import std/[assertions, cmdline]
import ../../src/state/[computed_admission, computed_inclusion, report_admission, report_policy]
import ../../src/codec/bounded
import ../support/pvm_computed_admission

proc expect[T](outcome: ComputedAdmissionResult[T], reason: ComputedAdmissionError) =
  ## Check exact alternatives before deliberate absent payload/cause extraction.
  assert outcome.error == reason, "computed admission runtime control"
let source = admissionFixture()
let config = computedAdmissionConfig(source)
let done = admitComputedReports(source, config)
expect(done, ComputedAdmissionError.None)
let invalid = admitComputedReports(default(IncludedComputedGuarantees), config)
expect(invalid, ComputedAdmissionError.InvalidSource)
var changed = config
changed.policy.reportGas = ReportGasLimit(0)
let profile = admitComputedReports(source, changed)
expect(profile, ComputedAdmissionError.ProfileMismatch)
changed = config
changed.ancestors.headers = ElementLimit(1)
let limit = admitComputedReports(source, changed)
expect(limit, ComputedAdmissionError.LimitExceeded)
changed = config
changed.credentials.reporters = ElementLimit(5)
let child = admitComputedReports(source, changed)
expect(child, ComputedAdmissionError.AdmissionFailure)
assert child.admissionError.error == ReportAdmissionError.CredentialFailure
let missing = default(ComputedAdmissionResult[AdmittedComputedReports])
case paramStr(1)
of "default": discard missing.value # No default admitted reports.
of "source": discard invalid.value # No loose source authority.
of "profile": discard profile.value # Original protocol knobs are mandatory.
of "limit": discard limit.value # No partial ancestor prefix on refusal.
of "child": discard child.value # Actual child refusal has no completed report certificate.
of "owner": discard default(AdmittedComputedReports).computedAdmissionSource.value # No original inclusion.
of "reports": discard default(AdmittedComputedReports).computedAdmissionReports.value # No report admission.
of "reason-default": discard missing.admissionError # Default contains no nested refusal.
of "reason-success": discard done.admissionError # Complete success contains no refusal.
else: discard profile.admissionError # Semantic-profile refusal carries no unrelated child failure.
