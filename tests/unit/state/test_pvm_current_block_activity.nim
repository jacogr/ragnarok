# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_block_activity_arc_release"}

## Literal signed C(13) bytes, exact parent/body binding, independent full-map roots and atomic publication refusals.

import std/[assertions, envvars, syncio]
import ../../../src/state/[accumulation_current_activity, accumulation_activity,
  accumulation_current_validators, validator_projection, core_service_activity, preimages,
  accumulation_current_recent, accumulation_current_ready, accumulation_current_finalization,
  accumulation_current_accounts, accumulation_current_statistics, accumulation_current_driver,
  accumulation_current_sequence, accumulation_current_round, accumulation_block_guests,
  accumulation_round, accumulation_queue, report_admission, guarantee_credentials,
  block_transition, block_admission, store]
import ../../../src/codec/[bounded, composite, natural, block_codec, owned, report_owned,
  state_statistics, state_layout, state_trie, state_accounts]
import ../../support/[accumulation_current_activity_context, accumulation_provision_integration,
  report_context, arc_evidence]

# Backend faults begin only after all real signatures, guests and immutable source candidates exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Chain domains are absent: the adapter derives them from the actual validator candidate.
proc config(): AccumulationActivityConfig =
  AccumulationActivityConfig(componentBytes: ByteLimit(1024),
    preimages: PreimageLimits(items: ElementLimit(3), perBlob: ByteLimit(3),
        totalBlobBytes: ByteLimit(4)),
    incoming: ElementLimit(2), available: ElementLimit(1), digests: ElementLimit(2),
    assurances: ElementLimit(5), provisions: ElementLimit(2), accumulation: ElementLimit(2),
    services: ElementLimit(2), activityBytes: ByteLimit(4096))

# The independent expected bytes use only low-level natural and E4 framing, never the activity codec/projectors.
proc appendNatural(bytes: var seq[byte], value: uint64) =
  let encoded = natural.encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])
proc appendFixed(bytes: var seq[byte], value: uint32) =
  for shift in 0..<4: bytes.add(byte((value shr (8*shift)) and 255))

# Raw verified credential positions independently identify the fixture's unchanged six-validator reporter set.
proc admission(source: PreparedCurrentAccumulationValidators): AdmittedReports =
  source.currentValidatorsSource.value.currentRecentSource.value.currentReadySource.value.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value.completedSequenceSource.value.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value

proc expectedBytes(source: PreparedCurrentAccumulationValidators, available, blobs: bool,
    guarantees: int, rotated = false, executed = false): seq[byte] =
  ## Literal seeded validators plus fixed fixture core/service observations freeze complete wire ordering.
  result = @[]
  var reported = default(array[6, bool])
  let credentials = admission(source).reportCredentials.value
  for index in 0..<credentials.verifiedGuaranteeCount.value:
    let guarantee = credentials.verifiedGuaranteeAt(index).value
    for signer in 0..<guarantee.credentialCount:
      reported[int(uint16(guarantee.credentials[signer].validator))] = true
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    result.add(6) # Each variable validator population has its own canonical count.
    for index in 0..<6:
      for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
        var value = uint32(1000*ord(epoch)+100*index+10+ord(measure))
        if rotated: value = if epoch == StatisticsEpoch.Current: 0'u32 else: uint32(
            100*index+10+ord(measure))
        let assuranceEpoch = if rotated: StatisticsEpoch.Previous else: StatisticsEpoch.Current
        if epoch == assuranceEpoch and available and index < 5 and measure ==
            ValidatorMeasure.Assurances: inc value
        if epoch == StatisticsEpoch.Current:
          if reported[index] and measure == ValidatorMeasure.Guarantees: inc value
          if index == 0:
            case measure
            of ValidatorMeasure.Blocks: inc value
            of ValidatorMeasure.PreimageCount: value += uint32(if blobs: 3 else: 0)
            of ValidatorMeasure.PreimageBytes: value += uint32(if blobs: 4 else: 0)
            else: discard # These fixtures submit no tickets; all other counters use membership above.
        appendFixed(result, value)
  let gas = [11'u64, 13]
  let imports = [2'u64, 17]
  let xtCounts = [3'u64, 19]
  let xtBytes = [5'u64, 23]
  let exports = [7'u64, 29]
  for core in 0..<2:
    let present = core < guarantees
    let values = [uint64(if available and core == 0: 291426 else: 0),
      uint64(if available and core == 0: 5 else: 0),
      (if present: imports[core] else: 0'u64), (if present: xtCounts[core] else: 0'u64),
      (if present: xtBytes[core] else: 0'u64), (if present: exports[core] else: 0'u64),
      uint64(if present: 42 else: 0), (if present: gas[core] else: 0'u64)]
    for value in values: appendNatural(result, value) # No core sequence count exists in T.
  let first = blobs or available or guarantees > 0 or executed
  let second = blobs or executed
  appendNatural(result, uint64(ord(first)+ord(second)))
  if first:
    appendFixed(result, 42)
    let fields = [uint64(ord(blobs)), uint64(ord(blobs)), uint64(guarantees),
      (if guarantees == 2: 24'u64 elif guarantees == 1: 11'u64 else: 0'u64),
      (if guarantees == 2: 19'u64 elif guarantees == 1: 2'u64 else: 0'u64),
      (if guarantees == 2: 22'u64 elif guarantees == 1: 3'u64 else: 0'u64),
      (if guarantees == 2: 28'u64 elif guarantees == 1: 5'u64 else: 0'u64),
      (if guarantees == 2: 36'u64 elif guarantees == 1: 7'u64 else: 0'u64),
      uint64(ord(available)), 0'u64, (if executed: 22'u64 else: 0'u64)]
    for value in fields: appendNatural(result, value) # Provision/refinement/gas/metrics/S follow their exact wire positions.
  if second:
    appendFixed(result, 99)
    let fields = [uint64(if blobs: 2 else: 0), uint64(if blobs: 3 else: 0), 0'u64, 0, 0, 0, 0, 0, 0, 0,
      (if executed: 22'u64 else: 0'u64)]
    for value in fields: appendNatural(result, value)

# Reconstruct every known prior key and add only the independently expected C(13) encoding.
proc reconstructed(fixture: CurrentActivityFixture, expected: seq[byte]): StateStoreSnapshot =
  let prior = fixture.source.currentValidatorsState.value
  var entries: seq[StateEntry] = @[]
  var hasOutputs = false
  for original in fixture.entries:
    let key = original.key
    let value = prior.lookup(key)
    assert value.error == StateStoreError.None, "all original fixture keys still survive accumulation"
    if array[31, byte](key) == array[31, byte](chapterKey(StateChapter(16))): hasOutputs = true
    let bytes = if array[31, byte](key) == array[31, byte](chapterKey(StateChapter(
        13))): expected else: value.value.bytes
    entries.add(StateEntry(key: key, value: bytes))
  if not hasOutputs:
    let key = chapterKey(StateChapter(16))
    entries.add(StateEntry(key: key, value: prior.lookup(
        key).value.bytes)) # Finalization alone adds this absent chapter.
  assert entries.len == prior.commitment.entries, "independent reconstruction covers the complete prior map"
  newStateStore(entries, report_context.limits()).value.snapshot.value

proc witness(fixture: CurrentActivityFixture, available, blobs: bool, guarantees: int,
    rotated = false, executed = false): PreparedCurrentAccumulationActivity =
  ## Complete-map comparison proves the batch changes only C(13), retaining all original requests and earlier candidate effects.
  let prior = fixture.source.currentValidatorsState.value
  let original = prior.lookup(chapterKey(StateChapter(13))).value.bytes
  let expected = expectedBytes(fixture.source, available, blobs, guarantees, rotated, executed)
  let independent = reconstructed(fixture, expected)
  let prepared = prepareCurrentAccumulationActivity(fixture.source, config())
  assert prepared.error == CurrentAccumulationActivityError.None, "genuine source publishes combined activity"
  result = prepared.value
  let state = result.currentActivityState.value
  let entry = result.currentActivityEntry.value
  assert array[31, byte](entry.key) == array[31, byte](chapterKey(StateChapter(13)))
  assert entry.value == expected, "literal complete four-component C(13) bytes"
  assert state.lookup(entry.key).value.bytes == expected, "canonical encoding is exactly the private stored value"
  assert array[32, byte](state.commitment.root) == array[32, byte](independent.commitment.root), "independent complete-map root"
  assert prior.lookup(entry.key).value.bytes == original, "source C(13) stays immutable"
  assert sameStateSnapshot(prior, result.currentActivitySource.value.currentValidatorsState.value)
  assert not sameStateSnapshot(prior, state), "private candidate owns a separate map"
  for number in [3'u8, 14, 15, 16, 250]:
    let key = chapterKey(StateChapter(number))
    assert state.lookup(key).value.bytes == prior.lookup(key).value.bytes, "earlier chapters and opaque state preserved"
  let admitted = result.currentActivityPreimages.value
  assert admitted.preimageInfo.value.items == (if blobs: 3 else: 0)
  assert uint64(admitted.preimageInfo.value.bytes) == uint64(if blobs: 4 else: 0)
  assert sameStateSnapshot(admitted.preimagePrior.value, admission(
      fixture.source).reportBlockStage.value.value.admitted.admittedState),
    "preimages admitted on the exact original parent, not the timestamp map"
  let info = result.currentActivityInfo.value
  assert info.incoming == guarantees and info.available == ord(available) and info.assurances == (
      if available: 5 else: 0)
  assert info.provisions == (if blobs: 2 else: 0)
  assert info.accumulation == (if executed: 2 else: ord(available))
  let snapshot = result.currentActivitySnapshot.value
  assert snapshot.activityInfo.value.services == info.services, "retained snapshot uses the encoded complete union"
  if blobs:
    for request in [integrationRequest(42, @[73'u8]), integrationRequest(99, @[]),
        integrationRequest(99, @[81'u8, 82, 83])]:
      assert state.lookup(request.key).value.bytes == @[0'u8], "statistics do not prematurely integrate requests"

# Input work, admission, projection and codec policies retain distinct refusal alternatives and permit retry.
proc policies(fixture: CurrentActivityFixture, bytes: int) =
  let prior = fixture.source.currentValidatorsState.value
  for mode in 0..<12:
    var short = config()
    case mode
    of 0: short.componentBytes = ByteLimit(495)
    of 1: short.incoming = ElementLimit(1)
    of 2: short.available = ElementLimit(0)
    of 3: short.assurances = ElementLimit(4)
    of 4: short.accumulation = ElementLimit(0)
    of 5: short.preimages.items = ElementLimit(2)
    of 6: short.preimages.perBlob = ByteLimit(2)
    of 7: short.preimages.totalBlobBytes = ByteLimit(3)
    of 8: short.provisions = ElementLimit(1)
    of 9: short.digests = ElementLimit(1)
    of 10: short.services = ElementLimit(1)
    else: short.activityBytes = ByteLimit(uint64(bytes-1))
    let refused = prepareCurrentAccumulationActivity(fixture.source, short)
    if mode == 6 or mode == 7:
      assert refused.error == CurrentAccumulationActivityError.PreimageFailure
      assert refused.preimageError == PreimageTransitionError.LimitExceeded
    elif mode == 9 or mode == 10:
      assert refused.error == CurrentAccumulationActivityError.CoreFailure
      assert refused.coreError == CoreServiceActivityError.LimitExceeded
    elif mode == 11:
      assert refused.error == CurrentAccumulationActivityError.CodecFailure
      assert refused.codecError == ActivityError.LimitExceeded
    else:
      assert refused.error == CurrentAccumulationActivityError.LimitExceeded
    assert sameStateSnapshot(prior, fixture.source.currentValidatorsState.value), "policy refusal preserves source identity"
  var exact = config()
  exact.componentBytes = ByteLimit(496)
  exact.activityBytes = ByteLimit(uint64(bytes))
  assert prepareCurrentAccumulationActivity(fixture.source, exact).error ==
      CurrentAccumulationActivityError.None, "exact byte ceilings retry"
  var full = config()
  full.componentBytes = ByteLimit(high(uint64))
  full.preimages = PreimageLimits(items: ElementLimit(high(uint64)), perBlob: ByteLimit(high(uint64)),
    totalBlobBytes: ByteLimit(high(uint64)))
  full.incoming = ElementLimit(high(uint64))
  full.available = ElementLimit(high(uint64))
  full.digests = ElementLimit(high(uint64))
  full.assurances = ElementLimit(high(uint64))
  full.provisions = ElementLimit(high(uint64))
  full.accumulation = ElementLimit(high(uint64))
  full.services = ElementLimit(high(uint64))
  full.activityBytes = ByteLimit(high(uint64))
  assert prepareCurrentAccumulationActivity(fixture.source, full).error ==
      CurrentAccumulationActivityError.None, "full-width policies allocate actual populations only"

# The same primitive admission independently measures the successful hash prefix before the first trie hash.
proc admissionHashes(source: PreparedCurrentAccumulationValidators): cint =
  let bound = admission(source).reportBlockStage.value.value.admitted
  let body = bound.admittedBlock.blockExtrinsic.value
  failHash(0)
  assert admitPreimages(bound.admittedState, body.extrinsicPreimages.value.readPreimages.value,
    config().preimages).error == PreimageTransitionError.None
  hashCalls()

proc backendWitness(fixture: CurrentActivityFixture) =
  ## Immediate admission and late atomic-store failures expose reasons alone and leave all predecessor roots/bytes intact.
  let prior = fixture.source.currentValidatorsState.value
  let root = array[32, byte](prior.commitment.root)
  let bytes = prior.lookup(chapterKey(StateChapter(13))).value.bytes
  let prefix = admissionHashes(fixture.source)
  failHash(1)
  let early = prepareCurrentAccumulationActivity(fixture.source, config())
  assert early.error == CurrentAccumulationActivityError.PreimageFailure
  assert early.preimageError == PreimageTransitionError.BackendFailure
  for successful in [prefix, prefix+1]:
    failAfter(successful)
    let refused = prepareCurrentAccumulationActivity(fixture.source, config())
    assert refused.error == CurrentAccumulationActivityError.StateFailure, "failure after genuine preimage hashes is private trie refusal"
    assert refused.stateError == StateStoreError.BackendFailure
    assert array[32, byte](fixture.source.currentValidatorsState.value.commitment.root) == root
    assert prior.lookup(chapterKey(StateChapter(13))).value.bytes == bytes
  failHash(0)
  assert prepareCurrentAccumulationActivity(fixture.source, config()).error ==
      CurrentAccumulationActivityError.None, "backend retry remains usable"

# Success, early hash refusal and delayed write refusal release every derived owner before the next iteration.
proc cycle(source: PreparedCurrentAccumulationValidators, prefix: cint) =
  failHash(0)
  let candidate = prepareCurrentAccumulationActivity(source, config()).value
  assert candidate.currentActivityInfo.value.services == 2
  failHash(1)
  assert prepareCurrentAccumulationActivity(source, config()).preimageError ==
      PreimageTransitionError.BackendFailure
  failAfter(prefix+1)
  assert prepareCurrentAccumulationActivity(source, config()).stateError ==
      StateStoreError.BackendFailure
  failHash(0)

proc main() {.raises.} =
  ## Native launcher owns fixture bytes and ARC evidence; every source includes genuine signatures and actual completed rounds.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let empty = currentActivityFixture(base)
  discard witness(empty, false, false, 0)
  let incoming = currentActivityFixture(base, guarantees = 2)
  discard witness(incoming, false, false, 2)
  let supplied = currentActivityFixture(base, blobs = true)
  discard witness(supplied, false, true, 0)
  let ready = currentActivityFixture(base, available = true)
  discard witness(ready, true, false, 0)
  let running = currentActivityFixture(base, executed = true)
  discard witness(running, false, false, 0, executed = true)
  let combined = currentActivityFixture(base, available = true, guarantees = 2, blobs = true)
  let candidate = witness(combined, true, true, 2)
  let crossed = currentActivityFixture(base, available = true, blobs = true, slot = 12)
  discard witness(crossed, true, true, 0, rotated = true)
  policies(combined, candidate.currentActivityEntry.value.value.len)
  for mode in 0..<3:
    let bad = currentActivityFixture(base, blobs = true, requested = mode != 0,
      missingLast = mode == 1, disordered = mode == 2)
    let refused = prepareCurrentAccumulationActivity(bad.source, config())
    assert refused.error == CurrentAccumulationActivityError.PreimageFailure
    assert refused.preimageError == (if mode == 2: PreimageTransitionError.NotOrderedUnique else: PreimageTransitionError.NotRequested)
  let huge = currentActivityFixture(base, guarantees = 2, hugeRefinement = true)
  let overflow = prepareCurrentAccumulationActivity(huge.source, config())
  assert overflow.error == CurrentAccumulationActivityError.CoreFailure
  assert overflow.coreError == CoreServiceActivityError.CounterOverflow, "certified inputs may still overflow combined service metrics"
  backendWitness(combined)
  let defaultOwner = default(PreparedCurrentAccumulationActivity)
  assert defaultOwner.currentActivitySource.error == CurrentAccumulationActivityError.Uninitialized
  assert defaultOwner.currentActivityPreimages.error ==
      CurrentAccumulationActivityError.Uninitialized
  assert defaultOwner.currentActivityInfo.error == CurrentAccumulationActivityError.Uninitialized
  assert defaultOwner.currentActivitySnapshot.error ==
      CurrentAccumulationActivityError.Uninitialized
  assert defaultOwner.currentActivityEntry.error == CurrentAccumulationActivityError.Uninitialized
  assert defaultOwner.currentActivityState.error == CurrentAccumulationActivityError.Uninitialized
  let invalid = prepareCurrentAccumulationActivity(default(PreparedCurrentAccumulationValidators),
      config())
  assert invalid.error == CurrentAccumulationActivityError.InvalidSource
  var detached = default(PreparedCurrentAccumulationActivity)
  block:
    let local = currentActivityFixture(base, blobs = true)
    detached = prepareCurrentAccumulationActivity(local.source, config()).value
  var copied = detached.currentActivityEntry.value
  copied.value[0] = 0
  assert detached.currentActivityEntry.value.value[0] == 6, "entry extraction is detached after source scope"
  var info = detached.currentActivityInfo.value
  info.services = 0
  assert detached.currentActivitySnapshot.value.activityInfo.value.services == 2, "immutable snapshot survives source scope"
  assert detached.currentActivityInfo.value.services == 2, "info extraction is copied"
  let prefix = admissionHashes(combined.source)
  cycle(combined.source, prefix)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(combined.source,
      prefix) # Scoped success and both backend refusals retain no derived state.
  let after = getOccupiedMem()
  assert before == after, "combined activity ARC release"
  recordArcRelease("pvm_current_block_activity", 1000, before, after)
  echo "PVM current block activity passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fallible fixture I/O remains a strict native failure.
except:
  quit(2)
