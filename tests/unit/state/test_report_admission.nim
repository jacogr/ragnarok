# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Signed authored block composition plus unchanged empty-report traces; every verdict belongs
## to native tests.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "report_admission_arc_release"}

import std/[assertions, envvars, strutils, syncio, sequtils]
import ../../../src/state/[report_admission, report_assignments, report_policy, report_anchors,
  report_packages, guarantee_credentials, block_transition, block_admission, store,
  safrole_transition, disputes, availability, report_transition]
import ../../../src/codec/[block_codec, header, bounded, guarantees, assurances, state_safrole,
  state_consensus, state_disputes, state_layout, state_trie, state_history, state_availability,
  state_workqueues, state_authorization, tickets, report_owned, owned, work_report, composite]
import ../../../src/crypto/[primitives, extrinsic_commitment]
import ../../../src/bandersnatch/bandersnatch
import ../../support/[report_context, arc_evidence]

## Controlled backend refusal never replaces successful verification.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

import ../../support/[report_admission_context, core_activity_context]

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
  checkCoreProjection(base)
  checkCoreSource(base)
  let context = authored(base)
  let original = context.staged.value.snapshot
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
    let broken = authored(base, mode)
    let outcome = planBlockReports(broken.staged, broken.older, config())
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
  let expired = authored(base, 11)
  assert availabilityInfo(expired.staged.value.availability.assuredAssignments).value.present == 0
  assert planBlockReports(expired.staged, expired.older, config()).error ==
      ReportAdmissionError.None # Use actual timeout-cleared table, not parent C(10).
  let duplicateExpired = authored(base, 12)
  assert availabilityInfo(duplicateExpired.staged.value.availability.assuredAssignments).value.present == 0
  let duplicate = planBlockReports(duplicateExpired.staged, duplicateExpired.older, config())
  assert duplicate.error == ReportAdmissionError.PackageFailure and duplicate.packageError ==
      ReportPackageError.DuplicatePackage # A freed core does not erase parent package exclusion.
  let empty = authored(base, reports = 0)
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
  let refused = authored(base, 1)
  cycle(context, ReportAdmissionError.None)
  cycle(refused, ReportAdmissionError.PolicyFailure)
  let before = getOccupiedMem()
  for i in 0..<1000:
    if i mod 2 == 0: cycle(context, ReportAdmissionError.None) # Retire complete retained chain.
    else: cycle(refused, ReportAdmissionError.PolicyFailure) # Retire successful credential work before later refusal.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("report_admission", 1000, before, after)

## Reuse unchanged published signed blocks, explicitly limited to their empty report batches.
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
    assert staged.error == BlockTransitionError.None
    let outcome = planBlockReports(staged, [], config())
    assert outcome.error == ReportAdmissionError.None, fields[0] & " " & $outcome.error
    assert outcome.value.reportCredentials.value.verifiedGuaranteeCount.value == 0
    var publishing = original
    let published = advanceBlockReports(publishing, candidate, parent, [], transitionConfig())
    assert published.error == BlockReportError.None, fields[0] & " publication " & $published.error
    unchanged(staged.value.snapshot, published.value.snapshot) # Empty reports add no C(10) change.
    inc count
  assert count == 10

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
