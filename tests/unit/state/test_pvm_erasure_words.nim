# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_erasure_words_arc_release"}

## Independent full parity witnesses, exact field-work bounds and immutable scalar-code ownership.

import std/[assertions, syncio]
import ../../../src/state/erasure/words as erasure_words
import ../../../src/codec/bounded
import ../../../src/codec/work/report as work_report
import ../../support/[pvm_erasure_vectors, arc_evidence]

proc generous(): ErasureWordLimits =
  ## Permit every valid scalar geometry while remaining an explicit local policy.
  ErasureWordLimits(bytes: ByteLimit(10000), products: FieldProductLimit(1000000))
proc expect[T](outcome: ErasureWordResult[T], reason: ErasureWordError) =
  ## Compare exact refusals without extracting incomplete output words.
  assert outcome.error == reason, "erasure word reason"
proc check(validators: uint16, expected: openArray[uint16]) =
  ## Build independent arithmetic message words and compare every systematic and parity coordinate.
  let bound = int(validators) div 3+1
  var original = 1
  for candidate in 1..bound:
    if 2052 mod candidate == 0: original = candidate # Increasing enumeration is independent of the geometry search.
  var input = newSeq[ErasureWord](original)
  for index in 0..<original:
    input[index] = ErasureWord(uint16(((index*257+0x8123) xor (index*index*19)) and 65535))
  let code = encodeErasureWords(input, ErasureShards(validators), generous()).value
  let info = code.wordCodeInfo.value
  assert expected.len == int(validators), "complete frozen codeword"
  assert info.originalShards == uint64(original), "original count"
  assert info.retainedBytes == uint64(validators)*2, "retained word bytes"
  for index in 0..<expected.len:
    assert uint16(code.codeWord(ErasureShardIndex(uint64(index))).value) == expected[index], "independent Lagrange parity word"
  for index in 0..<original:
    assert uint16(code.codeWord(ErasureShardIndex(uint64(index))).value) == uint16(input[index]), "systematic identity"
  var exact = ErasureWordLimits(bytes: ByteLimit(info.retainedBytes+info.workspaceBytes),
      products: FieldProductLimit(info.products))
  expect(encodeErasureWords(input, ErasureShards(validators), exact), ErasureWordError.None)
  exact.bytes = ByteLimit(uint64(exact.bytes)-1)
  expect(encodeErasureWords(input, ErasureShards(validators), exact),
      ErasureWordError.LimitExceeded)
  exact.bytes = ByteLimit(uint64(exact.bytes)+1)
  exact.products = FieldProductLimit(info.products-1)
  expect(encodeErasureWords(input, ErasureShards(validators), exact),
      ErasureWordError.LimitExceeded)
  expect(code.codeWord(ErasureShardIndex(uint64(validators))), ErasureWordError.InvalidIndex)
  expect(code.codeWord(ErasureShardIndex(high(uint64))), ErasureWordError.InvalidIndex)
  let first = uint16(code.codeWord(ErasureShardIndex(0)).value)
  input[0] = ErasureWord(first xor 1)
  assert uint16(code.codeWord(ErasureShardIndex(0)).value) == first, "caller input copy isolation"
  var copied = code.wordCodeInfo.value
  copied.originalShards = 0
  assert code.wordCodeInfo.value.originalShards == uint64(original), "metadata isolation"
check(6, Words6)
check(9, Words9)
check(51, Words51)
check(1023, Words1023)
# Constant polynomials exercise every Cantor bit through both basis conversions, including zero and all bits.
for word in [0'u16, 65535, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768]:
  let input = [ErasureWord(word), ErasureWord(word), ErasureWord(word)]
  let code = encodeErasureWords(input, ErasureShards(6), generous()).value
  for index in 0..<6:
    assert uint16(code.codeWord(ErasureShardIndex(uint64(index))).value) == word, "constant polynomial and basis roundtrip"
let input = [ErasureWord(0), ErasureWord(1), ErasureWord(65535)]
let empty: seq[ErasureWord] = @[]
expect(encodeErasureWords(empty, ErasureShards(6), generous()), ErasureWordError.InvalidLength)
expect(encodeErasureWords(input.toOpenArray(0, 1), ErasureShards(6), generous()),
    ErasureWordError.InvalidLength)
expect(encodeErasureWords(input, ErasureShards(9), generous()), ErasureWordError.InvalidLength)
let oversized = [ErasureWord(0), ErasureWord(1), ErasureWord(2), ErasureWord(3)]
expect(encodeErasureWords(oversized, ErasureShards(6), generous()), ErasureWordError.InvalidLength)
for shards in [0'u16, 3, 7, 1022, 1024, 65535]:
  expect(encodeErasureWords(input, ErasureShards(shards), generous()),
      ErasureWordError.InvalidShards)
expect(default(ErasureWordCode).wordCodeInfo, ErasureWordError.Uninitialized)
expect(default(ErasureWordCode).codeWord(ErasureShardIndex(0)), ErasureWordError.Uninitialized)
expect(default(ErasureWordResult[ErasureWordCode]), ErasureWordError.Uninitialized)
let code = encodeErasureWords(input, ErasureShards(6), generous()).value
assert code.wordCodeInfo.value.products == 102, "independent exact small work count"
assert code.wordCodeInfo.value.workspaceBytes == 14, "independent small workspace"
proc detached(): ErasureWordCode =
  ## Return a code after its original local input descriptor has retired.
  let local = [ErasureWord(0), ErasureWord(1), ErasureWord(65535)]
  encodeErasureWords(local, ErasureShards(6), generous()).value
assert uint16(detached().codeWord(ErasureShardIndex(5)).value) == uint16(code.codeWord(
    ErasureShardIndex(5)).value), "detached lifetime"
proc cycle() =
  ## Release completed output, coefficient workspace, inverse table and refused candidates.
  let done = encodeErasureWords(input, ErasureShards(6), generous()).value
  assert done.wordCodeInfo.value.products == 102, "cycle completed work"
  expect(encodeErasureWords(input, ErasureShards(6), ErasureWordLimits()),
      ErasureWordError.LimitExceeded)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "erasure word ARC release"
recordArcRelease("pvm_erasure_words", 1000, before, after)
echo "PVM erasure words passed"
echo "ARC_RELEASE cycles=1000 unchanged"
