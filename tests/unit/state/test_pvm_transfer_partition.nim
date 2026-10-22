# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_transfer_partition_arc_release"}

## Exact stable partition agrees with independent finite paper predicates across every small supervision graph.
import std/[assertions, syncio]
import ../../../src/state/[accumulation_transfer_partition, store]
import ../../../src/codec/[bounded, composite, state_accounts, state_layout, state_trie, c2_records]
import ../../support/arc_evidence

# Partitioning only reads canonical metadata; it must perform no native hash work.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

proc account(service, supervisor: uint32, expected = high(uint32), created = high(
    uint32)): StateEntry =
  ## Fixed independent incarnation values separate stale identifiers from current supervision.
  let ownSlot = if created == high(uint32): (if service <=
      3: 10'u32+service else: 17'u32) else: created
  let supervisorSlot = if expected == high(uint32): (if supervisor <=
      3: 10'u32+supervisor else: 17'u32) else: expected
  serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(supervisor: ServiceIndex(supervisor),
      supervisorCreated: AccountSlot(supervisorSlot), created: AccountSlot(ownSlot)), ByteLimit(
          ServiceMetadataBytes)).value
proc snapshot(entries: openArray[StateEntry]): StateStoreSnapshot =
  ## Opaque complete-map values permit explicit malformed-metadata refusals without patching a decoder.
  newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(16),
      perValue: ByteLimit(256), totalValueBytes: ByteLimit(4096), nodes: TrieNodeLimit(1000)),
      writes: ElementLimit(4), writeValueBytes: ByteLimit(1024))).value.snapshot.value
proc limits(transfers = 16'u64, services = 16'u64, checks = 1000'u64): TransferPartitionLimits =
  ## Input and work budgets are independent and deliberately finite.
  TransferPartitionLimits(transfers: ElementLimit(transfers), services: ElementLimit(services),
      checks: ElementLimit(checks))
proc transfer(destination: uint32, ordinal = 0): DeferredTransfer =
  ## Distinguishable fixed fields prove copying and ordered duplicate delivery, not only destination membership.
  var bytes = default(array[128, byte])
  for index in 0..<128:
    bytes[index] = byte((index+ordinal*13) mod 256) # Bounded fixture ordinals are at most three.
  DeferredTransfer(source: ServiceIndex(uint32(500+ordinal)), destination: ServiceIndex(
      destination), destinationSupervisor: ordinal mod 2 != 0, amount: TransferBalance(uint64(
          100+ordinal)),
      gas: Gas(uint64(9+ordinal)), memo: TransferMemo(bytes))
proc checkRecord(actual, expected: DeferredTransfer) =
  ## All output fields are fixed copies, including raw memo octets and the protected-credit flag.
  assert uint32(actual.source) == uint32(expected.source), "source identity remains exact"
  assert uint32(actual.destination) == uint32(expected.destination), "destination identity remains exact"
  assert actual.destinationSupervisor == expected.destinationSupervisor, "destination pool flag remains exact"
  assert uint64(actual.amount) == uint64(expected.amount), "full-width amount remains exact"
  assert uint64(actual.gas) == uint64(expected.gas), "full-width gas remains exact"
  let actualMemo = array[128, byte](actual.memo)
  let expectedMemo = array[128, byte](expected.memo)
  assert actualMemo == expectedMemo, "every copied memo octet remains exact"
proc check(plan: PreparedTransferPartition, source: openArray[DeferredTransfer], held: openArray[bool]) =
  ## Compare ordered subsequences against an independent per-source-row paper decision.
  assert source.len == held.len, "independent predicate covers every input row"
  var accepted = 0
  var queued = 0
  for index, row in source:
    let kind = if held[index]: TransferPartitionKind.Queued else: TransferPartitionKind.Accepted
    let ordinal = if held[index]: queued else: accepted
    let found = plan.partitionTransferAt(kind, TransferPartitionIndex(uint64(ordinal)))
    assert found.error == TransferPartitionError.None, "selected ordered output exists"
    checkRecord(found.value, row)
    if held[index]: inc queued
    else: inc accepted
  let info = plan.partitionInfo.value
  assert info.transfers == source.len and info.accepted == accepted and info.queued == queued,
      "observed partition counts match every independent source row"
  assert plan.partitionCount(TransferPartitionKind.Accepted).value == accepted, "accepted count remains exact"
  assert plan.partitionCount(TransferPartitionKind.Queued).value == queued, "queued count remains exact"
  for kind in [TransferPartitionKind.Accepted, TransferPartitionKind.Queued]:
    let past = plan.partitionTransferAt(kind, TransferPartitionIndex(high(uint64)))
    assert past.error == TransferPartitionError.InvalidIndex, "bound full-width output ordinals before native narrowing"

# This model uses fixed boolean sets and a supplied graph; it never decodes production metadata or reads its caches.
proc paper(graph: array[3, uint32], active: int, transfers: openArray[DeferredTransfer]): seq[bool] =
  result = newSeq[bool](transfers.len)
  var recipients = default(array[3, bool])
  for index, row in transfers:
    let destination = uint32(row.destination)
    if destination == 4: continue # Missing services never join the set of present accepted recipients.
    let target = int(destination)-1
    let parent = if graph[target] == 0: destination else: graph[target]
    let parentIndex = int(parent)-1
    var queued = parent != destination and ((active and (1 shl parentIndex)) != 0 or recipients[parentIndex])
    for service in 0..<3:
      let serviceId = uint32(service+1)
      let supervisor = if graph[service] == 0: serviceId else: graph[service]
      if recipients[service] and serviceId != destination and supervisor == destination:
        queued = true # Literal second existential predicate, independent of cache/insertion order.
    result[index] = queued
    if not queued: recipients[target] = true # Literal I' update only for accepted present recipients.

var corpus = 0
for encodedGraph in 0..<64:
  var graph = default(array[3, uint32])
  var remaining = encodedGraph
  for index in 0..<3:
    graph[index] = uint32(remaining mod 4)
    remaining = remaining div 4 # Every supervisor is absent0 or one of the three current services.
  let state = snapshot([account(1, graph[0]), account(2, graph[1]), account(3, graph[2])])
  for activeMask in 0..<8:
    var active: seq[ServiceIndex] = @[]
    for index in 0..<3:
      if (activeMask and (1 shl index)) != 0: active.add(ServiceIndex(uint32(index+1)))
    for count in 0..3:
      var cases = 1
      for index in 0..<count: cases *= 4 # Frozen bound count<=3 proves this finite radix extent fits.
      for encodedTransfers in 0..<cases:
        var values = newSeq[DeferredTransfer](count)
        var encoded = encodedTransfers
        for index in 0..<count:
          values[index] = transfer(uint32(encoded mod 4+1), index)
          encoded = encoded div 4
        let expected = paper(graph, activeMask, values)
        let planned = prepareAccumulationTransferPartition(state, values, active, limits())
        assert planned.error == TransferPartitionError.None, "every finite valid paper case produces a partition"
        check(planned.value, values, expected)
        assert sameStateSnapshot(planned.value.partitionPrior.value, state), "every decision retains the exact input prior owner"
        inc corpus
assert corpus == 43520, "complete 64-graph,8-active-set,85-transfer-sequence corpus"

# Current creation slots, self supervision and unknown accounts are checked independently of the finite model.
let current = snapshot([account(1, 2), account(2, 2)])
let stale = snapshot([account(1, 2, expected = 11), account(2, 2)])
let absent = snapshot([account(1, 2)])
let values = @[transfer(1), transfer(2, 1), transfer(1, 2)]
let active = @[ServiceIndex(2)]
check(prepareAccumulationTransferPartition(current, values, active, limits()).value, values, [true,
    false, true])
check(prepareAccumulationTransferPartition(stale, values, active, limits()).value, values, [false,
    false, false])
check(prepareAccumulationTransferPartition(absent, values, active, limits()).value, values, [false,
    false, false])
let duplicatedActive = @[ServiceIndex(2), ServiceIndex(2)]
check(prepareAccumulationTransferPartition(current, values, duplicatedActive, limits()).value,
    values, [true, false, true])
let ordered = @[transfer(1), transfer(2, 1)]
let reversed = @[transfer(2), transfer(1, 1)]
check(prepareAccumulationTransferPartition(current, ordered, [], limits()).value, ordered, [false, true])
check(prepareAccumulationTransferPartition(current, reversed, [], limits()).value, reversed, [false, true])
var full = transfer(1)
full.amount = TransferBalance(high(uint64))
full.gas = Gas(high(uint64))
full.destinationSupervisor = true
check(prepareAccumulationTransferPartition(current, [full], active, limits()).value, [full], [true])
var zero = full
zero.amount = TransferBalance(0)
zero.gas = Gas(0)
check(prepareAccumulationTransferPartition(current, [zero], active, limits()).value, [zero], [true])
let maximum = snapshot([account(1, high(uint32)), account(high(uint32), high(uint32))])
let highId = @[transfer(1), transfer(high(uint32), 1)]
check(prepareAccumulationTransferPartition(maximum, highId, [ServiceIndex(high(uint32))], limits(
  )).value, highId, [true, false])

# Local resource refusals never impersonate an empty partition, a missing account or a scheduling decision.
let valid = prepareAccumulationTransferPartition(current, values, active, limits()).value
let used = valid.partitionInfo.value.checks
assert used > 0
let exact = prepareAccumulationTransferPartition(current, values, active, limits(checks = used))
assert exact.error == TransferPartitionError.None, "exact work budget succeeds"
let short = prepareAccumulationTransferPartition(current, values, active, limits(checks = used-1))
assert short.error == TransferPartitionError.LimitExceeded, "one fewer predicate check grants no partial plan"
let noTransfers = prepareAccumulationTransferPartition(current, values, active, limits(transfers = 2))
assert noTransfers.error == TransferPartitionError.LimitExceeded, "source transfer extent is independently bounded"
let noServices = prepareAccumulationTransferPartition(current, values, active, limits(services = 0))
assert noServices.error == TransferPartitionError.LimitExceeded, "active-service source extent is independently bounded"
let badPrior = prepareAccumulationTransferPartition(default(StateStoreSnapshot), [], [], default(
    TransferPartitionLimits))
assert badPrior.error == TransferPartitionError.InvalidState, "default prior cannot authorize even an empty plan"
let emptyState = snapshot([])
let empty = prepareAccumulationTransferPartition(emptyState, [], [], default(
    TransferPartitionLimits)).value
check(empty, [], [])
assert empty.partitionInfo.value.checks == 0, "empty work fits exactly zero local budgets"
let damaged = StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(2)), value: @[0'u8])
let badTarget = snapshot([damaged])
let badTargetPlan = prepareAccumulationTransferPartition(badTarget, [transfer(2)], [], limits())
assert badTargetPlan.error == TransferPartitionError.MalformedState, "present malformed target never becomes absent"
let badNominee = snapshot([account(1, 2), damaged])
let badNomineePlan = prepareAccumulationTransferPartition(badNominee, [transfer(1)], [], limits())
assert badNomineePlan.error == TransferPartitionError.MalformedState, "malformed supervisor cannot fall back to self"
check(prepareAccumulationTransferPartition(badTarget, [transfer(4)], [], limits()).value, [transfer(
    4)], [false])

# Plans own complete copied records and retain the old prior independently of later caller/store mutations.
var caller = values
var callersActive = active
let independent = prepareAccumulationTransferPartition(current, caller, callersActive, limits()).value
let first = caller[0]
caller[0] = transfer(4)
callersActive[0] = ServiceIndex(1)
checkRecord(independent.partitionTransferAt(TransferPartitionKind.Queued, TransferPartitionIndex(
    0)).value, first)
var working = forkStateStore(current).value
let changed = account(2, 2, created = 99)
discard working.apply([StateWrite(key: changed.key, kind: StateWriteKind.Put,
    value: changed.value)]).value
assert sameStateSnapshot(independent.partitionPrior.value, current), "later store publication cannot alter captured supervisor incarnations"
assert not sameStateSnapshot(independent.partitionPrior.value, working.snapshot.value), "independent later prior never replaces the retained source owner"
failHash(1)
let unhashed = prepareAccumulationTransferPartition(current, values, active, limits())
assert unhashed.error == TransferPartitionError.None and hashCalls() == 0, "partition performs no hashing or state publication"
failHash(0)
let defaultInfo = default(PreparedTransferPartition).partitionInfo
assert defaultInfo.error == TransferPartitionError.Uninitialized, "default query grants no successful counts"
let defaultPrior = default(PreparedTransferPartition).partitionPrior
assert defaultPrior.error == TransferPartitionError.Uninitialized, "default query grants no prior state"
let defaultCount = default(PreparedTransferPartition).partitionCount(TransferPartitionKind.Accepted)
assert defaultCount.error == TransferPartitionError.Uninitialized, "default query grants no empty output"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let owned = prepareAccumulationTransferPartition(current, values, active, limits()).value
  check(owned, values, [true, false, true]) # Release record copies, source ordinals and prior handles every iteration.
let after = getOccupiedMem()
assert before == after, "partition owners release without retaining parent plans or borrowed inputs"
recordArcRelease("pvm_transfer_partition", 1000, before, after)
echo "PVM transfer partition passed"
echo "PAPER_PARTITION cases=43520"
echo "ARC_RELEASE cycles=1000 unchanged"
