# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized original-transcript credential extraction and selected assignment-cause guards.

import std/[assertions, cmdline]
import ../../src/state/computed/[credentials as computed_credentials,
    guarantors as computed_guarantors]
import ../../src/codec/guarantees
import ../support/pvm_computed_credentials

proc expect[T](outcome: ComputedCredentialResult[T], reason: ComputedCredentialError) =
  ## Confirm intended failure before deliberate absent payload or invalid cause access.
  assert outcome.error == reason, "credential runtime control"
let source = credentialFixture()
let records = signedCredentials(source, GuaranteeSlot(2), [1'u16, 2], credentialMessage(source))
let done = verifyComputedCredentials(source, GuaranteeSlot(2), records)
expect(done, ComputedCredentialError.None)
assert uint16(done.value.computedCredentialAt(ComputedCredentialIndex(1)).value.validator) == 2
let missing = default(ComputedCredentialResult[CredentialedComputedReport])
let badSource = verifyComputedCredentials(default(ComputedGuarantors), GuaranteeSlot(2), records)
expect(badSource, ComputedCredentialError.InvalidSource)
let count = verifyComputedCredentials(source, GuaranteeSlot(2), [records[0]])
expect(count, ComputedCredentialError.InvalidCount)
let order = verifyComputedCredentials(source, GuaranteeSlot(2), [records[1], records[0]])
expect(order, ComputedCredentialError.NonCanonical)
let assignment = verifyComputedCredentials(source, GuaranteeSlot(3), records)
expect(assignment, ComputedCredentialError.AssignmentFailure)
assert assignment.assignmentError == ComputedGuarantorError.InvalidSlot
var altered = records
altered[1].signature = default(GuaranteeSignature)
let signature = verifyComputedCredentials(source, GuaranteeSlot(2), altered)
expect(signature, ComputedCredentialError.InvalidSignature)
let index = done.value.computedCredentialAt(ComputedCredentialIndex(2))
expect(index, ComputedCredentialError.InvalidIndex)
case paramStr(1)
of "default": discard missing.value # No complete default credential owner.
of "source": discard badSource.value # No authenticated computed context.
of "count": discard count.value # Exactly two/three records required.
of "order": discard order.value # Canonical increasing indices required.
of "assignment": discard assignment.value # Nested refusal has no verified prefix.
of "signature": discard signature.value # Late invalid signature has no complete credentials.
of "index": discard index.value # No third credential in the completed pair.
of "owner": discard default(CredentialedComputedReport).computedCredentialSource.value # No source.
of "info": discard default(CredentialedComputedReport).computedCredentialInfo.value # No metadata.
of "record": discard default(CredentialedComputedReport).computedCredentialAt(
    ComputedCredentialIndex(0)).value # No record.
else: discard signature.assignmentError # A signature refusal carries no assignment-cause payload.
