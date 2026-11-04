# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_availability_merkle_arc_release"}

## Independent GP hashlib witnesses, exact NP node tags and hostile trace boundaries validate availability Merkle computation.
import std/[assertions, rawthreads, syncio]
import ../../../src/jamnp-s/availability_merkle
import ../../../src/codec/bounded
import ../../../src/crypto/primitives
import ../../support/arc_evidence
proc root(hex: string): Blake2bHash =
  ## Frozen independent Python hashlib.blake2b(digest_size=32) witnesses use one exact lowercase hexadecimal representation.
  assert hex.len == 64
  var bytes = default(array[32, byte])
  for index, character in hex:
    let nibble = if character in {'0'..'9'}: ord(character)-ord('0') else: ord(character)-ord('a')+10
    assert nibble >= 0 and nibble < 16
    bytes[index div 2] = (bytes[index div 2] shl 4) or byte(nibble)
  Blake2bHash(bytes)
proc leaves(width, count: int): seq[byte] =
  ## Distinct raw rows permit independent shape/coordinate checks without calling production encoders.
  result = newSeq[byte](width*count)
  for row in 0..<count:
    for position in 0..<width: result[row*width+position] = byte(row mod 251+1)
proc limits(): AvailabilityMerkleLimits =
  ## Maximum geometry still has a finite independent payload/hash/call policy.
  AvailabilityMerkleLimits(bytes: ByteLimit(6000000), hashBytes: ByteLimit(16000000),
      hashes: ElementLimit(10000))
proc releaseCycle(flat: seq[byte]) =
  ## Newly retained proof bytes and independent caller copies retire completely on every cycle.
  let encoded = prepareAvailabilityTrace(flat, 64, 6, 0, 1, limits())
  assert encoded.error == AvailabilityMerkleError.None
  let trace = encoded.value
  var copy = trace.bytes
  assert copy.len > 0
  let original = copy[0]
  copy[0] = copy[0] xor 1
  assert trace.bytes[0] == original
type StackContext = object
  ## The caller leaves this entire graph untouched from create through join.
  flat: seq[byte]
  passed: bool
proc boundedStack(context: pointer) =
  ## Maximum-width deepest traces must also fit the smaller management-worker stack.
  let selected = cast[ptr StackContext](context)
  let whole = availabilityMerkleRoot(selected.flat, AvailabilityLeafBytes,
    AvailabilityTreeLeaves, limits())
  assert whole.error == AvailabilityMerkleError.None
  for index in [0, AvailabilityTreeLeaves-1]:
    # Both edge paths cover the unequal split while temporaries remain thread-local.
    let trace = prepareAvailabilityTrace(selected.flat, AvailabilityLeafBytes,
      AvailabilityTreeLeaves, index, 2, limits())
    assert trace.error == AvailabilityMerkleError.None
    assert array[32, byte](trace.value.root) == array[32, byte](whole.value)
  selected.passed = true
proc main() {.raises.} =
  ## Hash/node/singleton distinctions are checked against frozen independent roots, not only production round trips.
  let flat = leaves(64, 3)
  let expected = root("ad9594b509d9b384cd514ecb8612d78c8391326ce2fa4f79f2c80733d7d87851")
  let first = prepareAvailabilityTrace(flat, 64, 3, 0, 1, limits())
  assert first.error == AvailabilityMerkleError.None and first.value.valid
  assert array[32, byte](first.value.root) == array[32, byte](expected)
  var literal = @[1'u8]
  for position in 0..<64: literal.add(3)
  literal.add(1)
  for position in 0..<64: literal.add(2)
  assert first.value.bytes == literal, "GP root-first T carries raw singleton pairs, without hashing each leaf"
  let leaf = leaves(64, 1)
  assert verifyAvailabilityTrace(expected, leaf, literal, 64, 3, 0, 1, limits()).error ==
      AvailabilityMerkleError.None
  let whole = availabilityMerkleRoot(flat, 64, 3, limits())
  assert whole.error == AvailabilityMerkleError.None and array[32, byte](whole.value) == array[32,
      byte](expected)
  for index in 0..<3:
    # Every branch of the odd tree produces the same independently known root.
    let selected = prepareAvailabilityTrace(flat, 64, 3, index, 1, limits())
    assert selected.error == AvailabilityMerkleError.None
    assert array[32, byte](selected.value.root) == array[32, byte](expected)
    assert verifyAvailabilityTrace(expected, flat.toOpenArray(index*64, index*64+63),
      selected.value.bytes, 64, 3, index, 1, limits()).error == AvailabilityMerkleError.None
  let small = leaves(12, 5)
  let segmentRoot = root("7d631018bc42a734c00e3279c6ac8445d36ebab8d0e464ca16861b0d1e2d7b44")
  let segment = prepareAvailabilityTrace(small, 12, 5, 4, 2, limits())
  assert segment.error == AvailabilityMerkleError.None
  assert array[32, byte](segment.value.root) == array[32, byte](segmentRoot)
  var segmentLiteral = @[0'u8]
  for octet in array[32, byte](root("8398e4ae5d1b800b48f65385b14c61a040fe12949fbba8b54f47f63704dd0860")):
    segmentLiteral.add(octet)
  segmentLiteral.add(2)
  for position in 0..<12: segmentLiteral.add(4)
  assert segment.value.bytes == segmentLiteral, "segment siblings use discriminator2 and geometry-derived raw width"
  let singleton = prepareAvailabilityTrace(leaf, 64, 1, 0, 1, limits())
  assert singleton.error == AvailabilityMerkleError.None and singleton.value.valid and
      singleton.value.bytes.len == 0
  assert array[32, byte](singleton.value.root) == array[32, byte](blake2b256(leaf).value)
  assert verifyAvailabilityTrace(singleton.value.root, leaf, [], 64, 1, 0, 1, limits()).error ==
      AvailabilityMerkleError.None
  assert not default(AvailabilityTrace).valid
  let empty = availabilityMerkleRoot([], 64, 0, default(AvailabilityMerkleLimits))
  assert empty.error == AvailabilityMerkleError.None and array[32, byte](empty.value) == default(
      array[32, byte])
  for extent in 0..<literal.len:
    # Every truncated tag/payload position fails before a root can authenticate any prefix.
    let prefix = if extent == 0: newSeq[byte](0) else: literal[0..<extent]
    assert verifyAvailabilityTrace(expected, leaf, prefix, 64, 3, 0, 1, limits()).error ==
        AvailabilityMerkleError.InvalidProof
  var changed = literal
  changed.add(0)
  assert verifyAvailabilityTrace(expected, leaf, changed, 64, 3, 0, 1, limits()).error ==
      AvailabilityMerkleError.InvalidProof
  changed = literal
  changed[0] = 0
  assert verifyAvailabilityTrace(expected, leaf, changed, 64, 3, 0, 1, limits()).error ==
      AvailabilityMerkleError.InvalidProof
  changed = literal
  changed[1] = changed[1] xor 1
  assert verifyAvailabilityTrace(expected, leaf, changed, 64, 3, 0, 1, limits()).error ==
      AvailabilityMerkleError.RootMismatch
  assert verifyAvailabilityTrace(expected, leaves(64, 2).toOpenArray(64, 127), literal,
    64, 3, 0, 1, limits()).error == AvailabilityMerkleError.RootMismatch
  assert verifyAvailabilityTrace(expected, leaf, literal, 64, 3, 1, 1, limits()).error !=
      AvailabilityMerkleError.None
  assert prepareAvailabilityTrace(flat, 0, 3, 0, 1, limits()).error ==
      AvailabilityMerkleError.InvalidInput
  assert prepareAvailabilityTrace([], high(int), 2, 0, 1, limits()).error ==
      AvailabilityMerkleError.InvalidInput
  assert prepareAvailabilityTrace([], 64, AvailabilityTreeLeaves+1, 0, 1, limits()).error ==
      AvailabilityMerkleError.InvalidInput
  for index in [-1, 3, high(int)]:
    assert prepareAvailabilityTrace(flat, 64, 3, index, 1, limits()).error ==
        AvailabilityMerkleError.InvalidIndex
  assert prepareAvailabilityTrace(flat, 64, 3, 0, 0, limits()).error ==
      AvailabilityMerkleError.InvalidInput
  assert prepareAvailabilityTrace(small, 12, 5, 0, 1, limits()).error ==
      AvailabilityMerkleError.InvalidInput
  assert prepareAvailabilityTrace(flat.toOpenArray(0, flat.len-2), 64, 3, 0, 1, limits()).error ==
      AvailabilityMerkleError.InvalidInput
  var cap = limits()
  cap.bytes = ByteLimit(321)
  assert prepareAvailabilityTrace(flat, 64, 3, 0, 1, cap).error ==
      AvailabilityMerkleError.LimitExceeded
  cap = limits()
  cap.hashes = ElementLimit(1)
  assert prepareAvailabilityTrace(flat, 64, 3, 0, 1, cap).error ==
      AvailabilityMerkleError.LimitExceeded
  cap = limits()
  cap.hashBytes = ByteLimit(231)
  assert prepareAvailabilityTrace(flat, 64, 3, 0, 1, cap).error ==
      AvailabilityMerkleError.LimitExceeded
  cap.hashBytes = ByteLimit(232)
  cap.hashes = ElementLimit(2)
  assert prepareAvailabilityTrace(flat, 64, 3, 0, 1, cap).error == AvailabilityMerkleError.None
  let large = leaves(AvailabilityLeafBytes, AvailabilityTreeLeaves)
  let largeRoot = availabilityMerkleRoot(large, AvailabilityLeafBytes, AvailabilityTreeLeaves,
      limits())
  assert largeRoot.error == AvailabilityMerkleError.None
  for index in [0, AvailabilityTreeLeaves-1]:
    # Maximum width/count exercise both deepest and shallower branches without unbounded recursion or stack buffers.
    let selected = prepareAvailabilityTrace(large, AvailabilityLeafBytes, AvailabilityTreeLeaves,
        index, 2, limits())
    assert selected.error == AvailabilityMerkleError.None
    assert array[32, byte](selected.value.root) == array[32, byte](largeRoot.value)
  var context = StackContext(flat: large, passed: false)
  var thread = default(RawThread)
  thread.create(boundedStack, addr context, stackSize = 524288)
  thread.join() # Every shared ARC alias remains untouched until the exact thread has retired.
  assert context.passed
  let six = leaves(64, 6)
  releaseCycle(six)
  let before = getOccupiedMem()
  for iteration in 0..<1000: releaseCycle(six)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_availability_merkle", 1000, before, after)
  echo "JAMNP-S availability Merkle traces passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit 2 # Failure to create the bounded thread cannot substitute for a completed stack witness.
