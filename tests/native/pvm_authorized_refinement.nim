# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized guards reject failed composition values and unrelated authorization/refinement/digest reason access.

import std/[assertions, cmdline]
import ../../src/state/[authorized_refinement, authorization_invocation, refinement_dispatch,
    refinement_report, refinement_digest]
import ../../src/codec/[bounded, composite]
import ../support/[pvm_authorized_refinement, pvm_report_results, pvm_refinement_outcome]

proc check(result: AuthorizedRefinementResult[AuthorizedRefinement],
    reason: AuthorizedRefinementError) =
  ## Confirm genuine alternatives without specializing the deliberate misuse below.
  assert result.error == reason
let halt = @[50'u8, 0]
let source = authorizedFixture([refinementImmediate(7, 65536), refinementImmediate(8, 3), halt], [
    reportGuest([halt])])
let success = prepareAuthorizedRefinement(source.authorization, source.inputs, authorizedLimits())
check(success, AuthorizedRefinementError.None)
assert success.value.authorizedInfo.value.items == 1
let rejectedSource = authorizedFixture([halt], [reportGuest([halt])], missingAuth = true)
let rejected = prepareAuthorizedRefinement(rejectedSource.authorization, default(RefinementInputs),
    default(AuthorizedRefinementLimits))
check(rejected, AuthorizedRefinementError.AuthorizationRejected)
assert rejected.authorizationKind == WorkKind.Bad
let child = prepareAuthorizedRefinement(source.authorization, default(RefinementInputs),
    authorizedLimits())
check(child, AuthorizedRefinementError.RefinementFailure)
assert child.refinementError.error == RefinementReportError.InvocationFailure
var cap = authorizedLimits()
cap.digests.totalEncoding = ByteLimit(0)
let projected = prepareAuthorizedRefinement(source.authorization, source.inputs, cap)
check(projected, AuthorizedRefinementError.DigestFailure)
assert projected.digestError == RefinementDigestError.LimitExceeded
let missing = default(AuthorizedRefinementResult[AuthorizedRefinement])
check(missing, AuthorizedRefinementError.Uninitialized)
case paramStr(1)
of "default": discard missing.value # Default alternatives have no bound source/result owner.
of "rejected": discard rejected.value # Protocol authorization rejection cannot expose a partial report.
of "refinement": discard child.value # Failed refinement has no prepared digest collection.
of "digest": discard projected.value # A late projection refusal discards the private report.
of "success-auth": discard success.authorizationKind # Complete success has no authorization-rejection reason.
of "success-refinement": discard success.refinementError # Complete success has no child refusal detail.
of "success-digest": discard success.digestError # Complete success has no projection refusal.
of "wrong-refinement": discard projected.refinementError # Projection failure cannot fabricate an execution-stage alternative.
of "wrong-digest": discard child.digestError # Execution failure cannot fabricate a projection refusal.
else: discard default(AuthorizedRefinement).authorizedInfo.value # Missing owners have no aggregate facts.
