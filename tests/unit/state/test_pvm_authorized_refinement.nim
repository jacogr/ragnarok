# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_authorized_refinement_arc_release"}

## Genuine combined source fixtures verify authorization gating, trace propagation, atomic children and immutable provenance.

import std/[assertions, syncio]
import ../../../src/state/[authorized_refinement, authorization_invocation, refinement_report,
  refinement_digest, refinement_dispatch, refinement_bootstrap, refinement_outcome, store]
import ../../../src/codec/[bounded, composite, work_digest, work_package, work_report]
import ../../../src/pvm/[host_fetch, refinement_exports]
import ../../../src/chain/parameters
import ../../support/[pvm_authorized_refinement, pvm_report_results, pvm_refinement_outcome, arc_evidence]

let halt = @[50'u8, 0]
let authCode = @[refinementImmediate(7, 65536), refinementImmediate(8, 3), halt]
let fetchTrace = @[refinementImmediate(7, 196608), refinementImmediate(8, 0), refinementImmediate(9, 3),
  refinementImmediate(10, 2), @[10'u8, 2], refinementImmediate(7, 196608), refinementImmediate(8,
      3), halt]
let exporting = @[refinementImmediate(7, 65536), refinementImmediate(8, 3), @[10'u8, 8],
  fetchTrace[0], fetchTrace[1], fetchTrace[2], fetchTrace[3], fetchTrace[4], fetchTrace[5],
      fetchTrace[6], halt]
let fixture = authorizedFixture(authCode, [reportGuest(fetchTrace), reportGuest(exporting, 1)])
let original = fixture.authorization
let complete = prepareAuthorizedRefinement(original, fixture.inputs, authorizedLimits()).value
let info = complete.authorizedInfo.value
assert uint64(info.core) == 0x1234 and uint32(info.host) == 77 and uint32(info.anchor) == 20
assert info.items == 2 and uint64(info.exports) == 1 and info.traceBytes == 3 and info.blobBytes ==
    9, "initial report projection"
assert uint64(info.authorizationGasUsed) == uint64(original.authorizationInfo.value.gasUsed)
let digests = complete.authorizedDigests.value
let report = digests.digestReport.value
assert uint64(report.reportInfo.value.core) == 0x1234
assert report.reportTrace.value == @[11'u8, 12, 13]
for index in 0..<2:
  let digest = digests.digestAt(FetchItemIndex(uint64(index))).value
  assert digest.digestInfo.value.kind == WorkKind.Success, "item " & $index & " kind " &
      $digest.digestInfo.value.kind
  assert uint32(digest.digestInfo.value.service) == uint32(42+index)
  assert digest.digestOutput.value == @[11'u8, 12,
      13] # RO auth bytes differ from the refinement fixture's original RW bytes 21/22/23.
  assert uint64(digest.digestInfo.value.refine.gasUsed) > 80
let segment = array[4104, byte](report.reportItem(FetchItemIndex(1)).value.refinedSegment(
    ExportCount(0)).value)
assert segment[0] == 11 and segment[1] == 12 and segment[2] == 13
for index in 3..<4104: assert segment[index] == 0
assert sameStateSnapshot(complete.authorizedSource.value.authorizationState.value, fixture.state)
assert complete.authorizedSource.value.authorizationPackage.value.workPackageInfo.value.items == 2
# Caller replacement of every input handle after authorization cannot rebind the production composition.
var changedFixture = fixture
changedFixture.state = default(StateStoreSnapshot)
changedFixture.package = default(OwnedWorkPackage)
changedFixture.parameters = default(Parameters)
changedFixture.authorization = default(AuthorizationInvocation)
let replay = prepareAuthorizedRefinement(original, changedFixture.inputs, authorizedLimits()).value
assert replay.authorizedDigests.value.digestAt(FetchItemIndex(1)).value.digestBytes.value ==
    digests.digestAt(FetchItemIndex(1)).value.digestBytes.value
var changedTrace = complete.authorizedSource.value.authorizationTrace.value
changedTrace[0] = 255
var changedInfo = complete.authorizedInfo.value
changedInfo.core = CoreIndex(0)
assert complete.authorizedDigests.value.digestReport.value.reportTrace.value == @[11'u8, 12, 13]
assert uint64(complete.authorizedInfo.value.core) == 0x1234
# Empty authorization trace is valid and reaches refinement as present-empty, without allocating under the local trace cap.
let emptyAuth = @[refinementImmediate(8, 0), halt]
let emptyItem = @[refinementImmediate(8, 0), halt]
let empty = authorizedFixture(emptyAuth, [reportGuest(emptyItem)])
var cap = authorizedLimits()
cap.trace = FetchTraceLimit(0)
let emptyDone = prepareAuthorizedRefinement(empty.authorization, empty.inputs, cap).value
assert emptyDone.authorizedInfo.value.traceBytes == 0 and
    emptyDone.authorizedInfo.value.blobBytes == 0
assert emptyDone.authorizedDigests.value.digestAt(FetchItemIndex(0)).value.digestInfo.value.kind ==
    WorkKind.Success
# Protocol errors and oversized authorization precede invalid external inputs and all child/local policies.
for variant in 0..<4:
  let code = if variant == 0 or variant == 1: @[halt]
    elif variant == 2: @[@[0'u8]] else: @[refinementImmediate(9, high(uint64)), refinementImmediate(
        10, 2), @[10'u8, 2], halt]
  let rejected = authorizedFixture(code, [reportGuest(fetchTrace)], authCodeSize = (if variant ==
      1: 64001 else: 0), missingAuth = variant == 0)
  let result = prepareAuthorizedRefinement(rejected.authorization, default(RefinementInputs),
      default(AuthorizedRefinementLimits))
  let expected = if variant == 0: WorkKind.Bad elif variant == 1: WorkKind.Big
    elif variant == 2: WorkKind.Panic else: WorkKind.OutOfGas
  assert result.error == AuthorizedRefinementError.AuthorizationRejected and
      result.authorizationKind == expected, "authorization refusal variant " & $variant &
          " error " & $result.error & " kind " & $result.authorizationKind
for size in [49152, 49153]:
  let large = authorizedFixture([refinementImmediate(7, 196608), refinementImmediate(8, uint64(
      size)), halt],
    [reportGuest(emptyItem)], authCodeSize = 64000)
  assert large.authorization.authorizationInfo.value.kind == WorkKind.Success,
      "large authorization size " & $size & " kind " &
      $large.authorization.authorizationInfo.value.kind
  if size == 49152:
    let done = prepareAuthorizedRefinement(large.authorization, large.inputs, authorizedLimits()).value
    assert done.authorizedInfo.value.blobBytes == 49152
    assert done.authorizedDigests.value.digestAt(FetchItemIndex(0)).value.digestOutput.value.len == 0
  else:
    let refused = prepareAuthorizedRefinement(large.authorization, default(RefinementInputs),
        default(AuthorizedRefinementLimits))
    assert refused.error == AuthorizedRefinementError.TraceTooLarge # This is report E, not a fabricated auth Oversize work error.
# An accepted large auth trace consumes shared blob budget; I replaces the item's output and declared exports atomically.
let budget = authorizedFixture([refinementImmediate(7, 196608), refinementImmediate(8, 49150),
    halt], [reportGuest(exporting, 1)], authCodeSize = 64000)
let budgetDone = prepareAuthorizedRefinement(budget.authorization, budget.inputs, authorizedLimits()).value
let discarded = budgetDone.authorizedDigests.value.digestAt(FetchItemIndex(0)).value
assert discarded.digestInfo.value.kind == WorkKind.Oversize
assert uint64(discarded.digestInfo.value.refine.exports) == 1 and uint64(
    discarded.digestInfo.value.refine.gasUsed) > 3521
assert budgetDone.authorizedInfo.value.blobBytes == 49150
let zero = array[4104, byte](discarded.digestSource.value.refinedSegment(ExportCount(0)).value)
for octet in zero: assert octet == 0
# Local trace, capture, execution and final digest budgets retain their stage and publish no partial result.
cap = authorizedLimits()
cap.trace = FetchTraceLimit(2)
assert prepareAuthorizedRefinement(original, fixture.inputs, cap).error ==
    AuthorizedRefinementError.LimitExceeded
let inputs = prepareAuthorizedRefinement(original, default(RefinementInputs), authorizedLimits())
assert inputs.error == AuthorizedRefinementError.RefinementFailure
assert inputs.refinementError.invocationError.bootstrapError ==
    RefinementBootstrapError.InvalidInputs
cap = authorizedLimits()
cap.refinement.bootstrap.preimage = ByteLimit(0)
let bootstrap = prepareAuthorizedRefinement(original, fixture.inputs, cap)
assert bootstrap.error == AuthorizedRefinementError.RefinementFailure
assert bootstrap.refinementError.bootstrapError == RefinementBootstrapError.LimitExceeded
# Select current memory compilation explicitly so the nonempty zero-byte-policy witness reaches its intended local refusal.
let late = authorizedFixture(authCode, [reportGuest(fetchTrace), reportGuest([refinementImmediate(7,
    0), refinementImmediate(8, 65536), refinementImmediate(9, 1), @[10'u8, 9], halt])])
let host = prepareAuthorizedRefinement(late.authorization, late.inputs, authorizedLimits())
assert host.error == AuthorizedRefinementError.RefinementFailure,
    "nonempty compile exceeds the zero program-byte policy: " & $host.error
assert host.refinementError.invocationError.error == RefinementInvocationError.HostFailure
assert host.refinementError.invocationError.hostError == RefinementDispatchError.LimitExceeded
cap = authorizedLimits()
cap.digests.totalEncoding = ByteLimit(1)
let projected = prepareAuthorizedRefinement(original, fixture.inputs, cap)
assert projected.error == AuthorizedRefinementError.DigestFailure and projected.digestError ==
    RefinementDigestError.LimitExceeded
assert prepareAuthorizedRefinement(default(AuthorizationInvocation), default(RefinementInputs),
    cap).error == AuthorizedRefinementError.InvalidAuthorization
assert default(AuthorizedRefinement).authorizedInfo.error == AuthorizedRefinementError.Uninitialized
assert default(AuthorizedRefinement).authorizedSource.error ==
    AuthorizedRefinementError.Uninitialized
assert default(AuthorizedRefinement).authorizedDigests.error ==
    AuthorizedRefinementError.Uninitialized
proc detached(): AuthorizedRefinement =
  ## Return only the bound result after original caller fixture/input handles retire.
  let source = authorizedFixture(authCode, [reportGuest(fetchTrace)])
  prepareAuthorizedRefinement(source.authorization, source.inputs, authorizedLimits()).value
assert detached().authorizedDigests.value.digestAt(FetchItemIndex(0)).value.digestOutput.value == @[
    11'u8, 12, 13]
proc cycle() =
  ## Fresh auth/state/package/report/digest owners and late-refused private candidates release completely each time.
  let source = authorizedFixture(authCode, [reportGuest(fetchTrace), reportGuest(exporting, 1)])
  let done = prepareAuthorizedRefinement(source.authorization, source.inputs, authorizedLimits()).value
  assert done.authorizedInfo.value.items == 2
  var limits = authorizedLimits()
  limits.digests.totalEncoding = ByteLimit(1)
  assert prepareAuthorizedRefinement(source.authorization, source.inputs, limits).error ==
      AuthorizedRefinementError.DigestFailure
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_authorized_refinement", 1000, before, after)
echo "PVM authorized refinement passed"
echo "ARC_RELEASE cycles=1000 unchanged"
