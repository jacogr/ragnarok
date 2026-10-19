# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Focused lifetime, immutable-copy, atomicity, alias and runtime result-guard tests.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

## Verification: {"arc": "bits_arc_release"}

import ../../support/arc_evidence
import std/[assertions, syncio]
import ../../../src/codec/bitstrings

# Only a selected complete success can supply native metadata, owners or written extents.
proc checked[T](parsed: BitResult[T]): T =
  assert parsed.error == BitError.None
  parsed.value

let limit = BitLimit(1024)
var input = @[9'u8, 0x81, 1, 0x99]
var owner = checked(decodeBits(input, limit)).owner
var retained = owner
owner = OwnedBits()
# All retained bits must outlive and ignore the caller's original mutable input.
for i in 0..<input.len: input[i] = 0
let info = checked(bitsInfo(retained))
assert uint64(info.count) == 9 and info.packedBytes == 2
assert checked(bitAt(retained, 0)) and checked(bitAt(retained, 7)) and checked(bitAt(retained, 8))
assert not checked(bitAt(retained, 1))
assert bitAt(retained, -1).error == BitError.InvalidIndex
assert bitAt(retained, 9).error == BitError.InvalidIndex
var output: array[16, byte] = default(array[16, byte])
# Fixed and variable framing preserve all destination suffix capacity.
for i in 0..<output.len: output[i] = 0xA5
assert checked(encodeOwnedBits(retained, limit, output)) == 3
assert output[0] == 9 and output[1] == 0x81 and output[2] == 1
assert output[3] == 0xA5
output[1] = 0
# Mutating extracted bytes can never mutate the private immutable snapshot.
assert checked(bitAt(retained, 0))
assert checked(encodeOwnedFixedBits(retained, BitCount(9), limit, output)) == 2
assert output[0] == 0x81 and output[1] == 1
# A stricter caller policy must be applied again to retained snapshots before any output writes.
for i in 0..<output.len: output[i] = 0xA5
assert encodeOwnedBits(retained, BitLimit(8), output).error == BitError.LimitExceeded
assert encodeOwnedFixedBits(retained, BitCount(8), limit, output).error == BitError.InvalidCount
var empty: seq[byte] = default(seq[byte])
assert encodeOwnedBits(retained, limit, empty).error == BitError.OutputTooSmall
# All failed source-policy and capacity checks leave the complete output unchanged.
for octet in output: assert octet == 0xA5
var missing: OwnedBits = default(OwnedBits)
assert bitsInfo(missing).error == BitError.InvalidOwner
assert bitAt(missing, 0).error == BitError.InvalidOwner
assert encodeOwnedBits(missing, limit, output).error == BitError.InvalidOwner
assert encodeOwnedFixedBits(missing, BitCount(0), limit, output).error == BitError.InvalidOwner
let zero = checked(decodeFixedBits(empty, BitCount(0), BitLimit(0))).owner
assert uint64(checked(bitsInfo(zero)).count) == 0
assert checked(encodeOwnedFixedBits(zero, BitCount(0), BitLimit(0), empty)) == 0
assert checked(encodeOwnedBits(zero, BitLimit(0), output)) == 1 and output[0] == 0
# A copied owner is independent of subsequent destruction of other handles.
retained = OwnedBits()
assert bitAt(zero, 0).error == BitError.InvalidIndex
# Borrowed bool storage cannot overlap any part of the written frame, even its earlier count prefix.
var backing: array[32, bool] = default(array[32, bool])
let storage = cast[ptr array[sizeof(backing), byte]](addr backing[0])
assert sizeof(bool) == 1
let aliasResult = encodeBits(backing.toOpenArray(1, 9), limit, storage[].toOpenArray(0, 2))
assert aliasResult.error == BitError.AliasedBuffers
# Failed alias preflight must leave the bool representations valid and unchanged.
for value in backing: assert not value
assert encodeFixedBits(backing.toOpenArray(1, 9), BitCount(9), limit,
  storage[].toOpenArray(0, 1)).error == BitError.AliasedBuffers
# Source cardinality and policy precede output capacity, even for an empty destination.
assert encodeFixedBits(backing, BitCount(31), BitLimit(0), empty).error == BitError.InvalidCount
assert encodeBits(backing, BitLimit(0), empty).error == BitError.LimitExceeded
# Successful snapshotting permits the original caller input to become an output destination later.
input = @[9'u8, 0x81, 1]
let independent = checked(decodeBits(input, limit)).owner
assert checked(encodeOwnedBits(independent, limit, input)) == 3
# A returned handle retains bytes from a callee-local buffer after that source leaves scope.
proc escapedBits(): OwnedBits =
  var bytes = @[9'u8, 0x81, 1]
  result = checked(decodeBits(bytes, BitLimit(9))).owner
  # Mutating a local caller buffer cannot change the snapshot that escapes this scope.
  for i in 0..<bytes.len: bytes[i] = 0

let escaped = escapedBits()
assert checked(bitAt(escaped, 0)) and checked(bitAt(escaped, 8))

# Scoped snapshots must retain their original logical bits after both source and newer handle replacement.
proc releaseCycle() =
  var source = @[9'u8, 0x81, 1, 0x99]
  var current = checked(decodeBits(source, BitLimit(9))).owner
  let old = current
  current = checked(decodeFixedBits([byte(0), 0], BitCount(9), BitLimit(9))).owner
  # Replacing the same-sized handle cannot rebind a retained old snapshot to the new bytes.
  assert not checked(bitAt(current, 0))
  source = @[]
  current = default(OwnedBits)
  assert checked(bitAt(old, 0)) and checked(bitAt(old, 7)) and checked(bitAt(old, 8))
  var metadata = checked(bitsInfo(old))
  metadata.count = BitCount(0)
  assert uint64(checked(bitsInfo(old)).count) == 9
  var bytes = newSeq[byte](4)
  assert checked(encodeOwnedBits(old, BitLimit(9), bytes)) == 3
  # Replacing extracted output cannot mutate the original retained logical bits.
  for i in 0..<bytes.len: bytes[i] = 0
  assert checked(bitAt(old, 8))
  assert checked(encodeOwnedFixedBits(old, BitCount(9), BitLimit(9), bytes)) == 2
  assert bytes[0] == 0x81 and bytes[1] == 1
  # A captured fixed empty string remains a genuine owner and can be reframed as variable empty.
  let empty = checked(decodeFixedBits([], BitCount(0), BitLimit(0))).owner
  assert checked(encodeOwnedBits(empty, BitLimit(0), bytes)) == 1 and bytes[0] == 0

# Warm public allocator paths before observing this isolated retain/replace/drop workload.
for i in 0..<100: releaseCycle()
let beforeRelease = getOccupiedMem()
# Last-owner destruction must return live occupancy to baseline after each complete scope.
for i in 0..<1000: releaseCycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve numeric observations outside the platform-independent success marker.
recordArcRelease("bits", 1000, beforeRelease, afterRelease)
echo "BITS_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony bits: retained ownership, atomicity, aliases and copied metadata passed"
