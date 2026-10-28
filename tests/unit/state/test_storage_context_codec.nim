# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Context and node changes share one exact frame; legacy and contextual schemas never cross-decode.
import std/assertions
import std/syncio
import ../../../src/storage/journal_codec as storage_journal_codec
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
proc run() =
  ## Frozen Python struct/hashlib checksum independently witnesses generation, context and record binding.
  let limits = RecordLimits(encoded: ByteLimit(105))
  let wire = encodeContextJournalFrame(RepositoryGeneration(9), default(TrieExport),
    [1'u8, 2, 3], ByteLimit(3), limits, ByteLimit(164)).value
  let checksum = [0'u8, 233, 227, 193, 7, 150, 185, 249, 4, 54, 122, 6, 105, 220, 179, 73, 51, 105,
      217, 31, 251, 225, 17, 87, 89, 223, 33, 153, 127, 5, 33, 207]
  assert wire.len == 164 and wire[0] == 116 and wire[8] == 9 and wire[16] == 3
  for index in 0..<32: assert wire[132+index] == checksum[index]
  let decoded = decodeContextJournalFrame(wire, ByteLimit(3), limits, ByteLimit(164)).value
  assert uint64(decoded.generation) == 9 and decoded.context == @[1'u8, 2, 3]
  assert decoded.batch.records.len == 0
  for stop in 0..<wire.len:
    # Borrow the same truncated extent without allocating a sequence slice.
    let prefix = decodeContextJournalFrame(wire.toOpenArray(0, stop-1), ByteLimit(3), limits,
        ByteLimit(164))
    assert prefix.error != FrameError.None
  for index in 0..<wire.len:
    var changed = wire
    changed[index] = changed[index] xor 1
    assert decodeContextJournalFrame(changed, ByteLimit(3), limits, ByteLimit(164)).error !=
        FrameError.None
  assert encodeContextJournalFrame(RepositoryGeneration(9), default(TrieExport),
    [1'u8, 2, 3], ByteLimit(2), limits, ByteLimit(164)).error == FrameError.LimitExceeded
  assert encodeContextJournalFrame(RepositoryGeneration(9), default(TrieExport),
    [1'u8, 2, 3], ByteLimit(3), limits, ByteLimit(163)).error == FrameError.LimitExceeded
  assert decodeContextJournalFrame(wire, ByteLimit(2), limits, ByteLimit(164)).error ==
      FrameError.LimitExceeded
  var huge = wire
  for index in 16..<24: huge[index] = 255
  assert decodeContextJournalFrame(huge, ByteLimit(high(uint64)), limits, ByteLimit(164)).error ==
      FrameError.InvalidFormat
  let legacy = encodeJournalFrame(RepositoryGeneration(9), default(TrieExport), limits, ByteLimit(153)).value
  assert decodeContextJournalFrame(legacy, ByteLimit(1024), limits, ByteLimit(164)).error !=
      FrameError.None
  assert decodeJournalFrame(wire, limits, ByteLimit(164)).error != FrameError.None
  let chain = default(StorageChainId)
  let contextual = encodeDatabaseIdentity(fullStateIdentity(chain, StorageSchema.FullStateV1),
      ByteLimit(StorageIdentityBytes)).value
  assert decodeDatabaseIdentity(contextual, chain, ByteLimit(StorageIdentityBytes)).error ==
      IdentityError.InvalidFormat
  assert decodeDatabaseIdentity(contextual, chain, ByteLimit(StorageIdentityBytes),
      StorageSchema.FullStateV1).error == IdentityError.None
  let ordinary = encodeDatabaseIdentity(fullStateIdentity(chain), ByteLimit(
      StorageIdentityBytes)).value
  assert decodeDatabaseIdentity(ordinary, chain, ByteLimit(StorageIdentityBytes),
      StorageSchema.FullStateV1).error == IdentityError.InvalidFormat
run()
echo "PASS storage context codec: exact independent checksum, bounded context and distinct physical schemas"
