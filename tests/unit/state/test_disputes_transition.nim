# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute every pinned tiny/full disputes STF case natively; Python only transports source
## bytes/answers.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/[disputes, store]
import ../../../src/codec/[disputes, state_disputes, state_availability, state_safrole,
  state_layout, state_trie, bounded, assurances, guarantees, header, report_owned]
import ../../../src/crypto/primitives
import ../../support/arc_evidence

## Refuse native hashing independently of signature/codec validation.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Count observed hash calls so unchanged/no-op publication requires no hidden rehash.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}

## Decode exact test-only hexadecimal tokens without accepting malformed fixture octets.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    assert parseHex(text[i*2..i*2+1], result[i]) == 2 # Fixed complete octets.

## Finite policy permits both profile populations, independent parent/posterior sets and full assignments.
proc policy(cores, epoch: uint64): DisputesConfig =
  DisputesConfig(rosters: ValidatorStateConfig(cores: CoreCount(cores),
    validators: ElementLimit(cores*3), maxBytes: ByteLimit(1000000)),
    state: DisputeStateConfig(perSet: ElementLimit(10000), totalItems: ElementLimit(40000),
        maxBytes: ByteLimit(2000000)),
    availability: AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(cores),
      validators: ValidatorCount(cores*3), maxBytes: ByteLimit(2000000)),
      maxPresent: ElementLimit(cores), maxBytes: ByteLimit(8000000)),
    epochSlots: EpochSlots(epoch), maxExtrinsicBytes: ByteLimit(2000000))

## Every failure must preserve the complete original map, its root and every unrelated field.
proc unchanged(state: StateStore, source: seq[StateEntry], root: StateRoot) =
  let snapshot = state.snapshot.value
  assert array[32, byte](snapshot.commitment.root) == array[32, byte](root)
  for entry in source:
    assert snapshot.lookup(entry.key).value.bytes == entry.value # Complete map, not just C(5).

## Map vector-specific semantic errors to the native contextual reason without inventing alternate acceptance.
proc reason(expected: string): DisputesError =
  case expected
  of "invalid_assignment_fixture": DisputesError.InvalidState # Explicit published dummy-state incompatibility.
  of "bad_signature": DisputesError.InvalidSignature # Cryptographic verdict is mandatory.
  of "already_judged": DisputesError.AlreadyJudged # Any prior report class excludes another verdict.
  of "offender_already_reported", "bad_guarantor_key",
      "bad_auditor_key": DisputesError.InvalidKey # Exact parent membership.
  of "bad_judgement_age": DisputesError.InvalidEpoch # Parent epoch, not candidate epoch.
  of "bad_votes_count": DisputesError.InvalidQuorum # Selected roster's quorum.
  of "bad_vote_split": DisputesError.InvalidSplit # No arbitrary mixed verdict.
  of "not_enough_faults": DisputesError.MissingFault # New good verdict has a contradictory witness.
  else: DisputesError.InvalidEvidence # Wrong posterior report class or contradictory vote.

## Encode an authored header solely to check literal marker order; its seal is never treated as authenticated.
proc markerHeader(keys: seq[HeaderEdKey], config: DisputesConfig): OwnedHeader =
  let policy = HeaderConfig(cores: config.rosters.cores,
    authorValidators: ValidatorCount(uint64(config.rosters.validators)),
        epochSlots: config.epochSlots,
    maxBytes: ByteLimit(10000))
  var bytes = newSeq[byte](10000)
  let written = encodeHeader(Header(unsigned: UnsignedHeader(offenders: keys)), policy, bytes)
  assert written.error == HeaderError.None
  bytes.setLen(written.value)
  decodeHeader(bytes, policy).value.owner

## Retire every successful/refused temporary plan before taking the next live-memory observation.
proc releaseCycle(parent: StateStoreSnapshot, input: OwnedDisputes, config: DisputesConfig,
    refused: bool) =
  failHash(cint(if refused: 1 else: 0))
  let result = planDisputes(parent, input, config)
  assert result.error == (if refused: DisputesError.BackendFailure else: DisputesError.None)

## Construct valid state assignments and real signatures for bad/wonky clearing, good retention and repeated markers.
proc authored(rawReports: string) =
  let config = policy(2, 12)
  let wires = rawReports.split(',')
  var rosters = newSeq[StateValidator](6)
  var seeds = newSeq[EdSeed](6)
  for i in 0..<6:
    var raw = default(array[32, byte])
    raw[0] = byte(i+1) # Reproducible authored secret seeds, never production entropy.
    seeds[i] = importSeed(raw).value
    rosters[i].ed25519 = StateEdKey(array[32, byte](publicKey(seeds[i]).value))
  var slots = newSeq[AvailabilityAssignment](2)
  for i in 0..<2:
    let report = decodeOwnedReport(unhex(wires[i]), 2).value
    let guarantee = Guarantee(report: report, slot: GuaranteeSlot(0), credentialCount: 2,
      credentials: [GuaranteeCredential(validator: GuarantorIndex(0)),
      GuaranteeCredential(validator: GuarantorIndex(1)), default(GuaranteeCredential)])
    slots[i] = presentAssignment(guarantee, AssignmentSlot(uint32(
        40+i))) # Opaque parent credentials are not reverified here.
  let target = DisputeHash(array[32, byte](blake2b256(unhex(wires[0])).value))
  for kind in [JudgmentSet.Bad, JudgmentSet.Wonky, JudgmentSet.Good]:
    var verdict = Verdict(target: target, epoch: DisputeEpoch(0), judgments: @[])
    for i in 0..<5:
      let valid = kind == JudgmentSet.Good or (kind == JudgmentSet.Wonky and i < 2)
      let domain = if valid: "jam_valid" else: "jam_invalid" # Exact vote-dependent domain.
      var message: seq[byte] = @[]
      for ch in domain: message.add(byte(ch)) # No dollar or terminator.
      for b in array[32, byte](target): message.add(b)
      verdict.judgments.add(Judgment(valid: valid, judge: JudgeIndex(uint16(i)),
        signature: DisputeSignature(array[64, byte](sign(seeds[i], message).value))))
    var input = Disputes(verdicts: @[verdict], culprits: @[], faults: @[])
    let key = OffenderKey(array[32, byte](rosters[0].ed25519))
    if kind != JudgmentSet.Wonky:
      var message: seq[byte] = @[]
      let domain = if kind == JudgmentSet.Bad: "jam_valid" else: "jam_invalid"
      for ch in domain: message.add(byte(ch)) # A fault always contradicts the verdict.
      for b in array[32, byte](target): message.add(b)
      input.faults.add(Fault(target: target, valid: kind == JudgmentSet.Bad, key: key,
        signature: DisputeSignature(array[64, byte](sign(seeds[0], message).value))))
      if kind == JudgmentSet.Bad:
        message = @[]
        for ch in "jam_guarantee": message.add(byte(ch)) # Same key may appear in both independent sections.
        for b in array[32, byte](target): message.add(b)
        input.culprits.add(Culprit(target: target, key: key,
          signature: DisputeSignature(array[64, byte](sign(seeds[0], message).value))))
    var bytes = newSeq[byte](10000)
    let written = encodeDisputes(input, DisputeConfig(validators: ValidatorCount(6),
        maxBytes: ByteLimit(10000)), bytes)
    assert written.error == DisputeError.None
    bytes.setLen(written.value)
    let captured = decodeDisputes(bytes, DisputeConfig(validators: ValidatorCount(6),
        maxBytes: ByteLimit(10000))).value.owner
    let originalAssignment = availabilityStateEntry(slots, config.availability).value
    let entries = @[disputeStateEntry(DisputeState(), config.state).value, originalAssignment,
      validatorEntry(ValidatorChapter.Active, rosters, config.rosters).value,
      validatorEntry(ValidatorChapter.Previous, rosters, config.rosters).value, timeEntry(StateTime(0))]
    let limits = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(20),
        perValue: ByteLimit(10000000),
      totalValueBytes: ByteLimit(30000000), nodes: TrieNodeLimit(1000)), writes: ElementLimit(2),
          writeValueBytes: ByteLimit(20000000))
    var state = newStateStore(entries, limits).value
    let parent = state.snapshot.value
    let planned = planDisputes(parent, captured, config)
    assert planned.error == DisputesError.None
    let plan = planned.value
    assert availabilityAt(plan.disputeAssignments, AssignmentCoreIndex(0)).value.present == (kind ==
        JudgmentSet.Good)
    assert availabilityAt(plan.disputeAssignments, AssignmentCoreIndex(1)).value.registered ==
        slots[1].registered # Unrelated assignment intact.
    assert disputeStateInfo(plan.disputeJudgments).value.reports[kind] == 1
    if kind == JudgmentSet.Bad:
      assert plan.newOffenderCount == 2 and disputeStateInfo(
          plan.disputeJudgments).value.offenders == 1 # Marker duplicates, set union once.
      assert array[32, byte](plan.newOffenderAt(0).value) == array[32, byte](plan.newOffenderAt(1).value)
    if kind == JudgmentSet.Bad:
      for warm in 0..<10: releaseCycle(parent, captured, config, false) # Exclude one-time runtime caches.
      let before = getOccupiedMem()
      for cycle in 0..<1000: releaseCycle(parent, captured, config, cycle mod 2 ==
          1) # Success and late hash refusal release all private owners.
      let after = getOccupiedMem()
      assert before == after
      recordArcRelease("disputes_transition", 1000, before, after)
    failHash(1)
    let rejected = planDisputes(parent, captured, config)
    if kind != JudgmentSet.Good:
      assert rejected.error == DisputesError.BackendFailure # Actual report hash refusal cannot silently retain an assignment.
    failHash(0)
    var tight = config
    tight.state.perSet = ElementLimit(0)
    assert planDisputes(parent, captured, tight).error ==
        DisputesError.LimitExceeded # Growth is charged before insertion.
    assert publishDisputes(state, plan).error == DisputesError.None
    unchanged(newStateStore(entries, limits).value, entries, parent.commitment.root)
  for seed in seeds: clearSeed(seed) # Authored secrets retire explicitly after all signatures.

## Native verification and exact posterior codec comparisons own every expected output assertion.
proc main() {.raises.} =
  let path = getEnv("RAGNAROK_DISPUTES_TRANSITION")
  assert path.len > 0
  var count, accepted = 0
  for line in readFile(path).splitLines:
    if line.len == 0: continue # Final file newline is not a test case.
    let parts = line.splitWhitespace
    assert parts.len == 14
    if count == 0: authored(parts[13]) # Valid authored assignments complement the published dummy fixtures.
    let config = policy(uint64(parseInt(parts[1])), uint64(parseInt(parts[2])))
    var source = @[StateEntry(key: chapterKey(StateChapter(5)), value: unhex(parts[5])),
      StateEntry(key: chapterKey(StateChapter(10)), value: unhex(parts[6])),
      StateEntry(key: chapterKey(StateChapter(8)), value: unhex(parts[7])),
      StateEntry(key: chapterKey(StateChapter(9)), value: unhex(parts[8])),
      timeEntry(StateTime(uint32(parseInt(parts[9])))),
      StateEntry(key: chapterKey(StateChapter(250)), value: @[9'u8, 7, 3])]
    let limits = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(20),
        perValue: ByteLimit(10000000),
      totalValueBytes: ByteLimit(30000000), nodes: TrieNodeLimit(10000)),
      writes: ElementLimit(10), writeValueBytes: ByteLimit(20000000))
    failHash(0)
    let created = newStateStore(source, limits)
    assert created.error == StateStoreError.None
    var state = created.value
    let parent = state.snapshot.value
    let input = decodeDisputes(unhex(parts[4]), DisputeConfig(validators: ValidatorCount(uint64(
        config.rosters.validators)), maxBytes: config.maxExtrinsicBytes))
    if input.error != DisputeError.None:
      assert parts[3] in ["judgements_not_sorted_unique", "culprits_not_sorted_unique",
          "faults_not_sorted_unique", "verdicts_not_sorted_unique"] # Canonical decoding owns these failures.
    else:
      let planned = planDisputes(parent, input.value.owner, config)
      if parts[3] != "ok":
        if planned.error != reason(parts[3]):
          echo parts[0], " expected ", reason(parts[3]), " got ", planned.error # Failure-only diagnostics.
        assert planned.error == reason(parts[3])
      else:
        if planned.error != DisputesError.None: echo parts[0], " got ",
            planned.error # Identify exact unchanged upstream case.
        assert planned.error == DisputesError.None
        let plan = planned.value
        let marker = if parts[12] == "-": newSeq[byte](0) else: unhex(parts[12]) # Empty output remains empty.
        assert plan.newOffenderCount*32 == marker.len
        for i in 0..<plan.newOffenderCount:
          assert @(array[32, byte](plan.newOffenderAt(i).value)) == marker[
              i*32..i*32+31] # Exact sequence, not sorted union.
        var keys = newSeq[HeaderEdKey](plan.newOffenderCount)
        for i in 0..<keys.len:
          keys[i] = HeaderEdKey(array[32, byte](plan.newOffenderAt(i).value)) # Exact published marker bytes.
        assert checkDisputeMarker(plan, markerHeader(keys, config)) == DisputesError.None
        keys.add(default(HeaderEdKey)) # Extra marker entries are never silently ignored.
        assert checkDisputeMarker(plan, markerHeader(keys, config)) == DisputesError.InvalidMarker
        keys.setLen(keys.len-1)
        if keys.len > 1 and array[32, byte](keys[0]) != array[32, byte](keys[keys.len-1]):
          let first = keys[0]
          let last = keys[keys.len-1]
          keys[0] = last
          keys[keys.len-1] = first # Same set, wrong literal sequence.
          assert checkDisputeMarker(plan, markerHeader(keys, config)) == DisputesError.InvalidMarker
        assert plan.newOffenderAt(-1).error == DisputesError.InvalidIndex
        assert plan.newOffenderAt(plan.newOffenderCount).error == DisputesError.InvalidIndex
        unchanged(state, source, parent.commitment.root)
        let published = publishDisputes(state, plan)
        assert published.error == DisputesError.None
        assert published.value.lookup(chapterKey(StateChapter(5))).value.bytes == unhex(parts[10])
        assert published.value.lookup(chapterKey(StateChapter(10))).value.bytes == unhex(parts[11])
        for entry in source:
          if array[31, byte](entry.key) != array[31, byte](chapterKey(StateChapter(5))) and array[
              31, byte](entry.key) != array[31, byte](chapterKey(StateChapter(10))):
            assert published.value.lookup(entry.key).value.bytes ==
                entry.value # Every other chapter is unchanged.
        assert parent.lookup(chapterKey(StateChapter(5))).value.bytes == source[
            0].value # Escaped parent stays immutable.
        var different = created.value
        assert different.apply(@[StateWrite(key: chapterKey(StateChapter(250)),
            kind: StateWriteKind.Put, value: @[0'u8])]).error == StateStoreError.None
        assert publishDisputes(different, plan).error == DisputesError.ParentMismatch
        var refused = created.value
        failHash(1)
        let result = publishDisputes(refused, plan)
        if source[0].value != unhex(parts[10]) or source[1].value != unhex(parts[11]):
          assert result.error == DisputesError.BackendFailure # Any real changed map needs native hashing.
          unchanged(refused, source, parent.commitment.root)
        else:
          assert result.error == DisputesError.None and hashes() == 0 # No-op publication needs no primitive call.
        failHash(0)
        inc accepted
      unchanged(created.value, source, parent.commitment.root)
    inc count
  assert count == 60 and accepted == 19
  assert planDisputes(default(StateStoreSnapshot), default(OwnedDisputes), policy(2, 12)).error ==
      DisputesError.InvalidInput
  var empty = default(StateStore)
  assert publishDisputes(empty, default(DisputesPlan)).error == DisputesError.Uninitialized
  echo "Disputes transition: 60 pinned tiny/full cases passed"

try:
  main() # Fixture I/O or parsing failures fail the suite rather than skipping coverage.
except:
  quit(2) # No unread or malformed published evidence can pass.
