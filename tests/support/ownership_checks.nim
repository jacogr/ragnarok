# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared adapter assertions: owned snapshots must match every successful borrowed conformance decode.
import std/[assertions, syncio]
import ../../src/codec/[bounded, composite, work_digest, owned]

# Compare snapshot bytes to the independently checked canonical prefix and each validated payload.
proc verifySnapshot(frame: OwnedFrame, wire: openArray[byte], consumed: int,
                    spans: openArray[BlobSpan]) =
  let info = ownedInfo(frame)
  assert info.error == OwnershipError.None
  assert info.value.consumed == consumed and info.value.blobCount == spans.len
  var encoded = newSeq[byte](consumed)
  let written = encodeOwned(frame, encoded)
  assert written.error == OwnershipError.None and written.value == consumed
  # Compare every consumed byte; unrelated trailing frames must not enter the snapshot.
  for index, value in encoded: assert value == wire[index]
  # Copy each payload through its owner; no second buffer is an input to extraction.
  for index, span in spans:
    let length = ownedBlobLength(frame, index)
    assert length.error == OwnershipError.None and length.value == span.length
    var payload = newSeq[byte](length.value)
    let copied = copyOwnedBlob(frame, index, payload)
    assert copied.error == OwnershipError.None and copied.value == span.length
    # Compare the complete payload against its validated wire location.
    for i, value in payload: assert value == wire[span.offset + i]

# Check the owned byte-string path against successful shared vectors and random requests.
proc checkOwnedBytes*(wire: openArray[byte], limit: ByteLimit, expected: BlobResult) =
  let parsed = decodeOwnedBytes(wire, limit)
  assert parsed.error == OwnershipError.None
  verifySnapshot(parsed.value, wire, expected.consumed,
      [BlobSpan(offset: expected.offset, length: expected.length)])

# Check both optional alternatives, including empty present blobs and payload-free absence.
proc checkOwnedOptional*(wire: openArray[byte], limit: ByteLimit, expected: OptionalResult) =
  let parsed = decodeOwnedOptional(wire, limit)
  assert parsed.error == OwnershipError.None
  let info = ownedOptionalInfo(parsed.value)
  assert info.error == OwnershipError.None and info.value.present == expected.value.present
  # Present optionals have one payload even when it is empty.
  if expected.value.present:
    assert info.value.length == expected.value.blob.length
    verifySnapshot(parsed.value, wire, expected.consumed, [expected.value.blob])
  else:
    # Absence has no copyable payload or length metadata.
    verifySnapshot(parsed.value, wire, expected.consumed, [])

# Check successful work blobs and each payload-free work error against conformance results.
proc checkOwnedWork*(wire: openArray[byte], limit: ByteLimit, expected: WorkResult) =
  let parsed = decodeOwnedWork(wire, limit)
  assert parsed.error == OwnershipError.None
  let info = ownedWorkInfo(parsed.value)
  assert info.error == OwnershipError.None and info.value.kind == expected.value.kind
  # Success retains exactly one validated payload.
  if expected.value.kind == WorkKind.Success:
    assert info.value.length == expected.value.blob.length
    verifySnapshot(parsed.value, wire, expected.consumed, [expected.value.blob])
  else:
    # Work errors remain successful frame values without payloads.
    verifySnapshot(parsed.value, wire, expected.consumed, [])

# Check all preimage service IDs and nested payloads from the official/full conformance requests.
proc checkOwnedPreimages*(wire: openArray[byte], limits: PreimageLimits,
                         expected: PreimageResult, records: openArray[Preimage]) =
  let parsed = decodeOwnedPreimages(wire, limits)
  assert parsed.error == OwnershipError.None
  var spans = newSeq[BlobSpan](expected.count)
  # Each tuple must preserve its own nominal service and bound payload.
  for i in 0..<expected.count:
    spans[i] = records[i].blob
    let service = ownedService(parsed.value, i)
    assert service.error == OwnershipError.None and uint32(service.value) == uint32(records[i].service)
  verifySnapshot(parsed.value, wire, expected.consumed, spans)

# Check every digest fixed field/metric and its nested work alternative against full official vectors.
proc checkOwnedDigest*(wire: openArray[byte], limit: ByteLimit, expected: DigestResult) =
  let parsed = decodeOwnedDigest(wire, limit)
  assert parsed.error == OwnershipError.None
  let info = ownedDigestInfo(parsed.value)
  assert info.error == OwnershipError.None
  let actual = info.value
  let value = expected.value
  assert uint32(actual.service) == uint32(value.service)
  assert array[32, byte](actual.codeHash) == array[32, byte](value.codeHash)
  assert array[32, byte](actual.payloadHash) == array[32, byte](value.payloadHash)
  assert uint64(actual.accumulateGas) == uint64(value.accumulateGas)
  assert uint64(actual.refine.gasUsed) == uint64(value.refine.gasUsed)
  assert uint64(actual.refine.imports) == uint64(value.refine.imports)
  assert uint64(actual.refine.extrinsicCount) == uint64(value.refine.extrinsicCount)
  assert uint64(actual.refine.extrinsicSize) == uint64(value.refine.extrinsicSize)
  assert uint64(actual.refine.exports) == uint64(value.refine.exports)
  assert actual.output.kind == value.output.kind
  # Only successful output contains a payload length and copyable blob.
  if value.output.kind == WorkKind.Success:
    assert actual.output.length == value.output.blob.length
    verifySnapshot(parsed.value, wire, expected.consumed, [value.output.blob])
  else:
    # Payload-free work errors still round-trip the whole digest.
    verifySnapshot(parsed.value, wire, expected.consumed, [])
