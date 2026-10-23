# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Single-buffer journal framing preserves strict mutable-record validation, exact bytes, replay and ownership.
# @@Verification={"arc": "storage_journal_framing_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_snapshot_samples]
import ../../../src/storage/[node_repository, node_records, record_codec, journal_codec, snapshot_codec]
import ../../../src/codec/[bounded, state_trie]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Real hash refusal distinguishes preflight from mandatory raw integrity and the outer checksum.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe exact attempts instead of treating frame reservations as existing integrity authority.
proc batch(source: SnapshotFixture): TrieExport =
  ## Detached mutable transport supplies no retained graph or validation privilege to its encoder.
  let metadata = source.selection.commitment
  TrieExport(root: metadata.root, entries: uint64(metadata.entries), nodes: metadata.nodes,
    records: exportRepositorySelection(source.selection,
        source.limits.repository.codec.records).value)
proc exercise(source: TrieExport, limits: SnapshotLimits) =
  ## Compare reserved bodies with strict unframed bytes, then verify both actual frame domains through replay.
  let codec = limits.repository.codec
  reset(0)
  let expected = encodeTrieExport(source, codec).value
  let integrityCalls = calls()
  for prefix in [0, 1, 24]:
    # Empty and unaligned reservations must not change any body byte or suppress a local hash.
    for suffix in [0, 1, 32]:
      let size = prefix+expected.len+suffix
      reset(0)
      var framed = encodeFramedTrieExport(source, codec, uint64(prefix), uint64(suffix), ByteLimit(size))
      assert framed.error == RecordError.None and calls() == integrityCalls
      let before = getOccupiedMem()
      var bytes = framed.takeValue
      assert framed.error == RecordError.Uninitialized and getOccupiedMem() == before
      for index in 0..<prefix: assert bytes[index] == 0
      for index in 0..<expected.len: assert bytes[prefix+index] == expected[index]
      for index in prefix+expected.len..<size: assert bytes[index] == 0
      bytes[0] = bytes[0] xor 255 # Detached reserved/output bytes cannot modify the caller's raw transport.
      reset(1)
      assert encodeFramedTrieExport(source, codec, uint64(prefix), uint64(suffix),
        ByteLimit(size-1)).error == RecordError.LimitExceeded
      assert calls() == 0
  for mode in 0..<6:
    var short = codec
    if mode == 0: short.encoded = ByteLimit(expected.len-1) # Whole-frame space never relaxes body extent policy.
    elif mode == 1: short.records.records = TrieNodeLimit(source.records.len-1)
    elif mode == 2: short.trie.perValue = ByteLimit(32)
    elif mode == 3: short.records.valueBytes = ByteLimit(65)
    elif mode == 4: short.trie.totalValueBytes = ByteLimit(65)
    else: short.trie.items = ElementLimit(1) # Complete target metadata remains independent of changed records.
    assert encodeFramedTrieExport(source, short, 16, 32, limits.bytes).error ==
        RecordError.LimitExceeded
    assert calls() == 0
  let before = getOccupiedMem()
  for extent in [uint64(high(int)), uint64(high(int))+1, high(uint64)]:
    # Impossible full-width extents refuse before narrowing, wrapping, allocation or cryptography.
    assert encodeFramedTrieExport(source, codec, extent, extent, ByteLimit(high(uint64))).error ==
      RecordError.LimitExceeded
    assert encodeFramedTrieExport(source, codec, extent, 0, ByteLimit(high(uint64))).error ==
      RecordError.LimitExceeded
    assert encodeFramedTrieExport(source, codec, 0, extent, ByteLimit(high(uint64))).error ==
      RecordError.LimitExceeded
  assert calls() == 0 and getOccupiedMem() == before
  for contextual in [false, true]:
    # The explicit node/context domains keep their exact different prefix sizes and checksum coverage.
    let context = if contextual: @[1'u8, 2, 3] else: @[]
    let prefix = if contextual: 24+context.len else: 16
    let size = prefix+expected.len+32
    reset(0)
    var encoded = if contextual:
        encodeContextJournalFrame(RepositoryGeneration(1), source, context, ByteLimit(3), codec,
            ByteLimit(size))
      else: encodeJournalFrame(RepositoryGeneration(1), source, codec, ByteLimit(size))
    assert encoded.error == FrameError.None and calls() == integrityCalls+1
    var wire = encoded.takeValue
    assert wire.len == size and encoded.error == FrameError.Uninitialized
    for index in 0..<expected.len: assert wire[prefix+index] == expected[index]
    let decoded = if contextual: decodeContextJournalFrame(wire, ByteLimit(3), codec, ByteLimit(size))
      else: decodeJournalFrame(wire, codec, ByteLimit(size))
    assert decoded.error == FrameError.None and uint64(decoded.value.generation) == 1
    assert decoded.value.context == context
    assert encodeTrieExport(decoded.value.batch, codec).value == expected
    var owner = newNodeRepository(limits.repository)
    let replayed = if contextual:
        replayContextJournalFrame(owner, owner.snapshot.value, wire, ByteLimit(3), ByteLimit(size))
      else: replayJournalFrame(owner, owner.snapshot.value, wire, ByteLimit(size))
    assert replayed.error == FrameError.None and replayed.value.context == context
    assert array[32, byte](replayed.value.view.commitment.root) == array[32, byte](source.root)
    assert owner.close == RepositoryError.None
    wire[0] = wire[0] xor 255
    assert replayed.value.context == context # Replay retains no mutable borrow into the source frame.
    reset(1)
    let short = if contextual:
        encodeContextJournalFrame(RepositoryGeneration(1), source, context, ByteLimit(3), codec,
            ByteLimit(size-1))
      else: encodeJournalFrame(RepositoryGeneration(1), source, codec, ByteLimit(size-1))
    assert short.error == FrameError.LimitExceeded and calls() == 0
    if contextual:
      assert encodeContextJournalFrame(RepositoryGeneration(1), source, context, ByteLimit(2),
        codec, ByteLimit(size)).error == FrameError.LimitExceeded
      assert calls() == 0 # Context extent refusal must not reach raw integrity or frame checksum work.
    let refused = if contextual:
        encodeContextJournalFrame(RepositoryGeneration(1), source, context, ByteLimit(3), codec,
            ByteLimit(size))
      else: encodeJournalFrame(RepositoryGeneration(1), source, codec, ByteLimit(size))
    assert refused.error == FrameError.InvalidRecords and refused.recordError ==
        RecordError.BackendFailure
    assert calls() == 1 # Strict mutable records fail at their first actual local integrity operation.
  reset(0)
  var duplicate = source
  let repeated = duplicate.records[0]
  duplicate.records.add(repeated)
  reset(1)
  assert encodeFramedTrieExport(duplicate, codec, 16, 32, limits.bytes).error ==
      RecordError.DuplicateNode
  assert calls() == 0
  var mutated = source
  for index in 0..<mutated.records.len:
    if mutated.records[index].kind == TrieRecordKind.Leaf:
      mutated.records[index].payload[0] = mutated.records[index].payload[0] xor 255
  reset(0)
  assert encodeFramedTrieExport(mutated, codec, 16, 32, limits.bytes).error ==
      RecordError.HashMismatch
  assert encodeTrieExport(source, codec).value == expected
  reset(1)
  assert encodeJournalFrame(RepositoryGeneration(1), default(TrieExport), codec,
    limits.bytes).error == FrameError.BackendFailure
  assert calls() == 1 # Empty raw bodies still require the outer checksum; reservation authority cannot supply it.
  reset(0)

let limits = snapshotPolicy()
let source = batch(snapshotFixture(2, 33))
for warmup in 0..<10: exercise(source, limits)
let before = getOccupiedMem()
for iteration in 0..<1000: exercise(source, limits)
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_journal_framing", 1000, before, after)
echo "PASS storage journal framing: strict reserved bodies, exact domains, replay, typed refusals and ARC"
