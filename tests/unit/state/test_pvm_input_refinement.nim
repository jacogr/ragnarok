# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_input_refinement_arc_release"}

## Genuine owned-input execution binds fetched bytes, source identity and lookup; failures retain no completed prefix.

import std/[assertions, syncio]
import ../../../src/state/input_refinement
import "../../../src/state/import/inputs" as import_inputs
import ../../../src/state/extrinsic_inputs
import "../../../src/state/import/justification" as import_justification
import ../../../src/state/report/identity as report_identity
import ../../../src/state/authorized_refinement
import ../../../src/state/authorization/invocation as authorization_invocation
import ../../../src/state/refinement/[digest as refinement_digest, report as refinement_report,
    outcome as refinement_outcome, bootstrap as refinement_bootstrap,
    dispatch as refinement_dispatch, lookup as refinement_lookup]
import ../../../src/state/store
import ../../../src/codec/[bounded, composite]
import ../../../src/codec/work/[package as work_package, report as work_report]
import ../../../src/pvm/host/fetch as host_fetch
import ../../../src/chain/parameters
import ../../../src/crypto/primitives
import ../../support/[pvm_input_refinement, pvm_report_results, pvm_refinement_outcome,
  pvm_import_inputs, pvm_import_vectors, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Controlled hashing failure proves invalid source refusal precedes execution.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe copied counters without relying on a successful fabricated backend result.
proc expect[T](outcome: InputRefinementResult[T], reason: InputRefinementError) =
  ## Inspect exact alternatives without extracting failed payloads.
  assert outcome.error == reason, "input execution reason mismatch"
proc output(done: InputRefinement, item: uint64): seq[byte] =
  ## Walk only immutable retained execution provenance to inspect actual normalized guest bytes.
  done.inputRefinementIdentity.value.identitySource.value.authorizedDigests.value.digestAt(
    FetchItemIndex(item)).value.digestOutput.value

let halt = @[50'u8, 0]
let authCode = @[refinementImmediate(7, 65536), refinementImmediate(8, 3), halt]
let fixture = executionFixture(authCode, [fetchedGuest(4), fetchedGuest(6), fetchedGuest(2)])
let done = executionRun(fixture).value
assert done.output(0) == @[97'u8, 98, 99], "owned input check: done.output(0)"
assert done.output(1) == @[2'u8, 0, 0], "owned input check: done.output(1)"
assert done.output(2) == @[11'u8, 12, 13], "owned input check: done.output(2)"
let identity = done.inputRefinementIdentity.value
let authorized = identity.identitySource.value
let info = identity.identityInfo.value
assert uint64(info.core) == 0x1234 and info.lookupCount == 1, "owned input check: uint64(info.core)"
assert identity.identityRoot(inputKey(1)).value.bytes == ThreeRoot, "owned input check: identity.identityRoot(inputKey(1)).value.bytes"
assert authorized.authorizedDigests.value.digestReport.value.reportTrace.value == @[11'u8, 12, 13], "owned input check: authorized.authorizedDigests.value.digestReport.value.reportTrace.value"
assert sameStateSnapshot(authorized.authorizedSource.value.authorizationState.value, fixture.state), "owned input check: sameStateSnapshot(authorized.authorizedSource.value.authorizationState.value, fixture.state)"
assert done.inputRefinementSource.value.importInputsInfo.value.entries == 3, "owned input check: done.inputRefinementSource.value.importInputsInfo.value.entries"
assert done.inputRefinementSource.value.importInputsExtrinsics.value.extrinsicInputsInfo.value.entries ==
    3, "owned input check: done.inputRefinementSource.value.importInputsExtrinsics.value.extrinsicInputsInfo.value.entries"
var wire = newSeq[byte](fixture.package.workPackageInfo.value.consumed)
assert fixture.package.encodeOwnedWorkPackage(wire).error == PackageError.None, "owned input check: fixture.package.encodeOwnedWorkPackage(wire).error"
assert info.packageHash.bytes == array[32, byte](blake2b256(wire).value), "owned input check: info.packageHash.bytes"
# Current and any-item selectors consume the same captured original rows, including distinguishable second-item data.
let current = executionFixture(authCode, [fetchedGuest(4), fetchedGuest(4)])
let currentDone = executionRun(current).value
assert currentDone.output(0) == @[97'u8, 98, 99], "owned input check: currentDone.output(0)"
assert currentDone.output(1) == @[97'u8, 98, 100], "owned input check: currentDone.output(1)"
let other = executionFixture(authCode, [fetchedGuest(3, 1), fetchedGuest(5, 0)])
let otherDone = executionRun(other).value
assert otherDone.output(0) == @[97'u8, 98, 100], "owned input check: otherDone.output(0)"
assert otherDone.output(1) == @[1'u8, 0, 0], "owned input check: otherDone.output(1)"
# The independent temporary-table cap includes every occurrence; exact totals pass and both subtraction branches refuse safely.
var cap = executionLimits()
cap.inputBytes = ByteLimit(12321)
expect(executionRun(fixture, cap), InputRefinementError.None)
for bytes in [0'u64, 8, 12320]:
  cap.inputBytes = ByteLimit(bytes)
  expect(executionRun(fixture, cap), InputRefinementError.LimitExceeded)
let empty = executionFixture([refinementImmediate(8, 0), halt],
  [reportGuest([refinementImmediate(8, 0), halt])], external = false)
cap = executionLimits()
cap.inputBytes = ByteLimit(0)
let emptyDone = executionRun(empty, cap).value
assert emptyDone.output(0).len == 0, "owned input check: emptyDone.output(0).len"
# Defaults are refused before authorization; no backend work or synthetic empty-result certificate can escape.
reset(1)
let invalid = runInputRefinement(fixture.state, default(VerifiedImportInputs), CoreIndex(0),
  fixture.parameters, executionLimits())
expect(invalid, InputRefinementError.InvalidInputs)
assert hashes() == 0, "owned input check: hashes()"
let backend = executionRun(fixture)
expect(backend, InputRefinementError.AuthorizationFailure)
assert backend.authorizationError.error == AuthorizationInvocationError.LookupFailure, "owned input check: backend.authorizationError.error"
assert backend.authorizationError.lookupError == HistoricalLookupError.BackendFailure, "lookup backend refusal retains its exact stage"
reset(0)
# Child authorization refusals preserve exact nested reasons, with full-width core bounds checked before narrowing.
let indexed = executionRun(fixture, core = high(uint64))
expect(indexed, InputRefinementError.AuthorizationFailure)
assert indexed.authorizationError.error == AuthorizationInvocationError.InvalidSelection, "owned input check: indexed.authorizationError.error"
let invalidParameters = runInputRefinement(fixture.state, fixture.inputs, CoreIndex(0), default(
    Parameters), executionLimits())
expect(invalidParameters, InputRefinementError.AuthorizationFailure)
assert invalidParameters.authorizationError.error == AuthorizationInvocationError.InvalidParameters, "owned input check: invalidParameters.authorizationError.error"
# Completed protocol rejection and the fixed trace ceiling precede local input/refinement policies.
for variant in 0..<3:
  let rejected = executionFixture((if variant == 2: @[@[0'u8]] else: @[halt]),
    [reportGuest([refinementImmediate(8, 0), halt])], authCodeSize = (if variant ==
        1: 64001 else: 0),
    missingAuth = variant == 0)
  cap = executionLimits()
  cap.inputBytes = ByteLimit(0)
  cap.refinement = default(AuthorizedRefinementLimits)
  let refused = executionRun(rejected, cap)
  expect(refused, InputRefinementError.AuthorizationRejected)
  let kind = if variant == 0: WorkKind.Bad elif variant == 1: WorkKind.Big else: WorkKind.Panic
  assert refused.authorizationKind == kind, "owned input check: refused.authorizationKind"
let exactTrace = executionFixture([refinementImmediate(7, 196608), refinementImmediate(8, 49152), halt],
  [reportGuest([refinementImmediate(8, 0), halt])], external = false, authCodeSize = 64000)
cap = executionLimits()
cap.inputBytes = ByteLimit(0)
let exactDone = executionRun(exactTrace, cap).value
assert exactDone.inputRefinementIdentity.value.identitySource.value.authorizedInfo.value.traceBytes ==
    49152, "owned input check: exactDone.inputRefinementIdentity.value.identitySource.value.authorizedInfo.value.traceBytes"
let large = executionFixture([refinementImmediate(7, 196608), refinementImmediate(8, 49153), halt],
  [reportGuest([refinementImmediate(8, 0), halt])], authCodeSize = 64000)
cap = executionLimits()
cap.inputBytes = ByteLimit(0)
cap.refinement = default(AuthorizedRefinementLimits)
expect(executionRun(large, cap), InputRefinementError.TraceTooLarge)
cap = executionLimits()
cap.refinement.trace = FetchTraceLimit(2)
expect(executionRun(fixture, cap), InputRefinementError.LimitExceeded)
# Late bootstrap, capture, digest and identity refusals preserve their stages without exposing prior completed items.
cap = executionLimits()
cap.refinement.refinement.bootstrap.preimage = ByteLimit(0)
let bootstrap = executionRun(fixture, cap)
expect(bootstrap, InputRefinementError.RefinementFailure)
assert bootstrap.refinementError.refinementError.bootstrapError ==
    RefinementBootstrapError.LimitExceeded
cap = executionLimits()
cap.refinement.refinement.invocation.capture.inputs = FetchInputLimit(1)
let capture = executionRun(fixture, cap)
expect(capture, InputRefinementError.RefinementFailure)
assert capture.refinementError.error == AuthorizedRefinementError.RefinementFailure, "owned input check: capture.refinementError.error"
cap = executionLimits()
cap.refinement.digests.totalEncoding = ByteLimit(1)
let digest = executionRun(fixture, cap)
expect(digest, InputRefinementError.RefinementFailure)
assert digest.refinementError.error == AuthorizedRefinementError.DigestFailure, "owned input check: digest.refinementError.error"
assert digest.refinementError.digestError == RefinementDigestError.LimitExceeded, "owned input check: digest.refinementError.digestError"
cap = executionLimits()
cap.identity.packageBytes = ByteLimit(0)
let projected = executionRun(fixture, cap)
expect(projected, InputRefinementError.IdentityFailure)
assert projected.identityError == ReportIdentityError.LimitExceeded, "owned input check: projected.identityError"
# Copied lookup, trace, metadata and fetched bytes cannot mutate either retained input or completed execution provenance.
var lookup = done.inputRefinementSource.value.importInputsLookup.value
lookup[0].segmentRoot.bytes[0] = 255
var trace = authorized.authorizedSource.value.authorizationTrace.value
trace[0] = 255
var bytes = done.output(0)
bytes[0] = 255
var copiedInfo = identity.identityInfo.value
copiedInfo.core = CoreIndex(0)
assert done.output(0) == @[97'u8, 98, 99], "owned input check: done.output(0)"
assert identity.identityRoot(inputKey(1)).value.bytes == ThreeRoot, "owned input check: identity.identityRoot(inputKey(1)).value.bytes"
assert uint64(identity.identityInfo.value.core) == 0x1234, "owned input check: uint64(identity.identityInfo.value.core)"
var replaced = fixture
replaced.package = default(OwnedWorkPackage)
let replay = executionRun(replaced).value
assert replay.inputRefinementIdentity.value.identityInfo.value.packageHash.bytes ==
    info.packageHash.bytes
assert replay.output(1) == done.output(1), "owned input check: replay.output(1)"
expect(default(InputRefinement).inputRefinementSource, InputRefinementError.Uninitialized)
expect(default(InputRefinement).inputRefinementIdentity, InputRefinementError.Uninitialized)
proc detached(): InputRefinement =
  ## Retire the original complete state, parameters, package and verified tables before result extraction.
  executionRun(executionFixture(authCode, [fetchedGuest(4)])).value
assert detached().output(0) == @[97'u8, 98, 99], "owned input check: detached().output(0)"
proc cycle() =
  ## Release final identity/input ownership and late-failed execution prefixes on every iteration.
  let completed = executionRun(current).value
  assert completed.output(1) == @[97'u8, 98, 100], "owned input check: completed.output(1)"
  var local = executionLimits()
  local.identity.packageBytes = ByteLimit(0)
  expect(executionRun(current, local), InputRefinementError.IdentityFailure)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "owned-input execution ARC release"
recordArcRelease("pvm_input_refinement", 1000, before, after)
echo "PVM input refinement passed"
echo "ARC_RELEASE cycles=1000 unchanged"
