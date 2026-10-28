# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Signed authored block composition plus unchanged empty-report traces; every verdict belongs
## to native tests.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "report_admission_arc_release"}

import std/assertions
import std/envvars
import std/strutils
import std/syncio
import std/sequtils
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/report_assignments as state_report_assignments
import ../../../src/state/report_policy as state_report_policy
import ../../../src/state/report_anchors as state_report_anchors
import ../../../src/state/report_packages as state_report_packages
import ../../../src/state/guarantee_credentials as state_guarantee_credentials
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
import ../../../src/state/safrole_transition as state_safrole_transition
import ../../../src/state/disputes as state_disputes
import ../../../src/state/availability as state_availability
import ../../../src/state/report_transition as state_report_transition
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/codec/header as codec_header
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/guarantees as codec_guarantees
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_consensus as codec_state_consensus
import ../../../src/codec/state_disputes as codec_state_disputes
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_history as codec_state_history
import ../../../src/codec/state_availability as codec_state_availability
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/state_authorization as codec_state_authorization
import ../../../src/codec/tickets as codec_tickets
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/owned as codec_owned
import ../../../src/codec/work_report as codec_work_report
import ../../../src/codec/composite as codec_composite
import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/crypto/extrinsic_commitment as crypto_extrinsic_commitment
import ../../../src/bandersnatch/bandersnatch as bandersnatch_bandersnatch
import ../../support/state_report_context
import ../../support/testing_arc_evidence
import ../../support/state_safrole_historical_refusal

## Controlled backend refusal never replaces successful verification.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

import ../../support/state_report_admission_context
import ../../support/state_core_activity_context
import ../../support/state_validator_activity_context

## Compare canonical state root and every known byte after pure planning, not just C(10).
proc unchanged(before, after: StateStoreSnapshot) =
  assert array[32, byte](before.commitment.root) == array[32, byte](after.commitment.root)
  for number in [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15]:
    let key = chapterKey(StateChapter(number))
    assert before.lookup(key).value.bytes == after.lookup(key).value.bytes # No report-stage writes at all.

## Repeated complete success and later-policy refusal must retire every retained plan and input capture.
proc cycle(context: Context, expected: ReportAdmissionError) =
  assert planBlockReports(context.staged, context.older, config()).error == expected

## Compose every report check, retain exact block/source owners and reject cross-context substitutes by API design.
proc boundaries(base: OwnedReport) =
  checkValidatorProjection()
  checkValidatorSource(base)
  checkCoreProjection(base)
  checkCoreSource(base)
  let context = authored(base)
  let original = context.staged.value.snapshot
  let preparedReports = prepareBlockReports(context.staged, config())
  assert preparedReports.error == ReportAdmissionError.None
  let demand = planPreparedReportLookupDemand(preparedReports.value, [])
  assert demand.error == ReportAdmissionError.None
  assert demand.value.missingLookups.value == 2
  assert uint64(demand.value.lookupDemandMaximum(ElementLimit(64)).value) == 1
  let completeDemand = planPreparedReportLookupDemand(preparedReports.value, context.older)
  assert completeDemand.error == ReportAdmissionError.None and
      completeDemand.value.missingLookups.value == 0
  assert planPreparedReportLookupDemand(default(PreparedReportAdmission), []).error ==
      ReportAdmissionError.InvalidTransition
  let wrongContext = planPreparedReportLookupDemand(preparedReports.value, [
      context.staged.value.admitted.admittedParent])
  assert wrongContext.error == ReportAdmissionError.AnchorFailure and wrongContext.anchorError ==
      ReportAnchorError.BrokenAncestry
  let completedReports = completeBlockReports(preparedReports.value, context.older)
  assert completedReports.error == ReportAdmissionError.None
  assert completedReports.value.reportCredentials.value.verifiedGuaranteeCount.value == 2
  assert completeBlockReports(default(PreparedReportAdmission), context.older).error ==
      ReportAdmissionError.InvalidTransition
  let admitted = planBlockReports(context.staged, context.older, config())
  assert admitted.error == ReportAdmissionError.None, $admitted.error
  let certificate = admitted.value
  assert certificate.reportCredentials.value.verifiedGuaranteeCount.value == 2
  let assignments = certificate.reportAssignments.value.reportAssignmentState.value
  assert availabilityInfo(assignments).value.present == 2
  assert uint32(availabilityAt(assignments, AssignmentCoreIndex(0)).value.registered) == 2
  let actual = certificate.reportBlockStage.value
  unchanged(original, actual.value.snapshot)
  unchanged(context.staged.value.admitted.admittedState, actual.value.admitted.admittedState)
  let first = certificate.reportCredentials.value.verifiedGuaranteeAt(0).value.report
  let fields = ownedReportInfo(first).value.header
  assert fields.stateRoot.bytes == array[32, byte](
      context.staged.value.admitted.admittedState.commitment.root) # Real correction is necessary: stored latest root is zero.
  let missing = BlockTransitionResult()
  assert prepareBlockReports(missing, config()).error == ReportAdmissionError.InvalidTransition
  assert planBlockReports(missing, [], config()).error == ReportAdmissionError.InvalidTransition
  assert default(AdmittedReports).reportAssignments.error == ReportAdmissionError.Uninitialized
  assert default(AdmittedReports).reportCredentials.error == ReportAdmissionError.Uninitialized
  assert default(AdmittedReports).reportBlockStage.error == ReportAdmissionError.Uninitialized
  # Independent domain substitutions fail before cryptographic checks.
  for mode in 0..<6:
    var bad = config()
    case mode
    of 0: bad.credentials.assignments.roster.cores = CoreCount(3) # Different roster core domain.
    of 1: bad.credentials.assignments.epochSlots = EpochSlots(24) # Different credential epoch.
    of 2: bad.packages.queues.epochSlots = EpochSlots(24) # Different pipeline ring extent.
    of 3: bad.ancestors.header.authorValidators = ValidatorCount(9) # Different header population ceiling.
    of 4: bad.packages.availability.guarantee.validators = ValidatorCount(9) # Different C(10) domain.
    else: bad.anchors.history.cores = CoreCount(3) # Different history domain.
    assert planBlockReports(context.staged, context.older, bad).error ==
        ReportAdmissionError.InvalidConfig
  var small = config()
  small.credentials.assignments.roster.maxBytes = ByteLimit(1)
  assert planBlockReports(context.staged, context.older, small).error ==
      ReportAdmissionError.LimitExceeded
  small = config()
  small.ancestors.headers = ElementLimit(1)
  let bounded = planBlockReports(context.staged, context.older, small)
  assert bounded.error == ReportAdmissionError.AnchorFailure and bounded.anchorError ==
      ReportAnchorError.LimitExceeded
  let noAncestor = planBlockReports(context.staged, [], config())
  assert noAncestor.error == ReportAdmissionError.AnchorFailure and noAncestor.anchorError ==
      ReportAnchorError.MissingLookupAnchor
  let fork = planBlockReports(context.staged, [context.staged.value.admitted.admittedParent],
      config())
  assert fork.error == ReportAdmissionError.AnchorFailure and fork.anchorError ==
      ReportAnchorError.BrokenAncestry
  # Later-stage refusals preserve the complete original staged map.
  for mode in [1, 3, 4, 6, 7, 8, 9, 10, 13]:
    var signedOptions1 = signedBlockFixtureConfig()
    signedOptions1.mode = mode
    let broken = authored(base, signedOptions1)
    let outcome = planBlockReports(broken.staged, broken.older, config())
    if mode in [6, 7, 13]:
      # Even with all lookup headers absent, known package/capacity failures refuse before requesting remote context.
      let prepared = prepareBlockReports(broken.staged, config())
      assert prepared.error == ReportAdmissionError.None
      let refusedDemand = planPreparedReportLookupDemand(prepared.value, [])
      assert refusedDemand.error == outcome.error
      if mode == 7:
        assert refusedDemand.assignmentError == outcome.assignmentError # Exact capacity reason survives discovery.
      else:
        assert refusedDemand.packageError == outcome.packageError # Missing parent queues are never fabricated.
    case mode
    of 1:
      assert outcome.error == ReportAdmissionError.PolicyFailure and outcome.policyError ==
          ReportPolicyError.Unauthorized # First report already passed.
    of 3:
      assert outcome.error == ReportAdmissionError.AnchorFailure and outcome.anchorError ==
          ReportAnchorError.InvalidRecentAnchor # Cannot supply a fabricated corrected history.
    of 4:
      assert outcome.error == ReportAdmissionError.AnchorFailure and outcome.anchorError ==
          ReportAnchorError.WrongLookupState # Child root, not loose lookup metadata.
    of 6:
      assert outcome.error == ReportAdmissionError.PackageFailure and outcome.packageError ==
          ReportPackageError.DuplicatePackage # Parent last accumulated row remains relevant.
    of 7:
      assert outcome.error == ReportAdmissionError.AssignmentFailure and outcome.assignmentError ==
          ReportAssignmentError.OccupiedCore # Actual post-assurance table still occupied.
    of 8:
      assert outcome.error == ReportAdmissionError.CredentialFailure and
          outcome.credentialError.error ==
          GuaranteeCredentialError.InvalidSignature # Reverify this block's exact credentials.
    of 9:
      assert outcome.error == ReportAdmissionError.MissingState # Missing parent history is not empty history.
    of 13:
      assert outcome.error == ReportAdmissionError.PackageFailure and outcome.packageError ==
          ReportPackageError.MissingState # No omitted parent-pipeline fallback.
    else:
      assert outcome.error == ReportAdmissionError.InvalidState # Exact history refuses suffix.
  var signedOptions2 = signedBlockFixtureConfig()
  signedOptions2.mode = 11
  let expired = authored(base, signedOptions2)
  assert availabilityInfo(expired.staged.value.availability.assuredAssignments).value.present == 0
  assert planBlockReports(expired.staged, expired.older, config()).error ==
      ReportAdmissionError.None # Use actual timeout-cleared table, not parent C(10).
  var signedOptions3 = signedBlockFixtureConfig()
  signedOptions3.mode = 12
  let duplicateExpired = authored(base, signedOptions3)
  assert availabilityInfo(duplicateExpired.staged.value.availability.assuredAssignments).value.present == 0
  let duplicate = planBlockReports(duplicateExpired.staged, duplicateExpired.older, config())
  assert duplicate.error == ReportAdmissionError.PackageFailure and duplicate.packageError ==
      ReportPackageError.DuplicatePackage # A freed core does not erase parent package exclusion.
  var signedOptions4 = signedBlockFixtureConfig()
  signedOptions4.reports = 0
  let empty = authored(base, signedOptions4)
  assert planBlockReports(empty.staged, empty.older, config()).error ==
      ReportAdmissionError.None # Empty batch still binds all context.
  failHash(1)
  let backend = planBlockReports(context.staged, context.older, config())
  assert backend.error == ReportAdmissionError.CredentialFailure and
      backend.credentialError.error == GuaranteeCredentialError.AssignmentFailure
  failHash(0)
  var detached = certificate.reportAssignments.value.reportAssignmentEntry.value
  detached.value[0] = detached.value[0] xor 1
  assert availabilityInfo(certificate.reportAssignments.value.reportAssignmentState.value).value.present == 2
  var signedOptions5 = signedBlockFixtureConfig()
  signedOptions5.mode = 1
  let refused = authored(base, signedOptions5)
  cycle(context, ReportAdmissionError.None)
  cycle(refused, ReportAdmissionError.PolicyFailure)
  let before = getOccupiedMem()
  for i in 0..<1000:
    if i mod 2 == 0: cycle(context, ReportAdmissionError.None) # Retire complete retained chain.
    else: cycle(refused, ReportAdmissionError.PolicyFailure) # Retire successful credential work before later refusal.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_report_admission", 1000, before, after)

## Reject unchanged historical blocks before report work; independent Thin blocks retain empty-report publication checks.
proc published() {.raises.} =
  var count = 0
  for line in readFile(getEnv("RAGNAROK_BLOCK_ADMISSION")).splitLines:
    if line.len == 0: continue # Terminal newline is not another case.
    let fields = line.splitWhitespace
    var entries: seq[StateEntry] = @[]
    for pair in fields[3].split(','):
      let parts = pair.split('=')
      let keyBytes = unhex(parts[0])
      var key = default(array[31, byte])
      for i in 0..<31: key[i] = keyBytes[i] # Exact original key identity.
      entries.add(StateEntry(key: StateKey(key), value: unhex(parts[1])))
    let bounds = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(100000),
        perValue: ByteLimit(20000000),
      totalValueBytes: ByteLimit(100000000), nodes: TrieNodeLimit(1000000)), writes: ElementLimit(
          5), writeValueBytes: ByteLimit(20000000))
    let created = newStateStore(entries, bounds)
    assert created.error == StateStoreError.None, fields[0] & " " & $created.error
    var state = created.value
    let candidate = decodeBlock(unhex(fields[1]), frame().frame).value.owner
    let parent = decodeHeader(unhex(fields[2]), config().ancestors.header).value.owner
    let original = state
    let staged = stage(state, candidate, parent)
    if not fields[0].startsWith("authored/"):
      # Historical credentials cannot authorize report planning or publication under the current Thin profile.
      assert staged.error == BlockTransitionError.SafroleFailure, fields[0] & " " & $staged.error
      checkHistoricalRefusal(fields[0], staged.safroleError)
      let failed = advanceBlockReports(state, candidate, parent, [], transitionConfig())
      assert failed.error == BlockReportError.StageFailure
      assert failed.stageError.error == BlockTransitionError.SafroleFailure
      checkHistoricalRefusal(fields[0], failed.stageError.safroleError)
      unchanged(original.snapshot.value, state.snapshot.value)
      inc count
      continue
    assert staged.error == BlockTransitionError.None
    let outcome = planBlockReports(staged, [], config())
    assert outcome.error == ReportAdmissionError.None, fields[0] & " " & $outcome.error
    assert outcome.value.reportCredentials.value.verifiedGuaranteeCount.value == 0
    var publishing = original
    let published = advanceBlockReports(publishing, candidate, parent, [], transitionConfig())
    assert published.error == BlockReportError.None, fields[0] & " publication " & $published.error
    unchanged(staged.value.snapshot, published.value.snapshot) # Empty reports add no C(10) change.
    inc count
  assert count == 13

## Missing fixtures fail, rather than quietly skipping authored or external evidence.
proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i]) # Canonical template hash is checked by fixture preparation.
  boundaries(decodeOwnedReport(bytes, 341).value)
  published()
  echo "PASS report admission: bound block stages, corrected history, exact credentials and rollback-free planning"
try:
  main() # Every implementation verdict remains native.
except:
  quit(2) # Missing trusted fixture transport cannot become success.
