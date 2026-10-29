# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict successor, receiver and nested store-cause probes with genuine admitted computed source controls.

import std/[assertions, cmdline]
import ../../src/state/computed/[publication as computed_publication,
    admission as computed_admission]
import ../../src/state/report/admission as report_admission
import "../../src/state/block/transition" as block_transition
import "../../src/state/block/admission" as block_admission
import ../../src/state/store
import ../../src/codec/bounded
import ../support/pvm_computed_publication

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Force an actual maintained backend failure after genuine execution/admission finishes.
proc expect[T](outcome: ComputedPublicationResult[T], reason: ComputedPublicationError) =
  ## Verify exact alternatives before attempting absent successful values or unrelated causes.
  assert outcome.error == reason, "computed publication runtime control"
let source = publicationFixture()
let done = prepareComputedPublication(source, ByteLimit(100000))
expect(done, ComputedPublicationError.None)
let invalid = prepareComputedPublication(default(AdmittedComputedReports), ByteLimit(100000))
expect(invalid, ComputedPublicationError.InvalidSource)
let limit = prepareComputedPublication(source, ByteLimit(0))
expect(limit, ComputedPublicationError.LimitExceeded)
reset(1)
let backend = prepareComputedPublication(source, ByteLimit(100000))
expect(backend, ComputedPublicationError.StoreFailure)
assert backend.storeError == StateStoreError.BackendFailure
reset(0)
let parent = source.computedAdmissionReports.value.reportBlockStage.value.value.admitted.admittedState
var receiver = forkStateStore(parent).value
expect(publishComputedReports(receiver, done.value), ComputedPublicationError.None)
let replay = publishComputedReports(receiver, done.value)
expect(replay, ComputedPublicationError.StateMismatch)
let missing = default(ComputedPublicationResult[ComputedReportSuccessor])
case paramStr(1)
of "default": discard missing.value # No default prepared map.
of "source": discard invalid.value # No loose admission authority.
of "limit": discard limit.value # Copy refusal retains no successor.
of "backend": discard backend.value # Failed hashing cannot expose a candidate map.
of "replay": discard replay.value # Stale receiver exposes no newly published map.
of "owner": discard default(ComputedReportSuccessor).computedSuccessorSource.value # No retained admission.
of "snapshot": discard default(ComputedReportSuccessor).computedSuccessorSnapshot.value # No final map.
of "reason-default": discard missing.storeError # Default carries no backend refusal.
of "reason-success": discard done.storeError # Complete success has no failure cause.
else: discard limit.storeError # Resource refusal carries no unrelated store cause.
