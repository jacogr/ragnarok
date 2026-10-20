# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete journal framing rejects truncation, tampering, huge lengths and ambiguous consumption.
import std/[assertions, syncio]
import ../../../src/storage/[journal_codec, record_codec, node_records, node_repository]
import ../../../src/codec/bounded
proc main() =
  ## Independent exact bytes protect length/generation endianness and checksum coverage.
  let limits = RecordLimits(encoded: ByteLimit(105))
  let wire = encodeJournalFrame(RepositoryGeneration(1), default(TrieExport), limits, ByteLimit(153)).value
  # Frozen Python struct/hashlib witness covers the entire local frame independently.
  let expected = [105'u8, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
    82, 65, 71, 78, 65, 82, 79, 75, 45, 84, 82, 73, 69, 45, 86, 49,
    10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 31, 211, 109, 138, 97, 115, 221,
    110, 174, 35, 70, 252, 177, 152, 240, 163, 160, 184, 199, 87, 111, 44, 77,
    243, 44, 255, 216, 216, 150, 132, 7, 84]
  assert wire == @expected
  for stop in 0..<wire.len:
    assert decodeJournalFrame(wire[0..<stop], limits, ByteLimit(153)).error != FrameError.None
  for index in 0..<wire.len:
    var corrupt = wire
    corrupt[index] = corrupt[index] xor 1
    assert decodeJournalFrame(corrupt, limits, ByteLimit(153)).error != FrameError.None
  var wide = wire
  for i in 0..<8: wide[i] = 255
  assert journalFrameExtent(wide, ByteLimit(high(uint64))).error == FrameError.LimitExceeded
  let frame = decodeJournalFrame(wire, limits, ByteLimit(153)).value
  assert uint64(frame.generation) == 1 and frame.batch.records.len == 0
  assert encodeJournalFrame(RepositoryGeneration(0), default(TrieExport), limits, ByteLimit(
      153)).error == FrameError.InvalidFormat
  assert encodeJournalFrame(RepositoryGeneration(1), default(TrieExport), limits, ByteLimit(
      152)).error == FrameError.LimitExceeded
  var joined = wire
  for octet in wire: joined.add(octet) # Append an independent second frame through the pinned scalar seq API.
  assert journalFrameExtent(joined, ByteLimit(153)).value == wire.len
  assert decodeJournalFrame(joined, limits, ByteLimit(306)).error == FrameError.InvalidFormat
main()
echo "PASS storage journal codec: exact generation frames, independent checksum, truncation and bounds"
