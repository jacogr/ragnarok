# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded scalar GP systematic Reed–Solomon transform over the pinned Cantor-coordinate field.

import ../../codec/bounded
import ../../codec/work/report as work_report
import ./layout as erasure_layout

type
  ErasureWord* = distinct uint16 ## Numeric Cantor coordinates corresponding to a little-endian E2 pair.
  ErasureShardIndex* = distinct uint64 ## Full encoded-shard ordinal, including parity positions.
  FieldProductLimit* = distinct uint64 ## Local field multiplication policy, distinct from bytes and shard counts.
  ErasureWordError* {.pure.} = enum ## Refusals expose no partial polynomial, output or work certificate.
    Uninitialized, None, InvalidShards, InvalidLength, LimitExceeded, InvalidIndex
  ErasureWordLimits* = object ## Exact logical buffer payload and deterministic field-product budgets.
    bytes*: ByteLimit
    products*: FieldProductLimit
  ErasureWordInfo* = object ## Copied dimensions/work facts are not bundle or availability provenance.
    shards*: ErasureShards
    originalShards*, retainedBytes*, workspaceBytes*, products*: uint64
  WordData = ref object ## Immutable acyclic heap stores only complete systematic and parity words.
    info: ErasureWordInfo
    words: seq[ErasureWord]
  ErasureWordCode* = object ## Only successful encoding initializes a codeword owner.
    data: nil WordData
  ErasureWordResult*[T] = object ## Guarded success payloads preserve optimized result selection.
    case status: ErasureWordError
    of None:
      completed: T
    else:
      discard                    # Refusals have only their selected reason.

const
  CantorBasis = [0x1'u16, 0xacca, 0x3c0e, 0x163e, 0xc582, 0xed2e, 0x914c, 0x4012, 0x6c98, 0x10d8,
      0x6a72, 0xb900, 0xfdb8, 0xfb34, 0xff38, 0x991e]
  PolynomialBasis = [0x1'u16, 0x4690, 0x65d8, 0x62d0, 0x5734, 0x45f0, 0x53b8, 0x1e38, 0x7cae,
      0x4e38, 0x6708, 0xc25c, 0x7a64, 0x9eac, 0x1124, 0x523a]

func error*[T](outcome: ErasureWordResult[T]): ErasureWordError =
  ## Read the selected reason without permitting result retagging.
  outcome.status

func value*[T](outcome: ErasureWordResult[T]): T
    {.requires: outcome.status == ErasureWordError.None.} =
  ## Extract only a fully completed selected success.
  outcome.completed

func changeBasis(word: uint16, columns: array[16, uint16]): uint16 =
  ## Apply an exact binary linear map; both basis tables are inverses over all sixteen bits.
  var converted = 0'u16
  for bit in 0..<16:
    if (word and (1'u16 shl bit)) != 0: converted = converted xor columns[bit]
  converted

func multiply(left, right: uint16): uint16 =
  ## Multiply polynomial representatives modulo x^16+x^5+x^3+x^2+1.
  var shifted = uint32(left)
  var bits = uint32(right)
  var product = 0'u32
  for bit in 0..<16:
    if (bits and 1) != 0: product = product xor shifted # Characteristic two adds by XOR.
    bits = bits shr 1
    shifted = shifted shl 1
    if (shifted and 65536) != 0: shifted = shifted xor 65581 # 0x1002d cancels the degree-sixteen term.
  uint16(product) # Reduction keeps shifted and product below 2^16 throughout.

func inverse(word: uint16): uint16 =
  ## Fermat inversion of nonzero polynomial representatives uses exactly 31 field products.
  var power = 65534'u32
  var base = word
  var answer = 1'u16
  while power > 0:
    if (power and 1) != 0: answer = multiply(answer, base) # Fifteen set exponent bits select a product.
    base = multiply(base, base) # All sixteen iterations square, including the final iteration.
    power = power shr 1
  answer

proc wordCodeInfo*(code: ErasureWordCode): ErasureWordResult[ErasureWordInfo] =
  ## Copy fixed work/size facts from a completed immutable codeword.
  let data = code.data
  if data == nil: return ErasureWordResult[ErasureWordInfo](status: ErasureWordError.Uninitialized)
  ErasureWordResult[ErasureWordInfo](status: ErasureWordError.None, completed: data.info)

proc codeWord*(code: ErasureWordCode, index: ErasureShardIndex): ErasureWordResult[ErasureWord] =
  ## Copy one systematic or parity scalar without exposing writable sequence storage.
  let data = code.data
  if data == nil: return ErasureWordResult[ErasureWord](status: ErasureWordError.Uninitialized)
  if uint64(index) >= uint64(uint16(data.info.shards)):
    return ErasureWordResult[ErasureWord](status: ErasureWordError.InvalidIndex)
  ErasureWordResult[ErasureWord](status: ErasureWordError.None, completed: data.words[int(uint64(index))])

proc encodeErasureWords*(input: openArray[ErasureWord], shards: ErasureShards,
    limits: ErasureWordLimits): ErasureWordResult[ErasureWordCode] =
  ## Borrow stable original words during encoding; preflight all variable buffers and multiplication work.
  template fail(reason: ErasureWordError) =
    return ErasureWordResult[ErasureWordCode](status: reason)
  let described = erasureGeometry(BundleLength(0), shards)
  if described.error != ErasureLayoutError.None: fail(ErasureWordError.InvalidShards)
  let count = int(uint16(shards))
  let original = int(described.value.originalShards)
  if input.len != original: fail(ErasureWordError.InvalidLength)
  var span = 1
  while span < original: span *= 2 # Original <=342 proves span <=512 before multiplication/index conversion.
  let products = uint64(31*(span-1)+original*(original-1) div 2+(count-original)*(original-1))
  let retained = uint64(count)*2
  let workspace = uint64(original+span)*2
  if retained+workspace > uint64(limits.bytes) or products > uint64(limits.products):
    fail(ErasureWordError.LimitExceeded)
  var coefficients = newSeq[uint16](original)
  var inverses = newSeq[uint16](span)
  var words = newSeq[ErasureWord](count)
  # Every nonzero original-index XOR fits below span and denotes a nonzero Cantor field element.
  for index in 1..<span: inverses[index] = inverse(changeBasis(uint16(index), CantorBasis))
  for index in 0..<original:
    words[index] = input[index] # Retain exact systematic words, independent of caller mutation after return.
    coefficients[index] = changeBasis(uint16(input[index]), CantorBasis)
  # Descending updates preserve the preceding divided-difference row in place.
  for order in 1..<original:
    var index = original-1
    while index >= order:
      coefficients[index] = multiply(coefficients[index] xor coefficients[index-1], inverses[
          index xor (index-order)])
      dec index
  # Nested Newton evaluation needs original-1 products per parity position.
  for index in original..<count:
    let point = changeBasis(uint16(index), CantorBasis)
    var evaluated = coefficients[original-1]
    var term = original-2
    while term >= 0:
      evaluated = multiply(evaluated, point xor changeBasis(uint16(term),
          CantorBasis)) xor coefficients[term]
      dec term
    words[index] = ErasureWord(changeBasis(evaluated, PolynomialBasis))
  ErasureWordResult[ErasureWordCode](status: ErasureWordError.None,
    completed: ErasureWordCode(data: WordData(words: words, info: ErasureWordInfo(shards: shards,
      originalShards: uint64(original), retainedBytes: retained, workspaceBytes: workspace,
          products: products))))
