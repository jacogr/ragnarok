# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent literal E4/group construction and GP segment verification support component and actual TLS serving witnesses.
import std/assertions
import ../../src/jamnp-s/read_stream
import ../../src/state/availability/specifier
import "../../src/state/import/justification" as import_proof
import ../../src/codec/[bounded, natural]
from ../../src/codec/work/package import ImportIndex
from ../../src/codec/work/report import SegmentRoot
from ../../src/pvm/host/fetch import FetchSegment
proc segmentGroup*(kind: ReadKind, root: array[32, byte], shard: uint16, rows: openArray[
    uint16]): seq[byte] =
  ## Construct exact request order; canonical naturals have independent codec witnesses elsewhere.
  result = @[]
  for octet in root: result.add(octet)
  if kind != ReadKind.Segments:
    result.add(byte(shard and 255))
    result.add(byte(shard shr 8))
  let count = encode(JamNatural(uint64(rows.len)))
  for index in 0..<count.len: result.add(count.bytes[index])
  for row in rows:
    result.add(byte(row and 255))
    result.add(byte(row shr 8))
proc segmentMessages*(wire: seq[byte]): seq[seq[byte]] =
  ## Independent E4 parsing requires exact complete messages and no suffix.
  result = @[]
  var offset = 0
  while offset < wire.len:
    assert wire.len-offset >= 4
    var length = 0'u64
    for index in 0..<4: length = length or (uint64(wire[offset+index]) shl (8*index))
    offset += 4
    assert length <= uint64(wire.len-offset)
    var payload = newSeq[byte](int(length))
    for index in 0..<payload.len: payload[index] = wire[offset+index]
    offset += payload.len
    result.add(payload)
proc verifyOriginalSegments*(expected: AvailabilitySpecifier, rows: openArray[uint16], parts: seq[
    seq[byte]]) =
  ## Every returned original segment is checked against an independent selected segment root using the GP verifier.
  assert parts.len == 2 and parts[0].len == rows.len*4104
  var offset = 0
  for ordinal, row in rows:
    let count = decode(parts[1].toOpenArray(offset, parts[1].len-1))
    assert count.ok and uint64(count.value) <= 12
    offset += count.consumed
    var path = newSeq[SegmentRoot](int(uint64(count.value)))
    for index in 0..<path.len:
      for octet in 0..<32: path[index].bytes[octet] = parts[1][offset+index*32+octet]
    offset += path.len*32
    var leaf = default(array[4104, byte])
    for octet in 0..<4104: leaf[octet] = parts[0][ordinal*4104+octet]
    assert verifyImportSegment(expected.segmentRoot, ImportIndex(row), FetchSegment(leaf), path,
      ImportJustificationLimits(siblings: ElementLimit(12), payloadBytes: ByteLimit(4500),
          hashBytes: ByteLimit(5000))).error == ImportJustificationError.None
  assert offset == parts[1].len
