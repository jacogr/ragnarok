## Unchanged report STF projections and authored credential, population, reporter-set and ownership boundaries.
import std/[assertions, envvars, strutils, parseutils, syncio]
import ../../../src/state/[guarantee_credentials, guarantors]
import ../../../src/codec/[guarantees, assurances, bounded, state_safrole, header, disputes,
  report_owned, owned, work_report, composite]
import ../../../src/crypto/[primitives, guarantee]
import ../../support/arc_evidence

## Refuse immediate/transcript hashes or a later batch member, preserving successful production verification.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Allow a finite successful prefix before provider refusal to exercise rollback after complete credentials.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Observe only test-linked hash attempts to demonstrate malformed preflight precedes hashing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Decode exact trusted fixture octets; a dash represents an absent list, not a synthesized protocol field.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # No bytes for an empty transport token.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    assert parseHex(text[i*2..i*2+1], result[i]) == 2 # Whole octets only.

## The profile's maximum population is independent from actual current/previous roster lengths.
proc policy(cores: uint64): GuaranteeCredentialConfig =
  GuaranteeCredentialConfig(assignments: GuarantorConfig(roster: ValidatorStateConfig(
    cores: CoreCount(cores), validators: ElementLimit(cores*3), maxBytes: ByteLimit(400000)),
    epochSlots: EpochSlots(if cores == 341: 600 else: 12),
    rotationSlots: GuarantorRotationSlots(if cores == 341: 10 else: 4), offenders: ElementLimit(
        cores*3)),
    maxBytes: ByteLimit(10000000), reporters: ElementLimit(cores*3))

## Derive the same structural ceiling used by credential preflight, with no contextual admission claim.
proc wirePolicy(config: GuaranteeCredentialConfig): GuaranteeConfig =
  GuaranteeConfig(cores: config.assignments.roster.cores,
    validators: ValidatorCount(uint64(config.assignments.roster.validators)),
        maxBytes: config.maxBytes)

## Copy canonical report bytes into caller-owned scratch, keeping every extraction bound to its original owner.
proc reportBytes(owner: OwnedReport): seq[byte] =
  result = newSeq[byte](ownedReportInfo(owner).value.consumed)
  assert encodeOwnedReport(owner, result).error == OwnershipError.None

## Recover all copied records only after complete canonical extrinsic decoding.
proc records(owner: GuaranteesRead): seq[Guarantee] =
  result = newSeq[Guarantee](owner.count)
  for i in 0..<result.len:
    result[i] = guaranteeAt(owner.owner, i).value # Each copy retains its exact report owner.

## Match the relevant published refusal; codec failures precede contextual verification for malformed wire values.
proc expectRefusal(expected: string, decoded: GuaranteeResult[GuaranteesRead],
    checked: GuaranteeCredentialResult[VerifiedGuaranteeCredentials]) =
  if decoded.error != GuaranteeError.None:
    case expected
    of "bad_core_index", "bad_erasure_shards":
      assert decoded.error == GuaranteeError.LimitExceeded # Invalid core/shard domains cannot form an owned report.
    of "bad_validator_index":
      assert decoded.error == GuaranteeError.InvalidValidator # The declared maximum population is exceeded.
    of "insufficient_guarantees":
      assert decoded.error == GuaranteeError.InvalidCredential # Exactly two or three credentials are required.
    of "not_sorted_or_unique_guarantors", "out_of_order_guarantee":
      assert decoded.error == GuaranteeError.NonCanonical # Preserve ordering/uniqueness without normalization.
    else:
      assert false, expected # No unrelated codec failure can substitute for the intended test.
    return
  case expected
  of "bad_signature", "banned_validator":
    assert checked.error == GuaranteeCredentialError.InvalidSignature # Phi-null keys cannot verify original credentials.
  of "wrong_assignment":
    assert checked.error == GuaranteeCredentialError.WrongAssignment # A valid signature does not establish core membership.
  of "future_report_slot", "report_epoch_before_last":
    assert checked.error == GuaranteeCredentialError.AssignmentFailure
    assert checked.assignmentError == GuarantorError.InvalidSlot # No modulo/wrapping fallback.
  of "bad_erasure_shards":
    assert checked.error == GuaranteeCredentialError.WrongErasureShards # Structurally valid counts still require equality.
  else:
    assert false, expected # Every selected vector has an explicit, narrow expected verdict.

## Exercise thirty unchanged tiny/full projections and compare the exact externally supplied reporter keys.
proc official(): OwnedReport {.raises.} =
  result = default(OwnedReport) # No successful fixture means the final count assertion must fail.
  var pools: seq[seq[byte]] = @[]
  var total = 0
  var accepted = 0
  for row in readFile(getEnv("RAGNAROK_GUARANTEE_CREDENTIALS")).splitLines:
    if row.len == 0: continue # Ignore only the fixture's trailing newline.
    let f = row.splitWhitespace
    if f[0] == "pool":
      pools.add(unhex(f[1])) # Repeated immutable roster bytes share transport storage only.
      continue
    inc total
    let config = policy(uint64(parseInt(f[2])))
    let active = decodeStateValidators(pools[parseInt(f[5])], config.assignments.roster).value.value
    let previous = decodeStateValidators(pools[parseInt(f[6])],
        config.assignments.roster).value.value
    let entropy = decodeStateEntropy(unhex(f[7])).value.value
    let rawOffenders = unhex(f[8])
    var offenders = newSeq[OffenderKey](rawOffenders.len div 32)
    for i in 0..<offenders.len:
      var key = default(array[32, byte])
      for j in 0..<32:
        key[j] = rawOffenders[i*32+j] # Preserve source order; the planner rejects noncanonical offenders.
      offenders[i] = OffenderKey(key)
    let decoded = decodeGuarantees(unhex(f[9]), wirePolicy(config))
    var checked = default(GuaranteeCredentialResult[VerifiedGuaranteeCredentials])
    if decoded.error == GuaranteeError.None:
      checked = verifyGuaranteeCredentials(records(decoded.value), active, previous, entropy,
        StateTime(parseInt(f[4])), offenders, config) # The same original named context for every case.
    if f[3] == "ok":
      assert decoded.error == GuaranteeError.None, f[1]
      assert checked.error == GuaranteeCredentialError.None, f[1] & " " & $checked.error
      inc accepted
      result = checked.value.verifiedGuaranteeAt(0).value.report # Retained child survives all local context owners.
      let expected = f[10].split(',')
      assert checked.value.verifiedReporterCount.value == expected.len
      for i in 0..<expected.len:
        let key = checked.value.verifiedReporterAt(i).value
        assert @(array[32, byte](key)) == unhex(expected[i]) # Exact supplied sorted mathematical key set.
    else:
      expectRefusal(f[3], decoded, checked) # No invalid source is repaired or resubmitted.
  assert total == 30 and accepted == 8

## Generate deterministic test seeds; their owned buffers stay alive only for the test's signing scope.
proc seeds(count, offset: int): seq[EdSeed] =
  result = newSeq[EdSeed](count)
  for i in 0..<count:
    var bytes = default(array[32, byte])
    bytes[0] = byte(i+offset)
    result[i] = importSeed(bytes).value # Public test seeds, never production keys.

## Capture complete copied key records without requiring generated BLS/Bandersnatch material in this Ed25519 slice.
proc roster(keys: seq[EdSeed], config: GuaranteeCredentialConfig): ValidatorStateSnapshot =
  var values = newSeq[StateValidator](keys.len)
  for i in 0..<keys.len:
    values[i].ed25519 = StateEdKey(array[32, byte](publicKey(keys[i]).value)) # Selected credential identities.
  let wire = validatorEntry(ValidatorChapter.Active, values, config.assignments.roster).value.value
  decodeStateValidators(wire, config.assignments.roster).value.value

## Change only nominal fixed/core fields, using the existing encoder with the original borrowed blob pool.
proc reportFor(base: OwnedReport, core: CoreIndex, shards: ErasureShards): OwnedReport =
  let original = reportBytes(base)
  var value = decodeReportBorrowed(original, 341).value
  value.core = core
  value.header.erasureShards = shards
  var output = newSeq[byte](original.len+16)
  let encoded = encodeReportBorrowed(value, original, 3, output)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(output.toOpenArray(0, encoded.written-1), 3).value

## Select two or three matching assigned ordinals and sign the complete canonical report's exact domain transcript.
proc signed(base: OwnedReport, core: CoreIndex, shards: ErasureShards, slot: GuaranteeSlot,
    plan: GuarantorPlan, keys: seq[EdSeed], count = 2): Guarantee =
  result = Guarantee(report: reportFor(base, core, shards), slot: slot,
    credentialCount: count, credentials: default(array[3, GuaranteeCredential]))
  let message = array[45, byte](guaranteeMessage(reportBytes(result.report)).value)
  var found = 0
  for i in 0..<keys.len:
    let assigned = plan.guarantorAt(slot, GuarantorIndex(i)).value
    if uint64(assigned.core) == uint64(core) and found < count:
      result.credentials[found] = GuaranteeCredential(validator: GuarantorIndex(i),
        signature: GuaranteeSignature(array[64, byte](sign(keys[i],
            message).value))) # Preserve ascending ordinal order.
      inc found
  assert found == count # Authored tests must actually find the intended two/three assigned signers.

## Scoped success and early/late refusal release both assignment tables and all partially collected reporter keys.
proc releaseCycle(values: seq[Guarantee], active, previous: ValidatorStateSnapshot,
    entropy: StateEntropy, config: GuaranteeCredentialConfig, mode: int) =
  case mode
  of 0:
    failHash(0) # A fully verified owner must release on scope exit.
  of 1:
    failHash(1) # Refuse the first assignment shuffle hash.
  of 2:
    failAfter(3) # Current six / previous nine consume three hashes before the first report transcript.
  else:
    failAfter(4) # One report has verified before the next transcript refuses.
  let outcome = verifyGuaranteeCredentials(values, active, previous, entropy, StateTime(12), [], config)
  if mode == 0:
    assert outcome.error == GuaranteeCredentialError.None
  elif mode == 1:
    assert outcome.error == GuaranteeCredentialError.AssignmentFailure
    assert outcome.assignmentError == GuarantorError.BackendFailure
  else:
    assert outcome.error == GuaranteeCredentialError.BackendFailure
  failHash(0) # Fault injection never escapes the sequential observer-linked test scope.

## Authored resizing separates the currently active-core rule and shard equality from historical credential eligibility.
proc boundaries(base: OwnedReport) =
  let config = policy(3)
  let currentKeys = seeds(6, 11)
  let previousKeys = seeds(9, 31)
  let active = roster(currentKeys, config)
  let previous = roster(previousKeys, config)
  let entropy = default(StateEntropy)
  let plan = planGuarantors(active, previous, entropy, StateTime(12), [], config.assignments).value
  let first = signed(base, CoreIndex(0), ErasureShards(6), GuaranteeSlot(12), plan, currentKeys)
  let second = signed(base, CoreIndex(1), ErasureShards(6), GuaranteeSlot(8), plan, previousKeys)
  var values = @[first, second]
  let verified = verifyGuaranteeCredentials(values, active, previous, entropy, StateTime(12), [], config).value
  assert verified.verifiedGuaranteeCount.value == 2
  assert verified.verifiedReporterCount.value == 4 # Current and previous key identities remain distinct even if ordinals overlap.
  let inactive = signed(base, CoreIndex(2), ErasureShards(6), GuaranteeSlot(8), plan, previousKeys)
  assert verifyGuaranteeCredentials([inactive], active, previous, entropy, StateTime(12), [],
      config).error == GuaranteeCredentialError.InactiveCore
  let oldShards = signed(base, CoreIndex(1), ErasureShards(9), GuaranteeSlot(8), plan, previousKeys)
  assert verifyGuaranteeCredentials([oldShards], active, previous, entropy, StateTime(12), [],
      config).error == GuaranteeCredentialError.WrongErasureShards
  let three = signed(base, CoreIndex(0), ErasureShards(6), GuaranteeSlot(12), plan, currentKeys, 3)
  assert verifyGuaranteeCredentials([three], active, previous, entropy, StateTime(12), [],
      config).value.verifiedReporterCount.value == 3
  var wrong = signed(base, CoreIndex(1), ErasureShards(6), GuaranteeSlot(12), plan, currentKeys)
  wrong.report = first.report
  assert verifyGuaranteeCredentials([wrong], active, previous, entropy, StateTime(12), [],
      config).error == GuaranteeCredentialError.WrongAssignment
  var invalid = first
  var corrupt = array[64, byte](invalid.credentials[0].signature)
  corrupt[0] = corrupt[0] xor 1
  invalid.credentials[0].signature = GuaranteeSignature(corrupt)
  assert verifyGuaranteeCredentials([invalid], active, previous, entropy, StateTime(12), [],
      config).error == GuaranteeCredentialError.InvalidSignature
  invalid = first
  var changedReport = reportBytes(first.report)
  changedReport[0] = changedReport[0] xor 1
  invalid.report = decodeOwnedReport(changedReport, 3).value
  assert verifyGuaranteeCredentials([invalid], active, previous, entropy, StateTime(12), [],
      config).error == GuaranteeCredentialError.InvalidSignature
  invalid = first
  let signer = int(uint16(first.credentials[0].validator))
  invalid.credentials[0].signature = GuaranteeSignature(array[64, byte](sign(currentKeys[signer],
      reportBytes(first.report)).value))
  assert verifyGuaranteeCredentials([invalid], active, previous, entropy, StateTime(12), [],
      config).error == GuaranteeCredentialError.InvalidSignature
  for count in [-1, 0, 1, 4, high(int)]:
    invalid = first
    invalid.credentialCount = count # The fixed array must never be indexed by these native counts.
    failHash(0)
    let refused = verifyGuaranteeCredentials([invalid], active, previous, entropy, StateTime(12), [], config)
    assert refused.error == GuaranteeCredentialError.StructureFailure
    assert refused.structureError == GuaranteeError.InvalidCredential
    assert hashCalls() == 0 # Whole-source malformed preflight precedes assignment/transcript hashing.
  invalid = first
  invalid.credentials[1] = invalid.credentials[0]
  let duplicate = verifyGuaranteeCredentials([invalid], active, previous, entropy, StateTime(12), [], config)
  assert duplicate.error == GuaranteeCredentialError.StructureFailure
  assert duplicate.structureError == GuaranteeError.NonCanonical
  invalid = first
  invalid.credentials[1].validator = GuarantorIndex(
      6) # Inside the chain ceiling, outside selected current population.
  let absent = verifyGuaranteeCredentials([invalid], active, previous, entropy, StateTime(12), [], config)
  assert absent.error == GuaranteeCredentialError.AssignmentFailure
  assert absent.assignmentError == GuarantorError.InvalidIndex
  for slot in [GuaranteeSlot(7), GuaranteeSlot(13)]:
    invalid = first
    invalid.slot = slot # Slot is not signed, so freshness must be checked separately.
    let refused = verifyGuaranteeCredentials([invalid], active, previous, entropy, StateTime(12), [], config)
    assert refused.error == GuaranteeCredentialError.AssignmentFailure
    assert refused.assignmentError == GuarantorError.InvalidSlot
  let reversed = verifyGuaranteeCredentials([second, first], active, previous, entropy, StateTime(
      12), [], config)
  assert reversed.error == GuaranteeCredentialError.StructureFailure
  assert reversed.structureError == GuaranteeError.NonCanonical
  var tight = config
  tight.maxBytes = ByteLimit(1+measureGuarantee(first, wirePolicy(config)).value+measureGuarantee(
      second, wirePolicy(config)).value)
  assert verifyGuaranteeCredentials(values, active, previous, entropy, StateTime(12), [],
      tight).error == GuaranteeCredentialError.None
  tight.maxBytes = ByteLimit(uint64(tight.maxBytes)-1)
  assert verifyGuaranteeCredentials(values, active, previous, entropy, StateTime(12), [],
      tight).error == GuaranteeCredentialError.LimitExceeded
  tight = config
  tight.reporters = ElementLimit(3)
  assert verifyGuaranteeCredentials(values, active, previous, entropy, StateTime(12), [],
      tight).error == GuaranteeCredentialError.LimitExceeded
  var repeated = seeds(6, 71)
  let shared = repeated[0]
  for i in 1..<repeated.len:
    repeated[i] = shared # Distinct ordinals may carry the same Ed25519 bytes in supplied structural context.
  let repeatedRoster = roster(repeated, config)
  let repeatedPlan = planGuarantors(repeatedRoster, previous, entropy, StateTime(12), [],
      config.assignments).value
  let duplicateKeys = signed(base, CoreIndex(0), ErasureShards(6), GuaranteeSlot(12), repeatedPlan,
      repeated, 3)
  tight.reporters = ElementLimit(1)
  let unique = verifyGuaranteeCredentials([duplicateKeys], repeatedRoster, previous, entropy,
      StateTime(12), [], tight).value
  assert unique.verifiedReporterCount.value == 1 # Reporter set deduplicates keys, never credential ordinals.
  assert array[32, byte](unique.verifiedReporterAt(0).value) == array[32, byte](publicKey(repeated[0]).value)
  let empty = verifyGuaranteeCredentials([], active, previous, entropy, StateTime(12), [], config).value
  assert empty.verifiedGuaranteeCount.value == 0 and empty.verifiedReporterCount.value == 0
  assert verifyGuaranteeCredentials([], default(ValidatorStateSnapshot), previous, entropy,
      StateTime(12), [], config).error == GuaranteeCredentialError.AssignmentFailure
  assert default(VerifiedGuaranteeCredentials).verifiedGuaranteeCount.error ==
      GuaranteeCredentialError.Uninitialized
  assert default(VerifiedGuaranteeCredentials).verifiedReporterCount.error ==
      GuaranteeCredentialError.Uninitialized
  assert default(VerifiedGuaranteeCredentials).verifiedGuaranteeAt(0).error ==
      GuaranteeCredentialError.Uninitialized
  assert default(VerifiedGuaranteeCredentials).verifiedReporterAt(0).error ==
      GuaranteeCredentialError.Uninitialized
  assert verified.verifiedGuaranteeAt(-1).error == GuaranteeCredentialError.InvalidIndex
  assert verified.verifiedGuaranteeAt(2).error == GuaranteeCredentialError.InvalidIndex
  assert verified.verifiedReporterAt(-1).error == GuaranteeCredentialError.InvalidIndex
  assert verified.verifiedReporterAt(4).error == GuaranteeCredentialError.InvalidIndex
  values[0].report = default(OwnedReport)
  values[0].credentialCount = 1
  var extracted = verified.verifiedGuaranteeAt(0).value
  extracted.report = default(OwnedReport)
  extracted.credentials = default(array[3, GuaranteeCredential])
  let retained = verified.verifiedGuaranteeAt(0).value
  assert retained.credentialCount == 2 and reportBytes(retained.report) == reportBytes(first.report)
  assert array[64, byte](retained.credentials[0].signature) == array[64, byte](first.credentials[0].signature)
  values = @[first, second]
  releaseCycle(values, active, previous, entropy, config, 0)
  let before = getOccupiedMem()
  for i in 0..<1000:
    releaseCycle(values, active, previous, entropy, config,
        i mod 4) # Include release after a complete first report.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("guarantee_credentials", 1000, before, after)

## Fallible fixture transport cannot silently skip native conformance assertions.
proc main() {.raises.} =
  let report = official()
  boundaries(report)
  echo "PASS guarantee credentials: thirty published projections, reporter keys and contextual verification"
try:
  main() # Any assertion failure fails the native runner.
except:
  quit(2) # Missing/malformed fixture input cannot become success.
