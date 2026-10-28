# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized success/reason guards include real code execution and successful immutable owner controls.

import std/assertions
import std/cmdline
import ../../src/state/input_refinement as state_input_refinement
import ../../src/state/import_inputs as state_import_inputs
import ../../src/state/report_identity as state_report_identity
import ../../src/state/authorization_invocation as state_authorization_invocation
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/work_report as codec_work_report
import ../support/pvm_input_refinement
import ../support/pvm_report_results
import ../support/pvm_refinement_outcome

proc check(outcome: InputRefinementResult[InputRefinement], reason: InputRefinementError) =
  ## Inspect runtime alternatives without statically specializing deliberate invalid extraction.
  assert outcome.error == reason
let authCode = [refinementImmediate(8, 0), @[50'u8, 0]]
let fixture = executionFixture(authCode, [fetchedGuest(4)])
let done = executionRun(fixture)
check(done, InputRefinementError.None)
assert done.value.inputRefinementIdentity.value.identityInfo.value.lookupCount == 0
let missing = default(InputRefinementResult[InputRefinement])
let invalid = runInputRefinement(fixture.state, default(VerifiedImportInputs), CoreIndex(0),
    fixture.parameters, executionLimits())
check(invalid, InputRefinementError.InvalidInputs)
var cap = executionLimits()
cap.inputBytes = ByteLimit(0)
let limited = executionRun(fixture, cap)
check(limited, InputRefinementError.LimitExceeded)
cap = executionLimits()
cap.authorization.preimage = ByteLimit(0)
let authorization = executionRun(fixture, cap)
check(authorization, InputRefinementError.AuthorizationFailure)
cap = executionLimits()
cap.refinement.digests.totalEncoding = ByteLimit(1)
let refinement = executionRun(fixture, cap)
check(refinement, InputRefinementError.RefinementFailure)
cap = executionLimits()
cap.identity.packageBytes = ByteLimit(0)
let identity = executionRun(fixture, cap)
check(identity, InputRefinementError.IdentityFailure)
case paramStr(1)
of "default": discard missing.value # A default result cannot expose a completed computation.
of "inputs": discard invalid.value # No default owner can certify empty inputs.
of "limit": discard limited.value # Materialization refusal exposes no partial result.
of "authorization": discard authorization.value # Local authorizer failure exposes no source/trace result.
of "refinement": discard refinement.value # Late digest failure cannot publish a successful report prefix.
of "identity": discard identity.value # Late identity failure cannot publish private completed execution.
of "owner": discard default(InputRefinement).inputRefinementSource.value # Default handles have no input authority.
of "authorization-reason": discard done.authorizationError # A successful alternative has no failed authorization reason.
of "authorization-kind": discard done.authorizationKind # Success cannot fabricate a protocol rejection kind.
of "refinement-reason": discard done.refinementError # Success has no failed refinement reason.
of "identity-reason": discard done.identityError # Success has no identity refusal reason.
else: discard authorization.authorizationError.value # Retained failed child alternatives also guard their successful payloads.
