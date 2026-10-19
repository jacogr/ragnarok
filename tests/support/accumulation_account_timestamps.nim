# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent timestamp octets, complete-map roots and genuine statistics ownership witnesses for account finalization.

import std/assertions
import ../../src/codec/[bounded, composite, header, state_accounts, state_layout, state_trie, state_statistics]
import ../../src/state/[accumulation_accounts, accumulation_statistics, accumulation_finalization, store]
import ./report_context

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

proc accountPolicy*(services = 4'u64, bytes = 356'u64): AccumulationAccountConfig =
  ## Explicit selected-service and aggregate metadata limits do not replace inherited complete-map store limits.
  AccumulationAccountConfig(services: ElementLimit(services), metadataBytes: ByteLimit(bytes))

proc stamped(raw: seq[byte], slot: uint32): seq[byte] =
  ## Author the four normative E4 timestamp octets directly, independently of the production metadata codec/update.
  result = newSeq[byte](raw.len)
  for index, value in raw:
    result[index] = (if index in 81..84: byte((slot shr ((index-81)*8)) and 255) else: value)

proc checkAccountProjection*() =
  ## Pure projection distinguishes absent, unselected, malformed and already-current accounts without hashing.
  var metadata = ServiceMetadata(codeHash: CodeHash(default(array[32, byte])),
      balance: AccountBalance(high(uint64)),
    depositOffset: AccountBalance(128), minimumAccumulationGas: Gas(255), minimumTransferGas: Gas(65536),
    storageBytes: AccountStorageBytes(0x123456789abcdef0'u64), storageItems: AccountStorageItems(
        high(uint32)),
    created: AccountSlot(17), lastAccumulation: AccountSlot(1), parent: ServiceIndex(high(uint32)))
  let first = serviceMetadataEntry(ServiceIndex(42), metadata, ByteLimit(89)).value
  metadata.lastAccumulation = AccountSlot(2)
  let current = serviceMetadataEntry(ServiceIndex(99), metadata, ByteLimit(89)).value
  let unrelated = StateEntry(key: chapterKey(StateChapter(250)), value: @[0'u8, 255, 31])
  let malformed = StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(11)), value: @[1'u8])
  let store = newStateStore([first, current, unrelated, malformed], report_context.limits()).value
  let prior = store.snapshot.value
  let services = [ServiceIndex(42), ServiceIndex(77), ServiceIndex(99), ServiceIndex(high(uint32))]
  failHash(1)
  let projected = projectAccumulationAccounts(prior, services, AccountSlot(2), accountPolicy(4, 178)).value
  assert projected.info.services == 4 and projected.info.accounts == 2 and projected.info.updates == 1
  assert uint32(projected.info.slot) == 2 and projected.writes.len == 1
  assert projected.writes[0].value == stamped(first.value, 2)
  assert array[31, byte](projected.writes[0].key) == array[31, byte](first.key)
  assert prior.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(77))).error ==
      StateStoreError.MissingKey
  assert prior.lookup(first.key).value.bytes == first.value
  for policy in [accountPolicy(3, 178), accountPolicy(4, 177), accountPolicy(0, 0)]:
    assert projectAccumulationAccounts(prior, services, AccountSlot(2), policy).error ==
        AccumulationAccountError.LimitExceeded
  for identities in [@[ServiceIndex(99), ServiceIndex(42)], @[ServiceIndex(42), ServiceIndex(42)]]:
    assert projectAccumulationAccounts(prior, identities, AccountSlot(2), accountPolicy()).error ==
        AccumulationAccountError.InvalidServices
  let absent = default(StateStoreSnapshot)
  assert projectAccumulationAccounts(absent, [], AccountSlot(2), accountPolicy()).error ==
      AccumulationAccountError.InvalidState
  let empty = projectAccumulationAccounts(prior, [], AccountSlot(high(uint32)), accountPolicy(0, 0)).value
  assert empty.info.services == 0 and empty.writes.len == 0
  let maximum = projectAccumulationAccounts(prior, [ServiceIndex(42)], AccountSlot(high(uint32)),
      accountPolicy(high(uint64), high(uint64))).value
  assert maximum.writes[0].value == stamped(first.value, high(uint32))
  var copied = projected
  copied.writes[0].value[0] = 255 # Caller-owned projection bytes grant no access to immutable source storage.
  assert prior.lookup(first.key).value.bytes == first.value
  assert hashCalls() == 0
  failHash(0)
  for mode in 0..<4:
    var raw = first.value
    case mode
    of 0: raw = @[] # Present-empty is malformed, distinct from a missing account.
    of 1: raw.setLen(88) # A truncated fixed record cannot be copied as valid metadata.
    of 2: raw.add(0) # Stored service records require exact consumption rather than prefix decoding.
    else: raw[0] = 1 # Full-width unsupported versions retain their actual decoder reason.
    let source = newStateStore([StateEntry(key: first.key, value: raw)], report_context.limits()).value
    failHash(1)
    let refused = projectAccumulationAccounts(source.snapshot.value, [ServiceIndex(42)],
        AccountSlot(2), accountPolicy())
    if mode == 3:
      assert refused.error == AccumulationAccountError.MetadataFailure and refused.metadataError ==
          ServiceMetadataError.UnsupportedVersion
    else:
      assert refused.error == AccumulationAccountError.InvalidState
    assert hashCalls() == 0
    failHash(0)

proc expectedServiceIds(services: openArray[uint32]): seq[ServiceIndex] =
  ## Convert only bounded authored test identities; the production API keeps nominal protocol service indices.
  result = newSeq[ServiceIndex](services.len)
  for index, service in services:
    result[index] = ServiceIndex(service)

proc checkAccountTimestamps*(source: PreparedAccumulationStatistics, expected: openArray[uint32]) =
  ## Genuine finalized activity updates exactly the expected accounts at authenticated slot two, preserving the full prior map.
  let prior = source.statisticsSource.value.finalAccumulationState.value
  let original = prior.commitment.root
  let plan = prepareAccumulationAccounts(source, accountPolicy()).value
  let info = plan.accumulationAccountInfo.value
  assert uint32(info.slot) == 2 and info.services == expected.len and info.accounts == expected.len
  assert info.updates == expected.len
  var writes: seq[StateWrite] = @[]
  for service in expected:
    let key = chapterServiceKey(StateChapter(255), ServiceIndex(service))
    let raw = prior.lookup(key).value.bytes
    let bytes = stamped(raw, 2)
    assert plan.accumulationAccountState.value.lookup(key).value.bytes == bytes
    assert prior.lookup(key).value.bytes == raw
    writes.add(StateWrite(key: key, kind: StateWriteKind.Put, value: bytes))
  var wanted = forkStateStore(prior).value
  let posterior = wanted.apply(writes).value
  assert array[32, byte](posterior.commitment.root) == array[32, byte](
      plan.accumulationAccountState.value.commitment.root)
  assert array[32, byte](original) == array[32, byte](prior.commitment.root)
  assert sameStateSnapshot(plan.accumulationAccountSource.value.statisticsSource.value.finalAccumulationState.value, prior)
  var observed = info
  observed.updates = 0
  assert plan.accumulationAccountInfo.value.updates == expected.len
  failHash(1)
  let canonical = projectAccumulationAccounts(plan.accumulationAccountState.value,
    expectedServiceIds(expected), AccountSlot(2), accountPolicy()).value
  assert canonical.writes.len == 0 # Applying the same timestamp is a pure no-op, even with hashing disabled.
  var branch = forkStateStore(plan.accumulationAccountState.value).value
  assert sameStateSnapshot(branch.apply(canonical.writes).value,
      plan.accumulationAccountState.value)
  var tight = accountPolicy()
  if expected.len != 0:
    tight.services = ElementLimit(uint64(expected.len-1))
    assert prepareAccumulationAccounts(source, tight).error ==
        AccumulationAccountError.LimitExceeded
    tight = accountPolicy()
    tight.metadataBytes = ByteLimit(uint64(expected.len*89-1))
    assert prepareAccumulationAccounts(source, tight).error ==
        AccumulationAccountError.LimitExceeded
  else:
    assert sameStateSnapshot(plan.accumulationAccountState.value,
        prior) # Empty activity preserves initialized map identity.
  assert hashCalls() == 0
  failHash(0)
  if expected.len != 0:
    for successful in [0, 2]:
      hashAfter(cint(successful))
      let refused = prepareAccumulationAccounts(source, accountPolicy())
      assert refused.error == AccumulationAccountError.StateFailure and refused.stateError ==
          StateStoreError.BackendFailure
      failHash(0)
      assert sameStateSnapshot(source.statisticsSource.value.finalAccumulationState.value, prior)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let selected = prepareAccumulationAccounts(source, accountPolicy()).value
    assert selected.accumulationAccountInfo.value.updates == expected.len
  assert before == getOccupiedMem() # Private writes, forked maps and retained source graphs release every cycle.
