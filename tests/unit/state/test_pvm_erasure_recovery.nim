# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_erasure_recovery_arc_release"}

## Frozen independent Lagrange codewords validate arbitrary-point chunk recovery without using the production encoder.
import std/[assertions, syncio]
import ../../../src/state/erasure/[words, layout]
import ../../../src/codec/bounded
import ../../../src/codec/work/report
import ../../support/[pvm_erasure_vectors, arc_evidence]
proc generous(): ErasureWordLimits =
  ## Explicit bounds cover full segment recovery and maximum validator geometry.
  ErasureWordLimits(bytes: ByteLimit(100000), products: FieldProductLimit(10000000))
proc originalCount(validators: int): int =
  ## Increasing divisor enumeration independently fixes the reconstruction threshold.
  result = 1
  for candidate in 1..(validators div 3+1):
    if 2052 mod candidate == 0: result = candidate
proc frozen(validators: uint16, code: openArray[uint16], width, mode: int, padded = false) =
  ## XOR with a column constant is a known constant-polynomial addition to each independent frozen codeword.
  let policy = generous()
  let original = originalCount(int(validators))
  var indices = newSeq[ErasureShardIndex](original)
  for row in 0..<original:
    case mode
    of 0: indices[row] = ErasureShardIndex(uint64(int(validators)-1-row)) # All parity, reversed.
    of 1: indices[row] = ErasureShardIndex(uint64(original-1-row)) # Permuted complete systematic input.
    else: indices[row] = ErasureShardIndex(uint64(if row == 0: 0 else: int(validators)-row)) # A mixed subset.
  var input = newSeq[byte](original*width)
  var expected = newSeq[byte](original*width)
  for column in 0..<(width div 2):
    let mask = if padded and column == width div 2-1: code[original-1] and 65280'u16
      else: uint16((column*4660) and 65535)
    for row in 0..<original:
      let known = code[int(uint64(indices[row]))] xor mask
      input[row*width+column*2] = byte(known and 255)
      input[row*width+column*2+1] = byte(known shr 8)
      let wanted = code[row] xor mask
      expected[row*width+column*2] = byte(wanted and 255)
      expected[row*width+column*2+1] = byte(wanted shr 8)
  let length = original*width-(if padded: 1 else: 0)
  let recovered = recoverErasureChunks(input, indices, BundleLength(uint32(length)),
    ErasureShards(validators), policy)
  assert recovered.error == ErasureWordError.None, "frozen erasure recovery"
  var output = recovered.value.recoveredBytes.value
  assert output.len == length
  for index in 0..<length: assert output[index] == expected[index], "independent original byte"
  let info = recovered.value.recoveryInfo.value
  assert info.originalShards == uint64(original) and info.retainedBytes == uint64(original*width)
  assert (info.products == 0) == (mode == 1)
  var exact = ErasureWordLimits(bytes: ByteLimit(info.retainedBytes+info.workspaceBytes),
    products: FieldProductLimit(info.products))
  assert recoverErasureChunks(input, indices, BundleLength(uint32(length)), ErasureShards(
      validators), exact).error == ErasureWordError.None
  exact.bytes = ByteLimit(uint64(exact.bytes)-1)
  assert recoverErasureChunks(input, indices, BundleLength(uint32(length)), ErasureShards(
      validators), exact).error == ErasureWordError.LimitExceeded
  if info.products > 0:
    exact.bytes = ByteLimit(uint64(exact.bytes)+1)
    exact.products = FieldProductLimit(info.products-1)
    assert recoverErasureChunks(input, indices, BundleLength(uint32(length)), ErasureShards(
        validators), exact).error == ErasureWordError.LimitExceeded
  output[0] = output[0] xor 1
  input[0] = input[0] xor 1
  assert recovered.value.recoveredBytes.value[0] == expected[0], "independent immutable output"
proc cycle() =
  ## Complete parity recovery and its copied output retire before every ARC observation.
  let policy = generous()
  let indices = [ErasureShardIndex(5), ErasureShardIndex(4), ErasureShardIndex(3)]
  var input: seq[byte] = @[]
  for index in [5, 4, 3]:
    input.add(byte(Words6[index] and 255))
    input.add(byte(Words6[index] shr 8))
  let result = recoverErasureChunks(input, indices, BundleLength(6), ErasureShards(6), policy)
  assert result.error == ErasureWordError.None
  assert result.value.recoveredBytes.value.len == 6
  let systematic = [ErasureShardIndex(0), ErasureShardIndex(1), ErasureShardIndex(2)]
  assert recoverErasureChunks(@[0'u8, 0, 0, 0, 0, 1], systematic, BundleLength(5),
    ErasureShards(6), policy).error == ErasureWordError.InvalidPadding
proc main() =
  ## Full Cantor-coordinate populations and segment/bundle layouts are checked before hostile admission boundaries.
  let policy = generous()
  for mode in 0..2:
    frozen(6, Words6, 2, mode)
    frozen(9, Words9, 6, mode)
    frozen(51, Words51, 2, mode)
    frozen(1023, Words1023, 2, mode)
  frozen(6, Words6, 1368, 0)
  frozen(1023, Words1023, 12, 0)
  frozen(6, Words6, 6, 2, padded = true)
  let indices = [ErasureShardIndex(0), ErasureShardIndex(1), ErasureShardIndex(2)]
  let input = @[0'u8, 1, 2, 3, 4, 0]
  assert recoverErasureChunks(input, indices, BundleLength(5), ErasureShards(6),
      policy).error == ErasureWordError.None
  var invalid = input
  invalid[5] = 1
  assert recoverErasureChunks(invalid, indices, BundleLength(5), ErasureShards(6),
      policy).error == ErasureWordError.InvalidPadding
  for length in [0'u32, 13904951'u32, high(uint32)]:
    assert recoverErasureChunks([], indices, BundleLength(length), ErasureShards(6),
        policy).error == ErasureWordError.InvalidLength
  for shards in [0'u16, 3, 7, 1022, 1024, high(uint16)]:
    assert recoverErasureChunks(input, indices, BundleLength(6), ErasureShards(shards),
        policy).error == ErasureWordError.InvalidShards
  let duplicate = [ErasureShardIndex(0), ErasureShardIndex(1), ErasureShardIndex(1)]
  assert recoverErasureChunks(input, duplicate, BundleLength(6), ErasureShards(6),
      policy).error == ErasureWordError.InvalidIndex
  for bad in [6'u64, high(uint64)]:
    let wrong = [ErasureShardIndex(0), ErasureShardIndex(1), ErasureShardIndex(bad)]
    assert recoverErasureChunks(input, wrong, BundleLength(6), ErasureShards(6),
        policy).error == ErasureWordError.InvalidIndex
  assert recoverErasureChunks(input, indices.toOpenArray(0, 1), BundleLength(6), ErasureShards(6),
      policy).error == ErasureWordError.InvalidLength
  for extent in 0..<input.len:
    assert recoverErasureChunks(input.toOpenArray(0, extent-1), indices, BundleLength(6),
        ErasureShards(6), policy).error == ErasureWordError.InvalidLength
  assert recoverErasureChunks(@[0'u8, 1, 2, 3, 4, 5, 6], indices, BundleLength(6), ErasureShards(6),
      policy).error == ErasureWordError.InvalidLength
  assert default(RecoveredErasureChunks).recoveredBytes.error == ErasureWordError.Uninitialized
  assert default(RecoveredErasureChunks).recoveryInfo.error == ErasureWordError.Uninitialized
  cycle()
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle()
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("pvm_erasure_recovery", 1000, before, after)
  echo "PVM erasure recovery passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
main()
