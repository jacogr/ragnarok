# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine block sources exercise prior solicitation, posterior fulfillment and exact complete-map publication with independent expected bytes.

import std/assertions
import ../../src/state/[block_preimages, preimages, recent_history, store]
import ../../src/codec/[bounded, composite, owned, header, state_layout, state_trie,
  state_service_values]
import ../../src/crypto/primitives
import ./[report_context, pvm_accumulation_provision]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc blockPreimagePolicy*(): BlockPreimageConfig =
  ## Separate complete-frame capture from actual item/payload hashing work.
  BlockPreimageConfig(frameBytes: ByteLimit(19), preimages: PreimageLimits(
    items: ElementLimit(3), perBlob: ByteLimit(2), totalBlobBytes: ByteLimit(3)))
proc blockPreimageWire*(provided = false): seq[byte] =
  ## Literal canonical service/blob pairs include an empty blob, or actual guest-provided values.
  if provided: return @[2'u8, 42, 0, 0, 0, 1, 73, 99, 0, 0, 0, 1, 81]
  @[3'u8, 42, 0, 0, 0, 0, 42, 0, 0, 0, 2, 1, 2, 99, 0, 0, 0, 1, 3]
proc preimageRequests*(): seq[StateEntry] =
  ## All three requests enter the original signed parent, including the empty-blob request.
  @[provisionRequest(42, @[]), provisionRequest(42, @[1'u8, 2]), provisionRequest(99, @[3'u8])]
proc valueEntry(service: uint32, blob: seq[byte]): StateEntry =
  ## Namespace primitives frame literal values; they do not execute the transition being tested.
  let hash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
  servicePreimageEntry(ServiceIndex(service), hash, blob,
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(uint64(blob.len)))).value
proc checkBlockPreimages*(source: PublishedRecentHistory, original: openArray[StateEntry],
    empty = false, provided = false): PublishedBlockPreimages =
  ## Compare every complete-map value/root and protect exact source identity across refusal, retry and detached lifetimes.
  let prior = source.publishedRecentState.value
  let plan = prepareBlockPreimages(source, blockPreimagePolicy()).value
  let admitted = plan.blockPreimageAdmission.value
  let info = plan.blockPreimageInfo.value
  assert uint32(info.slot) == 2
  assert info.admission.items == (if empty: 0 elif provided: 2 else: 3)
  assert info.admission.services == (if empty: 0 else: 2)
  assert uint64(info.admission.bytes) == (if empty: 0'u64 elif provided: 2'u64 else: 3'u64)
  assert sameStateSnapshot(plan.blockPreimagePrior.value, prior)
  assert sameStateSnapshot(plan.blockPreimageSource.value.publishedRecentState.value, prior)
  assert not sameStateSnapshot(admitted.preimagePrior.value, prior)
  let captured = admitted.preimageSource.value
  assert captured.ownedInfo.value.blobCount == info.admission.items
  if not empty:
    let first = admitted.provisionAt(ProvisionIndex(0)).value
    assert uint32(first.service) == 42 and uint64(first.count) == (if provided: 1'u64 else: 2'u64)
    assert uint64(first.bytes) == (if provided: 1'u64 else: 2'u64)
    var copied = info
    copied.admission.items = 999
    assert plan.blockPreimageInfo.value.admission.items == info.admission.items
  var exact = blockPreimagePolicy()
  exact.frameBytes = ByteLimit(uint64(captured.ownedInfo.value.consumed))
  exact.preimages.items = ElementLimit(uint64(info.admission.items))
  exact.preimages.perBlob = ByteLimit(if empty: 0'u64 elif provided: 1'u64 else: 2'u64)
  exact.preimages.totalBlobBytes = ByteLimit(uint64(info.admission.bytes))
  assert prepareBlockPreimages(source, exact).error == BlockPreimageError.None
  var short = exact
  short.frameBytes = ByteLimit(uint64(captured.ownedInfo.value.consumed-1))
  failHash(3)
  assert prepareBlockPreimages(source, short).error == BlockPreimageError.LimitExceeded
  if not empty:
    short = exact
    short.preimages.items = ElementLimit(uint64(info.admission.items-1))
    assert prepareBlockPreimages(source, short).error == BlockPreimageError.LimitExceeded
    short = exact
    short.preimages.perBlob = ByteLimit(uint64(exact.preimages.perBlob)-1)
    let blobLimit = prepareBlockPreimages(source, short)
    assert blobLimit.error == BlockPreimageError.PreimageFailure and blobLimit.preimageError ==
        PreimageTransitionError.LimitExceeded
    short = exact
    short.preimages.totalBlobBytes = ByteLimit(uint64(info.admission.bytes)-1)
    assert prepareBlockPreimages(source, short).preimageError ==
        PreimageTransitionError.LimitExceeded
  assert hashCalls() == 0 # Every local limit refuses before payload/namespace hashing.
  failHash(0)
  var wide = exact
  wide.frameBytes = ByteLimit(high(uint64))
  wide.preimages = PreimageLimits(items: ElementLimit(high(uint64)), perBlob: ByteLimit(high(uint64)),
    totalBlobBytes: ByteLimit(high(uint64)))
  assert prepareBlockPreimages(source, wide).value.blockPreimageInfo.value.admission.items ==
      info.admission.items
  if not empty:
    for successful in [0, 1]:
      hashAfter(cint(successful))
      let refused = prepareBlockPreimages(source, exact)
      assert refused.error == BlockPreimageError.PreimageFailure and refused.preimageError ==
          PreimageTransitionError.BackendFailure
      failHash(0) # Content and request-key hashing failures preserve all source snapshots.
  var entries: seq[StateEntry] = @[]
  for record in original:
    entries.add(StateEntry(key: record.key, value: prior.lookup(record.key).value.bytes))
  let output = chapterKey(StateChapter(16))
  entries.add(StateEntry(key: output, value: prior.lookup(output).value.bytes))
  if provided:
    for index in 0..<2:
      let record = valueEntry(if index == 0: 42'u32 else: 99'u32, if index == 0: @[73'u8] else: @[81'u8])
      assert prior.lookup(record.key).value.bytes == record.value
      entries.add(record) # Actual accumulation already fulfilled these exact requests before block integration.
  assert entries.len == prior.commitment.entries
  var foreign = newStateStore(entries, report_context.limits()).value
  failHash(3)
  assert advanceBlockPreimages(foreign, plan).error == BlockPreimageError.ForeignState
  var invalid = default(StateStore)
  assert advanceBlockPreimages(invalid, plan).error == BlockPreimageError.InvalidState
  assert hashCalls() == 0
  failHash(0)
  if not empty and not provided:
    for successful in [0, 2, 6]:
      var caller = forkStateStore(prior).value
      hashAfter(cint(successful))
      let refused = advanceBlockPreimages(caller, plan)
      assert refused.error == BlockPreimageError.PreimageFailure and refused.preimageError ==
          PreimageTransitionError.BackendFailure
      failHash(0)
      assert sameStateSnapshot(caller.snapshot.value,
          prior) # Early namespace, later key and root failures all preserve the exact caller.
    for index in 0..<3:
      let service = if index < 2: 42'u32 else: 99'u32
      let blob = if index == 0: newSeq[byte]() elif index == 1: @[1'u8, 2] else: @[3'u8]
      let request = provisionRequest(service, blob)
      for ordinal in 0..<entries.len:
        if array[31, byte](entries[ordinal].key) == array[31, byte](request.key):
          assert entries[ordinal].value == @[0'u8]
          entries[ordinal].value = @[1'u8, 2, 0, 0,
              0] # Literal one Available timestamp at the authenticated candidate slot.
      entries.add(valueEntry(service, blob))
  let wanted = stateTrieRoot(entries, report_context.limits().trie).value
  if empty or provided: failHash(3) # Entirely disregarded input performs no new namespace/root hashing.
  let published = publishBlockPreimages(plan).value
  let posterior = published.publishedPreimageState.value
  assert array[32, byte](posterior.commitment.root) == array[32, byte](wanted.root)
  assert posterior.commitment.entries == entries.len
  for record in entries: assert posterior.lookup(record.key).value.bytes == record.value
  if empty or provided:
    assert sameStateSnapshot(posterior, prior) and hashCalls() == 0
  failHash(0)
  var caller = forkStateStore(prior).value
  let advanced = advanceBlockPreimages(caller, plan).value
  assert sameStateSnapshot(caller.snapshot.value, advanced.publishedPreimageState.value)
  if not empty and not provided:
    failHash(3)
    assert advanceBlockPreimages(caller, plan).error == BlockPreimageError.ForeignState
    assert hashCalls() == 0
    failHash(0)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareBlockPreimages(source, exact).value
    let committed = publishBlockPreimages(local).value
    assert array[32, byte](committed.publishedPreimageState.value.commitment.root) == array[32,
        byte](wanted.root)
  assert before == getOccupiedMem() # Original frame/certificate, staged writes and independent successor owners retire each cycle.
  assert sameStateSnapshot(source.publishedRecentState.value, prior)
  assert publishBlockPreimages(default(PreparedBlockPreimages)).error ==
      BlockPreimageError.InvalidSource
  assert prepareBlockPreimages(default(PublishedRecentHistory), exact).error ==
      BlockPreimageError.InvalidSource
  published
