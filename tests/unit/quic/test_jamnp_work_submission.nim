# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_work_submission_arc_release"}

## Actual authorizer execution gates exact builder messages and independent imported-segment proofs.

import std/[assertions, syncio]
import ../../../src/jamnp-s/work_submission
import ../../../src/codec/[bounded, composite, assurances]
import ../../../src/codec/work/[package as work_package, report as work_report, digest]
import ../../../src/codec/state/[authorization as state_authorization, history as state_history,
    layout as state_layout, trie as state_trie]
import ../../../src/state/[store, input_refinement, auditable_bundle, extrinsic_inputs]
import "../../../src/state/import/inputs" as import_inputs
import "../../../src/state/import/justification" as import_justification
import ../../../src/state/authorization/invocation as authorization_invocation
import ../../../src/state/report/identity as report_identity
import ../../../src/pvm/host/fetch as host_fetch
import ../../../src/chain/parameters
import ../../../src/crypto/primitives
import ../../support/[pvm_input_refinement, pvm_authorization_invoke, pvm_report_results,
  pvm_refinement_outcome, pvm_import_inputs, pvm_import_justification, pvm_extrinsic_inputs,
  pvm_import_vectors, arc_evidence]

type
  Fixture = object ## Test-owned wire buffers retire independently of immutable headers, grants and completed inputs.
    input: InputFixture
    package, first, extrinsics, segments, proofs: seq[byte]
    limits: WorkSubmissionLimits

proc fixture(external = true, rejected = false, wrongPool = false, wrongMapping = false,
    missingMapping = false, conflictingMapping = false): Fixture =
  ## Commit genuine PVM code, selected C(1) authorizer and C(3) package mapping into a private original source.
  result = default(Fixture)
  let code = if rejected: @[refinementImmediate(7, 0), refinementImmediate(8, 0), @[0'u8]]
    else: @[refinementImmediate(8, 0), @[50'u8, 0]]
  result.input = executionFixture(code, [fetchedGuest(4), fetchedGuest(4)], external = external)
  var params = result.input.parameters.encodeParameters
  params[24] = 2
  params[25] = 0 # The existing CPU fixture's E2-max profile becomes an actual two-core JAM population.
  result.input.parameters = decodeParameters(params).value
  result.limits = WorkSubmissionLimits(pools: AuthorizationConfig(cores: CoreCount(2),
    maxHashes: ElementLimit(16), maxBytes: ByteLimit(1024)), history: HistoryConfig(
        cores: CoreCount(2),
    blocks: ElementLimit(8), perBlock: ElementLimit(2), totalPackages: ElementLimit(16),
    peaks: ElementLimit(64), maxBytes: ByteLimit(4096)), authorization: authorizationLimits(),
    extrinsics: extrinsicLimits(), imports: inputLimits(), proof: importLimits())
  let info = result.input.package.workPackageInfo.value
  var authorizer = newSeq[byte](32+info.configurationBytes)
  let codeHash = array[32, byte](info.codeHash)
  for index in 0..<32: authorizer[index] = codeHash[index]
  assert result.input.package.copyPackageBlob(PackageBlob.Configuration,
    authorizer.toOpenArray(32, authorizer.high)).error == PackageError.None
  var hash = array[32, byte](blake2b256(authorizer).value)
  if wrongPool: hash[0] = hash[0] xor 1 # An actual different hash cannot select authorization for this package.
  let pools = authorizationEntry(AuthorizationKind.Pools, [@[AuthorizerHash(bytes: hash)],
    newSeq[AuthorizerHash](0)], result.limits.pools).value
  var root = SegmentRoot(bytes: ThreeRoot)
  if wrongMapping: root.bytes[0] = root.bytes[0] xor 1
  var historyRows = @[HistoryBlock(slot: HistorySlot(10), packages: @[ReportedPackage(
      package: inputKey(1), segment: root)])]
  if missingMapping: historyRows[0].packages = @[] # A selected history can be genuine while lacking this dependency.
  if conflictingMapping:
    var otherRoot = root
    otherRoot.bytes[0] = otherRoot.bytes[0] xor 1
    historyRows.add(HistoryBlock(slot: HistorySlot(11), packages: @[ReportedPackage(
        package: inputKey(1), segment: otherRoot)]))
  let history = historyStateEntry(HistoryState(blocks: historyRows), result.limits.history).value
  var state = forkStateStore(result.input.state).value
  assert state.apply([StateWrite(kind: StateWriteKind.Put, key: pools.key, value: pools.value),
    StateWrite(kind: StateWriteKind.Put, key: history.key, value: history.value)]).error ==
        StateStoreError.None
  result.input.state = state.snapshot.value
  result.package = newSeq[byte](info.consumed)
  assert result.input.package.encodeOwnedWorkPackage(result.package).error == PackageError.None
  result.first = @[0'u8, 0, byte(if external: 1 else: 0)] # Independent E2 core and canonical mapping-count prefix.
  if external:
    # The original fixture deliberately mixes a direct root and a package-relative import.
    for octet in inputKey(1).bytes: result.first.add(octet)
    for octet in ThreeRoot: result.first.add(octet)
    result.extrinsics = @[97'u8, 98, 99, 97, 98, 100]
    for index in 0..<2:
      let proof = inputProof(index)
      for octet in array[4104, byte](proof.verifiedImportSegment.value): result.segments.add(octet)
      for octet in proof.verifiedImportProof.value: result.proofs.add(octet)

proc header(f: Fixture): WorkSubmissionHeader =
  ## Headers are independently decoded from the actual separate CE146 payloads.
  let decoded = decodeWorkSubmission(WorkSubmissionKind.Bundle, f.first, f.package,
    fullPackageConfig(ByteLimit(204800)))
  assert decoded.error == WorkSubmissionError.None, "CE146 header: " & $decoded.error
  decoded.value

proc grant(f: Fixture): AuthorizedWorkSubmission =
  ## No test-issued grant bit or fake PVM success enters the body verifier.
  let checked = authorizeWorkSubmission(f.header, f.input.state, f.input.parameters, f.limits)
  assert checked.error == WorkSubmissionError.None, "real authorization: " & $checked.error
  checked.value

proc complete(f: Fixture): VerifiedImportInputs =
  ## Original manifests partition all three independently framed body payloads.
  let checked = completeBundleSubmission(f.grant, f.extrinsics, f.segments, f.proofs, f.limits)
  assert checked.error == WorkSubmissionError.None, "real body: " & $checked.error
  checked.value
let full = fixture()
let accepted = full.complete
assert accepted.importInputsInfo.value.entries == 2
assert accepted.importInputsExtrinsics.value.extrinsicInputsInfo.value.payloadBytes == 6
let refined = runInputRefinement(full.input.state, accepted, CoreIndex(0), full.input.parameters,
    executionLimits())
assert refined.error == InputRefinementError.None
let bundle = prepareAuditableBundle(refined.value, ByteLimit(13904950))
assert bundle.error == AuditableBundleError.None, "wire inputs must feed a genuine auditable execution bundle"
# Both fetched extrinsics remain distinguishable through actual host execution, not just a shape-only decoder.
assert refined.value.inputRefinementIdentity.value.identityInfo.value.core.uint64 == 0
let empty = fixture(external = false)
assert empty.complete.importInputsInfo.value.entries == 0
# CE133 contains core and package in its first payload and binds the separately acquired original witnesses.
var first133 = @[0'u8, 0]
for octet in full.package: first133.add(octet)
let packageHeader = decodeWorkSubmission(WorkSubmissionKind.Package, first133, [],
    fullPackageConfig(ByteLimit(204800))).value
let packageGrant = authorizeWorkSubmission(packageHeader, full.input.state, full.input.parameters,
    full.limits).value
assert completePackageSubmission(packageGrant, full.extrinsics, [@[inputProof(0)], @[inputProof(1)]],
  [inputPair(1)], full.limits).error == WorkSubmissionError.None
assert completePackageSubmission(packageGrant, full.extrinsics, [@[inputProof(0)]],
  [inputPair(1)], full.limits).bindingError == ImportInputsError.InvalidShape
assert completeBundleSubmission(packageGrant, full.extrinsics, full.segments, full.proofs,
    full.limits).error == WorkSubmissionError.InvalidMessage
assert completePackageSubmission(full.grant, full.extrinsics, [], [], full.limits).error ==
    WorkSubmissionError.InvalidMessage

proc grantedPackage(f: Fixture): AuthorizedWorkSubmission =
  ## Independent CE133 framing retains the same actual package and source authorizer as the bundle control.
  var wire = @[0'u8, 0]
  for octet in f.package: wire.add(octet)
  let header = decodeWorkSubmission(WorkSubmissionKind.Package, wire, [], fullPackageConfig(
      ByteLimit(204800))).value
  authorizeWorkSubmission(header, f.input.state, f.input.parameters, f.limits).value

proc fetchedReply(f: Fixture): seq[byte] =
  ## Independent literal E4 prefixes frame frozen segment/proof witnesses rather than using the production response encoder.
  result = @[]
  for body in [f.segments, f.proofs]:
    for octet in 0..<4: result.add(byte((body.len shr (octet*8)) and 255))
    for value in body: result.add(value)
let plan = prepareWorkImportPlan(packageGrant, full.limits)
assert plan.error == WorkSubmissionError.None
var request = plan.value.workImportRequest.value
assert request.len == 70
for occurrence in 0..<2:
  # Direct and C(3)-relative references converge to the independent frozen root, preserving their distinct indices.
  for octet in 0..<32: assert request[occurrence*35+octet] == ThreeRoot[octet]
  assert request[occurrence*35+32] == 1
  assert request[occurrence*35+33] == byte(occurrence)
  assert request[occurrence*35+34] == 0
request[0] = request[0] xor 1
assert plan.value.workImportRequest.value[0] == ThreeRoot[0]
let reply = fetchedReply(full)
let fetched = completeFetchedPackageSubmission(packageGrant, plan.value, full.extrinsics, reply, full.limits)
assert fetched.error == WorkSubmissionError.None
assert runInputRefinement(full.input.state, fetched.value, CoreIndex(0), full.input.parameters,
  executionLimits()).error == InputRefinementError.None
let otherGrant = full.grantedPackage
assert completeFetchedPackageSubmission(otherGrant, plan.value, full.extrinsics, reply,
    full.limits).error == WorkSubmissionError.InvalidSource
assert prepareWorkImportPlan(full.grant, full.limits).error == WorkSubmissionError.InvalidMessage
assert prepareWorkImportPlan(default(AuthorizedWorkSubmission), full.limits).error ==
    WorkSubmissionError.Uninitialized
assert default(WorkImportPlan).workImportRequest.error == WorkSubmissionError.Uninitialized
let missing = fixture(missingMapping = true)
assert prepareWorkImportPlan(missing.grantedPackage, missing.limits).error ==
    WorkSubmissionError.UnavailableMapping
let conflict = fixture(conflictingMapping = true)
assert prepareWorkImportPlan(conflict.grantedPackage, conflict.limits).error ==
    WorkSubmissionError.InvalidMappings
let emptyGrant = empty.grantedPackage
let emptyPlan = prepareWorkImportPlan(emptyGrant, empty.limits).value
assert emptyPlan.workImportRequest.value.len == 0
assert completeFetchedPackageSubmission(emptyGrant, emptyPlan, [], [], empty.limits).error ==
    WorkSubmissionError.None
assert completeFetchedPackageSubmission(emptyGrant, emptyPlan, [], empty.fetchedReply,
    empty.limits).error == WorkSubmissionError.None
for length in 0..<reply.len:
  # No truncated framing, leaf or late proof may expose a verified prefix.
  assert completeFetchedPackageSubmission(packageGrant, plan.value, full.extrinsics,
    reply.toOpenArray(0, length-1), full.limits).error != WorkSubmissionError.None
var extra = reply
extra.add(0)
assert completeFetchedPackageSubmission(packageGrant, plan.value, full.extrinsics, extra,
    full.limits).error == WorkSubmissionError.InvalidMessage
var altered = reply
altered[4] = altered[4] xor 1
assert completeFetchedPackageSubmission(packageGrant, plan.value, full.extrinsics, altered,
    full.limits).importError == ImportJustificationError.RootMismatch
var oversized = reply
for index in 0..<4: oversized[index] = 255
assert completeFetchedPackageSubmission(packageGrant, plan.value, full.extrinsics, oversized,
    full.limits).error == WorkSubmissionError.InvalidMessage
var capped = full.limits
capped.imports.witnessBytes = ByteLimit(8208)
assert completeFetchedPackageSubmission(packageGrant, plan.value, full.extrinsics, reply,
    capped).error == WorkSubmissionError.LimitExceeded
capped.imports.entries = ElementLimit(1)
assert prepareWorkImportPlan(packageGrant, capped).error == WorkSubmissionError.LimitExceeded
# Exact header extents, finite count domains and canonical dictionary order are enforced before authorization.
let config = fullPackageConfig(ByteLimit(204800))
for length in 0..<full.first.len:
  assert decodeWorkSubmission(WorkSubmissionKind.Bundle, full.first.toOpenArray(0, length-1),
      full.package, config).error != WorkSubmissionError.None
for length in 0..<full.package.len:
  assert decodeWorkSubmission(WorkSubmissionKind.Bundle, full.first, full.package.toOpenArray(0,
      length-1), config).error != WorkSubmissionError.None
var changed = full.package
changed.add(0)
assert decodeWorkSubmission(WorkSubmissionKind.Bundle, full.first, changed, config).error ==
    WorkSubmissionError.InvalidMessage
assert decodeWorkSubmission(WorkSubmissionKind.Package, first133, [0'u8], config).error ==
    WorkSubmissionError.InvalidMessage
assert decodeWorkSubmission(WorkSubmissionKind.Bundle, [0'u8, 0, 128, 0], full.package,
    config).error == WorkSubmissionError.InvalidMappings
assert decodeWorkSubmission(WorkSubmissionKind.Bundle, [0'u8, 0, 9], full.package, config).error ==
    WorkSubmissionError.LimitExceeded
assert decodeWorkSubmission(WorkSubmissionKind.Bundle, full.first, newSeq[byte](204801),
    config).error == WorkSubmissionError.LimitExceeded
assert decodeWorkSubmission(WorkSubmissionKind.Package, newSeq[byte](204803), [], config).error ==
    WorkSubmissionError.LimitExceeded
# Wrong selected core, actual pool membership, current mapping and genuine authorizer rejection are distinct.
let wrongPool = fixture(wrongPool = true)
assert authorizeWorkSubmission(wrongPool.header, wrongPool.input.state, wrongPool.input.parameters,
    wrongPool.limits).error == WorkSubmissionError.Unauthorized
let wrongMapping = fixture(wrongMapping = true)
assert authorizeWorkSubmission(wrongMapping.header, wrongMapping.input.state,
    wrongMapping.input.parameters, wrongMapping.limits).error ==
    WorkSubmissionError.UnavailableMapping
let rejected = fixture(rejected = true)
assert authorizeWorkSubmission(rejected.header, rejected.input.state, rejected.input.parameters,
    rejected.limits).error == WorkSubmissionError.AuthorizationRejected
var otherCore = full.first
otherCore[0] = 1
let coreHeader = decodeWorkSubmission(WorkSubmissionKind.Bundle, otherCore, full.package, config).value
assert authorizeWorkSubmission(coreHeader, full.input.state, full.input.parameters,
    full.limits).error == WorkSubmissionError.Unauthorized
otherCore[0] = 2
assert authorizeWorkSubmission(decodeWorkSubmission(WorkSubmissionKind.Bundle, otherCore,
    full.package, config).value,
  full.input.state, full.input.parameters, full.limits).error == WorkSubmissionError.InvalidMessage
# Invalid source/policy and genuine authorization child failures remain distinct from guest rejection.
assert authorizeWorkSubmission(default(WorkSubmissionHeader), full.input.state,
  full.input.parameters, full.limits).error == WorkSubmissionError.Uninitialized
assert default(WorkSubmissionHeader).submissionInfo.error == WorkSubmissionError.Uninitialized
assert default(AuthorizedWorkSubmission).submissionInfo.error == WorkSubmissionError.Uninitialized
assert authorizeWorkSubmission(full.header, default(StateStoreSnapshot), full.input.parameters,
  full.limits).error == WorkSubmissionError.InvalidSource
assert authorizeWorkSubmission(full.header, full.input.state, default(Parameters),
  full.limits).error == WorkSubmissionError.InvalidPolicy
var authCap = full.limits
authCap.authorization.preimage = ByteLimit(0)
let authFailure = authorizeWorkSubmission(full.header, full.input.state, full.input.parameters, authCap)
assert authFailure.error == WorkSubmissionError.AuthorizationFailure
assert authFailure.authorizationError.error == AuthorizationInvocationError.LimitExceeded
assert authorizeWorkSubmission(rejected.header, rejected.input.state, rejected.input.parameters,
  rejected.limits).authorizationKind == WorkKind.Panic
# Canonical mapping keys are neither silently sorted nor accepted if duplicated or unrelated.
var duplicate = full.first
duplicate[2] = 2
for index in 3..<full.first.len: duplicate.add(full.first[index])
assert decodeWorkSubmission(WorkSubmissionKind.Bundle, duplicate, full.package, config).error ==
    WorkSubmissionError.InvalidMappings
var unrelated = full.first
unrelated[3] = 2
assert decodeWorkSubmission(WorkSubmissionKind.Bundle, unrelated, full.package, config).error ==
    WorkSubmissionError.InvalidMappings
# Body mutation must reach real commitment/proof checks; framing errors cannot masquerade as cryptographic failure.
let authorized = full.grant
var badExtrinsics = full.extrinsics
badExtrinsics[0] = badExtrinsics[0] xor 1
assert completeBundleSubmission(authorized, badExtrinsics, full.segments, full.proofs,
    full.limits).extrinsicError == ExtrinsicInputsError.HashMismatch
var badSegments = full.segments
badSegments[4104] = badSegments[4104] xor 1
assert completeBundleSubmission(authorized, full.extrinsics, badSegments, full.proofs,
    full.limits).importError == ImportJustificationError.RootMismatch
var badProofs = full.proofs
badProofs[1] = badProofs[1] xor 1
assert completeBundleSubmission(authorized, full.extrinsics, full.segments, badProofs,
    full.limits).importError == ImportJustificationError.RootMismatch
assert completeBundleSubmission(authorized, full.extrinsics.toOpenArray(0, 4), full.segments,
    full.proofs, full.limits).error == WorkSubmissionError.InvalidMessage
assert completeBundleSubmission(authorized, full.extrinsics, full.segments.toOpenArray(0,
    full.segments.high-1), full.proofs, full.limits).error == WorkSubmissionError.InvalidMessage
for length in 0..<full.proofs.len:
  assert completeBundleSubmission(authorized, full.extrinsics, full.segments,
      full.proofs.toOpenArray(0, length-1), full.limits).error != WorkSubmissionError.None
var suffix = full.proofs
suffix.add(0)
assert completeBundleSubmission(authorized, full.extrinsics, full.segments, suffix,
    full.limits).error == WorkSubmissionError.InvalidMessage
var cap = full.limits
cap.imports.witnessBytes = ByteLimit(8208)
assert completeBundleSubmission(authorized, full.extrinsics, full.segments, full.proofs,
    cap).error == WorkSubmissionError.LimitExceeded
cap = full.limits
cap.proof.siblings = ElementLimit(0)
assert completeBundleSubmission(authorized, full.extrinsics, full.segments, full.proofs,
    cap).importError == ImportJustificationError.LimitExceeded
assert completeBundleSubmission(default(AuthorizedWorkSubmission), [], [], [], full.limits).error ==
    WorkSubmissionError.Uninitialized
# Replacing original wire buffers cannot alter retained headers or grants; detached result bytes cannot mutate inputs.
var replaced = full
let retained = replaced.grant
replaced.package = @[]
replaced.first = @[]
assert completeBundleSubmission(retained, full.extrinsics, full.segments, full.proofs,
    full.limits).value.importInputsInfo.value.entries == 2

proc cycle(bad: seq[byte]) =
  ## Release source-bearing grant, successful inputs and late failed proof prefixes on every iteration.
  let selected = full.grantedPackage
  let imports = prepareWorkImportPlan(selected, full.limits).value
  assert completeFetchedPackageSubmission(selected, imports, full.extrinsics, full.fetchedReply,
      full.limits).error == WorkSubmissionError.None
  var fetchedFailure = full.fetchedReply
  fetchedFailure[4108] = fetchedFailure[4108] xor 1 # A valid first proof precedes a bad second fetched segment.
  assert completeFetchedPackageSubmission(selected, imports, full.extrinsics, fetchedFailure,
      full.limits).error == WorkSubmissionError.ImportFailure
  let completed = full.complete
  assert completed.importInputsInfo.value.entries == 2
  assert completeBundleSubmission(full.grant, full.extrinsics, bad, full.proofs,
      full.limits).error == WorkSubmissionError.ImportFailure
cycle(badSegments)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(badSegments) # Repeated grants and proof/input owners exercise balanced ARC release.
let after = getOccupiedMem()
assert before == after, "work submission ARC release"
recordArcRelease("jamnp_work_submission", 1000, before, after)
echo "JAMNP-S work submission passed"
echo "ARC_RELEASE cycles=1000 unchanged"

proc largeHeaders() =
  ## GP payload capacity exceeds the old200KiB upload cap; configured byte limits still apply before parsing/copying.
  let package = WorkPackage(items: @[WorkItem(refineGas: Gas(1), accumulateGas: Gas(1),
      payload: newSeq[byte](262144))])
  let policy = fullPackageConfig(ByteLimit(MaxBundleBytes))
  var bytes = newSeq[byte](270000)
  let encoded = encodeWorkPackage(package, policy, bytes)
  assert encoded.error == PackageError.None
  bytes.setLen(encoded.value)
  assert bytes.len > 204800
  let bundle = decodeWorkSubmission(WorkSubmissionKind.Bundle, [0'u8, 0, 0], bytes, policy)
  assert bundle.error == WorkSubmissionError.None
  assert bundle.value.submissionInfo.value.packageBytes == bytes.len
  var first = @[0'u8, 0]
  for octet in bytes: first.add(octet)
  let separate = decodeWorkSubmission(WorkSubmissionKind.Package, first, [], policy)
  assert separate.error == WorkSubmissionError.None
  assert separate.value.submissionInfo.value.packageBytes == bytes.len
  var bounded = policy
  bounded.maxBytes = ByteLimit(uint64(bytes.len-1))
  let denied = decodeWorkSubmission(WorkSubmissionKind.Bundle, [0'u8, 0, 0], bytes, bounded)
  assert denied.error == WorkSubmissionError.LimitExceeded
  let oversized = decodeWorkSubmission(WorkSubmissionKind.Bundle, [0'u8, 0, 0], newSeq[byte](
      MaxBundleBytes+1), policy)
  assert oversized.error == WorkSubmissionError.LimitExceeded
largeHeaders()
