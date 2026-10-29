# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Logical GP T sources for complete encoder comparisons; no expected bytes feed these constructors.
import std/assertions
import ../../src/codec/[bounded, assurances, composite]
import ../../src/codec/work/[digest as work_digest, report as work_report]
import ../../src/codec/[owned, report_owned, guarantees]
import ../../src/codec/state/[layout as state_layout, trie as state_trie,
    composition as state_composition, authorization as state_authorization,
    history as state_history, consensus as state_consensus, safrole as state_safrole,
    disputes as state_disputes, availability as state_availability, privileges as state_privileges,
    statistics as state_statistics, workqueues as state_workqueues, outputs as state_outputs]
const
  items = ElementLimit(50000)
  budget = ByteLimit(2000000)
proc patterned[N: static[int]](seed: int): array[N, byte] =
  ## Fixed logical octets expose positional swaps independently of wire encoding.
  result = default(array[N, byte])
  for i in 0..<N: result[i] = byte((seed+i) mod 251)
proc repeated[N: static[int]](value: byte): array[N, byte] =
  ## Canonical sets use distinct constant-octet identities with explicit ordering.
  result = default(array[N, byte])
  for i in 0..<N: result[i] = value
proc roster(count, seed: int): seq[StateValidator] =
  ## Construct the four nominal fields by record/field position, never by decoding expected roster bytes.
  result = newSeq[StateValidator](count)
  for i in 0..<count:
    let start = seed+336*i
    result[i] = StateValidator(bandersnatch: StateBsKey(patterned[32](start)),
      ed25519: StateEdKey(patterned[32](start+32)), bls: StateBlsKey(patterned[144](start+64)),
      metadata: StateValidatorMetadata(patterned[128](start+208)))
proc ticket(seed: int): WinningTicket =
  ## Ticket IDs and E1 attempts retain their exact distinct logical positions.
  WinningTicket(id: WinningTicketId(patterned[32](seed)), attempt: TicketAttempt((seed+32) mod 251))
proc report(profile: StateProfile): OwnedReport =
  ## Encode an authored typed C2 report before immutable capture; expected report bytes are never decoded.
  var source = default(WorkReport)
  source.header.erasureShards = ErasureShards(uint16(profile.current))
  source.core = CoreIndex(uint64(profile.cores)-1)
  source.authorizer = AuthorizerHash(bytes: patterned[32](7))
  source.authGas = Gas(128)
  source.digestCount = 1
  source.digests[0] = WorkDigest(service: ServiceIndex(high(uint32)),
    codeHash: CodeHash(patterned[32](73)), payloadHash: PayloadHash(patterned[32](107)),
    accumulateGas: Gas(high(uint64)), output: successfulWork(BlobSpan(offset: 0, length: 0)),
    refine: RefineLoad(gasUsed: Gas(128), imports: ImportCount(127),
      extrinsicCount: work_digest.ExtrinsicCount(256), extrinsicSize: work_digest.ExtrinsicBytes(
          0x100000000'u64),
      exports: ExportCount(16384)))
  let size = measureReportBorrowed(source, 0, uint64(profile.cores))
  assert size.error == CompositeError.None
  var bytes = newSeq[byte](size.written)
  assert encodeReportBorrowed(source, [], uint64(profile.cores), bytes).error == CompositeError.None
  let captured = decodeOwnedReport(bytes, uint64(profile.cores))
  assert captured.error == OwnershipError.None
  captured.value
proc activityService(id: uint32, maximum: bool): ServiceStatisticsEntry =
  ## Map the eleven GP tuple positions to their named fields rather than observing native encoding.
  let values = if maximum: [high(uint64), high(uint64), high(uint64), high(uint64),
    high(uint64), high(uint64), high(uint64), high(uint64), high(uint64), high(uint64), high(uint64)]
    else: [0'u64, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  result = ServiceStatisticsEntry(service: ServiceIndex(id))
  let positions = [0, 1, 2, 4, 5, 6, 7, 8, 9]
  for measure in low(ServiceMeasure)..high(ServiceMeasure):
    result.statistics.counters[measure] = ActivityNatural(values[positions[ord(measure)]])
  result.statistics.refinementGas = ActivityGas(values[3])
  result.statistics.accumulationGas = ActivityGas(values[10])
proc typedGlobalEntries*(profile: StateProfile, kind: int): array[16, StateEntry] =
  ## Exercise every public chapter encoder from logical fields under one explicit profile.
  assert profile.valid and kind in [0, 1]
  result = default(array[16, StateEntry])
  let cores = int(uint64(profile.cores))
  let slots = int(uint64(profile.epochSlots))
  let validators = ValidatorStateConfig(cores: profile.cores, validators: items, maxBytes: budget)
  var pools = newSeq[AuthorizerRow](cores)
  var queues = newSeq[AuthorizerRow](cores)
  for i in 0..<cores:
    pools[i] = newSeq[AuthorizerHash](i mod 3+1)
    queues[i] = newSeq[AuthorizerHash](80)
    for j in 0..<pools[i].len: pools[i][j] = AuthorizerHash(bytes: patterned[32](i+32*j))
    for j in 0..<80: queues[i][j] = AuthorizerHash(bytes: patterned[32](i+7+32*j))
  let authorization = AuthorizationConfig(cores: profile.cores, maxHashes: items, maxBytes: budget)
  result[0] = authorizationEntry(AuthorizationKind.Pools, pools, authorization).value
  result[1] = authorizationEntry(AuthorizationKind.Queues, queues, authorization).value
  let history = HistoryState(blocks: @[HistoryBlock(header: HistoryHeaderHash(patterned[32](17)),
    superPeak: HistorySuperPeak(patterned[32](49)), state: HistoryStateRoot(patterned[32](81)),
    slot: HistorySlot(high(uint32)), packages: @[ReportedPackage(
      package: PackageHash(bytes: repeated[32](1)), segment: SegmentRoot(bytes: repeated[32](
          7)))])],
    peaks: @[absentHistoryPeak(), presentHistoryPeak(HistoryPeakHash(default(array[32, byte]))),
      presentHistoryPeak(HistoryPeakHash(patterned[32](31)))])
  result[2] = historyStateEntry(history, HistoryConfig(cores: profile.cores, blocks: items,
    perBlock: items, totalPackages: items, peaks: items, maxBytes: budget)).value
  var schedule = ticketSchedule(@[])
  if kind == 0:
    var tickets = newSeq[WinningTicket](slots)
    for i in 0..<slots: tickets[i] = ticket(23+33*i)
    schedule = ticketSchedule(tickets)
  else:
    var keys = newSeq[StateBsKey](slots)
    for i in 0..<slots: keys[i] = StateBsKey(patterned[32](23+32*i))
    schedule = keySchedule(keys)
  result[3] = safroleStateEntry(SafroleState(pending: roster(int(uint64(profile.current)), 11),
    root: StateRingRoot(patterned[144](37)), schedule: schedule, accumulator: @[ticket(43)]),
    SafroleStateConfig(validators: validators, epochSlots: profile.epochSlots,
      maxAccumulator: items, maxBytes: budget)).value
  var disputes = default(DisputeState)
  disputes.reports[JudgmentSet.Good] = @[DisputeHash(repeated[32](1)), DisputeHash(repeated[32](2))]
  disputes.reports[JudgmentSet.Bad] = @[DisputeHash(repeated[32](3))]
  disputes.reports[JudgmentSet.Wonky] = @[DisputeHash(repeated[32](4))]
  disputes.offenders = @[OffenderKey(repeated[32](5))]
  result[4] = disputeStateEntry(disputes, DisputeStateConfig(perSet: items, totalItems: items,
    maxBytes: budget)).value
  var entropy = default(StateEntropy)
  for i in 0..<4: entropy[i] = StateEntropyWord(patterned[32](47+32*i))
  result[5] = entropyEntry(entropy)
  result[6] = validatorEntry(ValidatorChapter.Staging, roster(6, 53), validators).value
  result[7] = validatorEntry(ValidatorChapter.Active, roster(int(uint64(profile.current)), 59),
      validators).value
  result[8] = validatorEntry(ValidatorChapter.Previous, roster(int(uint64(profile.previous)), 61),
      validators).value
  let child = report(profile)
  var guarantee = Guarantee(report: child, slot: GuaranteeSlot(high(uint32)), credentialCount: 2)
  for i in 0..<2:
    guarantee.credentials[i] = GuaranteeCredential(validator: GuarantorIndex(i),
      signature: GuaranteeSignature(repeated[64](byte(17+i))))
  var assignments = newSeq[AvailabilityAssignment](cores)
  assignments[cores-1] = presentAssignment(guarantee, AssignmentSlot(high(uint32)))
  result[9] = availabilityStateEntry(assignments, AvailabilityConfig(
    guarantee: GuaranteeConfig(cores: profile.cores, validators: profile.current, maxBytes: budget),
    maxPresent: items, maxBytes: budget)).value
  result[10] = timeEntry(StateTime(high(uint32)))
  var privileges = PrivilegeState(manager: ServiceIndex(high(uint32)), delegator: ServiceIndex(256),
    registrar: ServiceIndex(0), assigners: newSeq[ServiceIndex](cores), always: @[
      AlwaysAccumulate(service: ServiceIndex(1), gas: PrivilegeGas(high(uint64))),
      AlwaysAccumulate(service: ServiceIndex(256), gas: PrivilegeGas(128)),
      AlwaysAccumulate(service: ServiceIndex(high(uint32)), gas: PrivilegeGas(0))])
  for i in 0..<cores: privileges.assigners[i] = ServiceIndex(i+1)
  result[11] = privilegeStateEntry(privileges, PrivilegeConfig(cores: profile.cores,
    maxAlways: items,
    maxBytes: budget)).value
  var statistics = ActivityState(cores: newSeq[CoreActivity](cores), services: @[
    activityService(1, false), activityService(256, true)])
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    let count = if epoch == StatisticsEpoch.Current: int(uint64(profile.current)) else: int(uint64(
        profile.previous))
    statistics.validators[epoch] = newSeq[ValidatorActivity](count)
    for i in 0..<count:
      let fields = if epoch == StatisticsEpoch.Current: [uint32(i), 1, 127, 128, 65536, high(uint32)]
        else: [uint32(i), 2, 255, 256, 16384, high(uint32)]
      for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
        statistics.validators[epoch][i][measure] = ValidatorCounter(fields[ord(measure)])
  for i in 0..<cores:
    let fields = [0'u64, 127, 128, 255, 256, 16384, 0x100000000'u64]
    for measure in low(CoreMeasure)..high(CoreMeasure): statistics.cores[i].counters[
        measure] = ActivityNatural(fields[ord(measure)])
    statistics.cores[i].gas = ActivityGas(high(uint64))
  result[12] = activityStateEntry(statistics, ActivityConfig(cores: profile.cores,
    current: profile.current, previous: profile.previous, maxServices: items,
    maxBytes: budget)).value
  let dependencies = @[PackageHash(bytes: repeated[32](1)), PackageHash(bytes: repeated[32](2))]
  var ready = newSeq[ReadyRow](slots)
  var accumulated = newSeq[AccumulatedRow](slots)
  ready[0] = @[ReadyItem(report: child, dependencies: dependencies)]
  accumulated[0] = dependencies
  let work = WorkQueueConfig(epochSlots: profile.epochSlots, cores: profile.cores, perSlot: items,
    totalItems: items, perDependencies: items, totalDependencies: items,
    reportBytes: budget, maxBytes: budget)
  result[13] = readyStateEntry(ready, work).value
  result[14] = accumulatedStateEntry(accumulated, work).value
  result[15] = outputLogEntry(@[
    AccumulationOutput(service: ServiceIndex(high(uint32)), commitment: OutputCommitment(patterned[
        32](67))),
    AccumulationOutput(service: ServiceIndex(0), commitment: OutputCommitment(default(array[32,
        byte]))),
    AccumulationOutput(service: ServiceIndex(high(uint32)), commitment: OutputCommitment(patterned[
        32](71)))],
    OutputLogConfig(items: items, maxBytes: budget)).value
