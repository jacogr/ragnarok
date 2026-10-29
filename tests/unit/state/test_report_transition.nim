# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real signed block publication and complete parent rollback after report, budget and
## final-hash refusals.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "report_transition_arc_release"}

import std/[assertions, envvars, syncio]
import ../../../src/state/report/[transition as report_transition, admission as report_admission,
    assignments as report_assignments]
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/report/[policy as report_policy, anchors as report_anchors,
    packages as report_packages]
import ../../../src/state/[guarantee_credentials, store]
import ../../../src/codec/[bounded, block_codec, header]
import ../../../src/codec/state/[layout as state_layout, trie as state_trie,
    safrole as state_safrole, availability as state_availability]
import ../../../src/codec/[guarantees, report_owned, owned]
import ../../../src/codec/state/disputes as state_disputes
import ../../support/[report_context, report_admission_context, arc_evidence]

## Reset observed primitive calls/refusal without substituting successful hashes or signatures.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Fail one exact hash after a measured accepted prefix, including the final publication's last digest.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Separate fixture construction hashes from actual transition/publication work.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}

## Compare every authored original entry and complete commitment after a refused canonical update.
proc unchanged(context: Context, actual: StateStoreSnapshot) =
  let root = context.original.snapshot.value.commitment.root
  assert array[32, byte](actual.commitment.root) == array[32, byte](root)
  for entry in context.source:
    assert actual.lookup(entry.key).value.bytes ==
        entry.value # Includes services and opaque C(250), not just C(10).

## Canonical C(10) answer is assembled from the block's original complete guarantees and its fixed authored slot.
proc expected(context: Context): seq[byte] =
  let values = readGuarantees(extrinsicGuarantees(blockExtrinsic(
      context.candidate).value).value).value
  var rows = newSeq[AvailabilityAssignment](2)
  let slot = uint32(headerInfo(context.staged.value.admitted.admittedHeader).value.unsigned.slot)
  # Authored incoming guarantees occupy core zero then one, preserving signatures and evaluation slots verbatim.
  for i in 0..<values.count:
    rows[i] = presentAssignment(guaranteeAt(values.owner, i).value, AssignmentSlot(slot))
  availabilityStateEntry(rows, config().packages.availability).value.value

## Success publishes all previous stages and exact report assignments while preserving every unrelated byte.
proc success(base: OwnedReport) =
  var signedOptions0 = signedBlockFixtureConfig()
  signedOptions0.withDispute = true
  let context = authored(base, signedOptions0)
  let parent = context.original.snapshot.value
  let staged = context.staged.value.snapshot
  assert parent.lookup(chapterKey(StateChapter(5))).value.bytes != staged.lookup(chapterKey(
      StateChapter(5))).value.bytes
  assert parent.lookup(chapterKey(StateChapter(6))).value.bytes != staged.lookup(chapterKey(
      StateChapter(6))).value.bytes
  assert parent.lookup(chapterKey(StateChapter(11))).value.bytes != staged.lookup(chapterKey(
      StateChapter(11))).value.bytes
  var state = context.original
  failHash(0)
  let outcome = advanceBlockReports(state, context.candidate, context.parent, context.older,
      transitionConfig())
  assert outcome.error == BlockReportError.None, $outcome.error
  let update = outcome.value
  let final = state.snapshot.value
  assert array[32, byte](final.commitment.root) == array[32, byte](update.snapshot.commitment.root)
  assert final.lookup(chapterKey(StateChapter(10))).value.bytes == expected(context)
  assert final.lookup(chapterKey(StateChapter(5))).value.bytes == staged.lookup(chapterKey(
      StateChapter(5))).value.bytes
  # Report publication may change C(10) only, after the previous stages already succeeded privately.
  for entry in context.source:
    if array[31, byte](entry.key) != array[31, byte](chapterKey(StateChapter(10))):
      assert final.lookup(entry.key).value.bytes == staged.lookup(entry.key).value.bytes
  unchanged(context, parent) # Retained parent roots/bytes never mutate when another handle advances.
  assert update.reports.reportCredentials.value.verifiedGuaranteeCount.value == 2
  assert update.reports.reportBlockStage.value.value.snapshot.lookup(chapterKey(StateChapter(
      10))).value.bytes != final.lookup(chapterKey(StateChapter(10))).value.bytes
  let measured = hashes()
  assert measured > 0
  # A later independent modification cannot make this block apply to a second state or overwrite its new head.
  let repeated = advanceBlockReports(state, context.candidate, context.parent, context.older,
      transitionConfig())
  assert repeated.error == BlockReportError.StageFailure
  assert repeated.stageError.error == BlockTransitionError.AdmissionFailure
  assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
      final.commitment.root)

## Each actual later report refusal must discard C(5), authenticated Safrole state and any timeout-cleared C(10).
proc reportRefusals(base: OwnedReport) =
  for mode in [1, 3, 4, 6, 7, 8, 9, 10, 12, 13]:
    var signedOptions1 = signedBlockFixtureConfig()
    signedOptions1.mode = mode
    signedOptions1.withDispute = true
    let context = authored(base, signedOptions1)
    assert context.original.snapshot.value.lookup(chapterKey(StateChapter(5))).value.bytes !=
        context.staged.value.snapshot.lookup(chapterKey(StateChapter(5))).value.bytes
    var state = context.original
    let refused = advanceBlockReports(state, context.candidate, context.parent, context.older,
        transitionConfig())
    assert refused.error == BlockReportError.ReportFailure, $mode & " " & $refused.error
    let cause = refused.reportError
    case mode
    of 1:
      assert cause.error == ReportAdmissionError.PolicyFailure and cause.policyError ==
          ReportPolicyError.Unauthorized # A preceding report already passed policy.
    of 3, 4:
      assert cause.error == ReportAdmissionError.AnchorFailure # Earlier credentials and policy succeeded.
    of 6, 12:
      assert cause.error == ReportAdmissionError.PackageFailure and cause.packageError ==
          ReportPackageError.DuplicatePackage # Parent exclusions survive timeout clearing.
    of 7:
      assert cause.error == ReportAdmissionError.AssignmentFailure and cause.assignmentError ==
          ReportAssignmentError.OccupiedCore # A surviving core is never overwritten.
    of 8:
      assert cause.error == ReportAdmissionError.CredentialFailure and
          cause.credentialError.error ==
          GuaranteeCredentialError.InvalidSignature # Later invalid signature must refuse everything.
    of 9:
      assert cause.error == ReportAdmissionError.MissingState # No empty history substitute.
    of 13:
      assert cause.error == ReportAdmissionError.PackageFailure and cause.packageError ==
          ReportPackageError.MissingState # Missing parent pipeline chapter.
    else:
      assert cause.error == ReportAdmissionError.InvalidState # Exact history suffix refusal.
    unchanged(context, state.snapshot.value)
  let context = authored(base)
  var state = context.original
  let missing = advanceBlockReports(state, context.candidate, context.parent, [], transitionConfig())
  assert missing.error == BlockReportError.ReportFailure and missing.reportError.anchorError ==
      ReportAnchorError.MissingLookupAnchor
  unchanged(context, state.snapshot.value)
  var profile = transitionConfig()
  profile.reports.packages.queues.epochSlots = EpochSlots(24)
  let mismatch = advanceBlockReports(state, context.candidate, context.parent, context.older, profile)
  assert mismatch.error == BlockReportError.ReportFailure and mismatch.reportError.error ==
      ReportAdmissionError.InvalidConfig
  unchanged(context, state.snapshot.value)

## Publication budgets and final Merklization must refuse without leaking any successfully checked stage.
proc publicationRefusals(base: OwnedReport) =
  var signedOptions3 = signedBlockFixtureConfig()
  signedOptions3.withDispute = true
  let context = authored(base, signedOptions3)
  var successful = context.original
  failHash(0)
  let accepted = advanceBlockReports(successful, context.candidate, context.parent, context.older,
      transitionConfig())
  assert accepted.error == BlockReportError.None
  let count = hashes()
  # First-hash refusal proves early failure; last-hash refusal occurs after all report checks at final publication.
  for prefix in [0.cint, count-1]:
    var refused = context.original
    hashAfter(prefix)
    let failed = advanceBlockReports(refused, context.candidate, context.parent, context.older,
        transitionConfig())
    if prefix == 0:
      assert failed.error == BlockReportError.StageFailure # Admission cannot hash the actual parent identity.
    else:
      assert failed.error == BlockReportError.PublicationFailure and failed.publicationError ==
          StateStoreError.BackendFailure # No fake success root on a final digest refusal.
    unchanged(context, refused.snapshot.value)
    failHash(0)
  var signedOptions4 = signedBlockFixtureConfig()
  signedOptions4.maxWriteBytes = 132
  signedOptions4.withDispute = true
  let bounded = authored(base, signedOptions4)
  assert expected(bounded).len > 132 # Earlier stage writes fit, but complete new assignments do not.
  var refused = bounded.original
  let resource = advanceBlockReports(refused, bounded.candidate, bounded.parent, bounded.older,
      transitionConfig())
  assert resource.error == BlockReportError.PublicationFailure and resource.publicationError ==
      StateStoreError.LimitExceeded
  unchanged(bounded, refused.snapshot.value)
  var signedOptions5 = signedBlockFixtureConfig()
  signedOptions5.mode = 11
  let timed = authored(base, signedOptions5)
  var timedState = timed.original
  let timeout = advanceBlockReports(timedState, timed.candidate, timed.parent, timed.older,
      transitionConfig())
  assert timeout.error == BlockReportError.None
  assert timedState.snapshot.value.lookup(chapterKey(StateChapter(10))).value.bytes == expected(
      timed) # Cleared original assignments make room for complete new guarantees.

## Empty-report publication preserves the exact earlier-stage root and requires no redundant map hashing.
proc emptyBatch(base: OwnedReport) =
  var signedOptions6 = signedBlockFixtureConfig()
  signedOptions6.reports = 0
  signedOptions6.maxWriteBytes = 132
  signedOptions6.withDispute = true
  let context = authored(base, signedOptions6)
  var staged = context.original
  failHash(0)
  let prefix = stage(staged, context.candidate, context.parent)
  assert prefix.error == BlockTransitionError.None
  assert planBlockReports(prefix, context.older, config()).error == ReportAdmissionError.None
  let required = hashes()
  var state = context.original
  failHash(0)
  let result = advanceBlockReports(state, context.candidate, context.parent, context.older,
      transitionConfig())
  assert result.error == BlockReportError.None
  assert hashes() == required # An unchanged C(10) has an empty write batch, not a redundant root computation.
  assert array[32, byte](result.value.snapshot.commitment.root) == array[32, byte](
      prefix.value.snapshot.commitment.root)

## Every scoped success or late refusal must retire complete report/stage owners and private working maps.
proc cycle(context: Context, expected: BlockReportError) =
  var state = context.original
  let result = advanceBlockReports(state, context.candidate, context.parent, context.older,
      transitionConfig())
  assert result.error == expected

## A retained success must outlive its fixture's stores, block/header handles and mutable source descriptors.
proc escaped(base: OwnedReport): BlockReportUpdate =
  var signedOptions7 = signedBlockFixtureConfig()
  signedOptions7.withDispute = true
  let context = authored(base, signedOptions7)
  var state = context.original
  advanceBlockReports(state, context.candidate, context.parent, context.older, transitionConfig()).value

## Run all deterministic ownership/atomicity cases with genuinely verified crypto and explicit fixture transport.
proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i]) # The existing template digest is checked by the fixture manifest.
  let base = decodeOwnedReport(bytes, 341).value
  success(base)
  reportRefusals(base)
  publicationRefusals(base)
  emptyBatch(base)
  let retained = escaped(base)
  assert retained.reports.reportCredentials.value.verifiedGuaranteeCount.value == 2
  assert retained.snapshot.lookup(chapterKey(StateChapter(10))).error == StateStoreError.None
  var signedOptions8 = signedBlockFixtureConfig()
  signedOptions8.withDispute = true
  let good = authored(base, signedOptions8)
  var signedOptions9 = signedBlockFixtureConfig()
  signedOptions9.mode = 1
  signedOptions9.withDispute = true
  let bad = authored(base, signedOptions9)
  cycle(good, BlockReportError.None)
  cycle(bad, BlockReportError.ReportFailure)
  let before = getOccupiedMem()
  for i in 0..<1000:
    if i mod 2 == 0: cycle(good, BlockReportError.None) # Complete final-map/certificate retirement.
    else: cycle(bad, BlockReportError.ReportFailure) # Earlier C(5)/Safrole writes and verified credentials remain private.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("report_transition", 1000, before, after)
  echo "PASS report transition: atomic assignments, whole-block rollback, exact publication and retained owners"
try:
  main() # Every state/crypto/rollback assertion runs natively.
except:
  quit(2) # Missing transport or unexpected exceptions cannot be reported as success.
