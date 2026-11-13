# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded scalar GP systematic Reed–Solomon transform over the pinned Cantor-coordinate field.

import ../../codec/bounded
import ../../codec/work/report as work_report
import ./layout as erasure_layout
from ../../codec/work/package import MaxBundleBytes

type
  ErasureWord* = distinct uint16 ## Numeric Cantor coordinates corresponding to a little-endian E2 pair.
  ErasureShardIndex* = distinct uint64 ## Full encoded-shard ordinal, including parity positions.
  FieldProductLimit* = distinct uint64 ## Local field multiplication policy, distinct from bytes and shard counts.
  ErasureWordError* {.pure.} = enum ## Refusals expose no partial polynomial, output or work certificate.
    Uninitialized, None, InvalidShards, InvalidLength, LimitExceeded, InvalidIndex, InvalidPadding
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

func encodingLimits*(geometry: ErasureGeometry): ErasureWordLimits =
  ## Bounds for one column of validated erasure geometry, including implicit zero coordinates.
  let count = uint64(uint16(geometry.shards))
  let span = geometry.interpolationPoints
  if count > 1023 or geometry.originalShards == 0 or geometry.originalShards > count or
      span < geometry.originalShards or span > 512:
    return default(ErasureWordLimits)
  let parity = count-geometry.originalShards
  ErasureWordLimits(bytes: ByteLimit((count+2*span)*2),
    products: FieldProductLimit(31*(span-1)+span*(span-1) div 2+parity*(span-1)))

func evaluationIndex(index, original, span: int): int =
  ## Systematic coordinates are unchanged. Parity follows the implicit zero coordinates.
  if index < original: index else: index+span-original

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
  let span = int(described.value.interpolationPoints)
  let required = encodingLimits(described.value)
  let products = uint64(required.products)
  let retained = uint64(count)*2
  let workspace = uint64(required.bytes)-retained
  if uint64(required.bytes) > uint64(limits.bytes) or products > uint64(limits.products):
    fail(ErasureWordError.LimitExceeded)
  var coefficients = newSeq[uint16](span)
  var inverses = newSeq[uint16](span)
  var words = newSeq[ErasureWord](count)
  # Every nonzero original-index XOR fits below span and denotes a nonzero Cantor field element.
  for index in 1..<span: inverses[index] = inverse(changeBasis(uint16(index), CantorBasis))
  for index in 0..<original:
    words[index] = input[index] # Retain exact systematic words, independent of caller mutation after return.
    coefficients[index] = changeBasis(uint16(input[index]), CantorBasis)
  # Descending updates preserve the preceding divided-difference row in place.
  for order in 1..<span:
    var index = span-1
    while index >= order:
      coefficients[index] = multiply(coefficients[index] xor coefficients[index-1], inverses[
          index xor (index-order)])
      dec index
  # Nested Newton evaluation needs span-1 products per parity position.
  for index in original..<count:
    let point = changeBasis(uint16(evaluationIndex(index, original, span)), CantorBasis)
    var evaluated = coefficients[span-1]
    var term = span-2
    while term >= 0:
      evaluated = multiply(evaluated, point xor changeBasis(uint16(term),
          CantorBasis)) xor coefficients[term]
      dec term
    words[index] = ErasureWord(changeBasis(evaluated, PolynomialBasis))
  ErasureWordResult[ErasureWordCode](status: ErasureWordError.None,
    completed: ErasureWordCode(data: WordData(words: words, info: ErasureWordInfo(shards: shards,
      originalShards: uint64(original), retainedBytes: retained, workspaceBytes: workspace,
          products: products))))

type
  ErasureRecoveryInfo* = object ## Copied complete resource facts confer neither source authenticity nor proof validity.
    length*: BundleLength
    shards*: ErasureShards
    originalShards*, missingShards*, retainedBytes*, workspaceBytes*, products*: uint64
  RecoveryData = ref object ## Only detached reconstructed bytes survive; no caller chunk or index alias is retained.
    info: ErasureRecoveryInfo
    bytes: seq[byte]
  RecoveredErasureChunks* = object ## Default/rejected recovery exposes no partial systematic prefix.
    data: nil RecoveryData

proc recoveryInfo*(recovered: RecoveredErasureChunks): ErasureWordResult[ErasureRecoveryInfo] =
  ## Observe fixed dimensions only after complete recovery and padding validation.
  let data = recovered.data
  if data == nil: return ErasureWordResult[ErasureRecoveryInfo](
      status: ErasureWordError.Uninitialized)
  ErasureWordResult[ErasureRecoveryInfo](status: ErasureWordError.None, completed: data.info)

proc recoveredBytes*(recovered: RecoveredErasureChunks): ErasureWordResult[seq[byte]] =
  ## Return an independent original-length copy; retained checked padding never appears as payload.
  let data = recovered.data
  if data == nil: return ErasureWordResult[seq[byte]](status: ErasureWordError.Uninitialized)
  var bytes = newSeq[byte](int(uint32(data.info.length)))
  for index in 0..<bytes.len: bytes[index] = data.bytes[index]
  ErasureWordResult[seq[byte]](status: ErasureWordError.None, completed: bytes)

proc recoverErasureChunks*(input: openArray[byte], indices: openArray[ErasureShardIndex],
    length: BundleLength, shards: ErasureShards,
    limits: ErasureWordLimits): ErasureWordResult[RecoveredErasureChunks] =
  ## Borrow exactly threshold indexed row-major chunks; bound complete work before allocation and reconstruct without granting authenticity.
  template fail(reason: ErasureWordError) =
    return ErasureWordResult[RecoveredErasureChunks](status: reason)
  let bytes = uint64(uint32(length))
  if bytes == 0 or bytes > uint64(MaxBundleBytes): fail(ErasureWordError.InvalidLength)
  let described = erasureGeometry(length, shards)
  if described.error != ErasureLayoutError.None: fail(ErasureWordError.InvalidShards)
  let original = int(described.value.originalShards)
  let count = int(uint16(shards))
  let width = int(described.value.bundleChunkBytes)
  if indices.len != original or uint64(input.len) != described.value.paddedBytes:
    fail(ErasureWordError.InvalidLength)
  var seen = default(array[1023, bool])
  var missing = original
  for index in indices:
    # Validate before narrowing/indexing; duplicate points would select a zero denominator.
    if uint64(index) >= uint64(count): fail(ErasureWordError.InvalidIndex)
    let position = int(uint64(index))
    if seen[position]: fail(ErasureWordError.InvalidIndex)
    seen[position] = true
    if position < original: dec missing
  let span = int(described.value.interpolationPoints)
  # At most 1023 validator slots plus 170 implicit points fit below 2048.
  # Store coordinates in supplied-row order, then append the known zero points.
  var coordinates = default(array[512, int])
  var differences = default(array[2048, bool])
  var differenceCount = 0'u64
  if missing > 0:
    for row in 0..<original:
      coordinates[row] = evaluationIndex(int(uint64(indices[row])), original, span)
    for row in original..<span: coordinates[row] = row
    for row in 0..<span:
      for preceding in 0..<row:
        let difference = coordinates[row] xor coordinates[preceding]
        if not differences[difference]:
          differences[difference] = true
          inc differenceCount
  let columns = width div 2
  let inverseCount = if count+span-original <= 1024: 1024 else: 2048
  let products = if missing == 0: 0'u64 else:
    differenceCount*31+uint64(columns)*(uint64(span*(span-1) div 2)+uint64(missing*(span-1)))
  let workspace = uint64(original*sizeof(int))+(if missing == 0: 0'u64 else:
    uint64(span*4+inverseCount*2))
  let retained = described.value.paddedBytes
  if retained+workspace > uint64(limits.bytes) or products > uint64(limits.products):
    fail(ErasureWordError.LimitExceeded)
  var positions = newSeq[int](original)
  for index in 0..<original: positions[index] = -1
  for row in 0..<original:
    if uint64(indices[row]) < uint64(original): positions[int(uint64(indices[row]))] = row
  var coefficients, points, inverses: seq[uint16] = @[]
  if missing > 0:
    coefficients = newSeq[uint16](span)
    points = newSeq[uint16](span)
    inverses = newSeq[uint16](inverseCount)
    for index in 1..<inverseCount:
      if differences[index]: inverses[index] = inverse(changeBasis(uint16(index), CantorBasis))
    for row in 0..<span: points[row] = changeBasis(uint16(coordinates[row]), CantorBasis)
  var output = newSeq[byte](int(retained))
  for column in 0..<columns:
    if missing > 0:
      for row in 0..<original:
        let offset = row*width+column*2
        let word = uint16(input[offset]) or (uint16(input[offset+1]) shl 8)
        coefficients[row] = changeBasis(word, CantorBasis)
      for row in original..<span: coefficients[row] = 0
      for order in 1..<span:
        var row = span-1
        while row >= order:
          let difference = coordinates[row] xor coordinates[row-order]
          coefficients[row] = multiply(coefficients[row] xor coefficients[row-1], inverses[difference])
          dec row
    for row in 0..<original:
      let offset = row*width+column*2
      if positions[row] >= 0:
        let source = positions[row]*width+column*2
        output[offset] = input[source]
        output[offset+1] = input[source+1]
      else:
        # Newton evaluation uses supplied-point order; output order is always systematic coordinate order.
        let point = changeBasis(uint16(row), CantorBasis)
        var evaluated = coefficients[span-1]
        var term = span-2
        while term >= 0:
          evaluated = multiply(evaluated, point xor points[term]) xor coefficients[term]
          dec term
        let word = changeBasis(evaluated, PolynomialBasis)
        output[offset] = byte(word and 255)
        output[offset+1] = byte(word shr 8)
  for index in int(bytes)..<output.len:
    if output[index] != 0: fail(ErasureWordError.InvalidPadding) # Never hide inconsistent recovered padding by merely truncating the buffer.
  ErasureWordResult[RecoveredErasureChunks](status: ErasureWordError.None,
    completed: RecoveredErasureChunks(data: RecoveryData(bytes: output,
      info: ErasureRecoveryInfo(length: length, shards: shards, originalShards: uint64(original),
        missingShards: uint64(missing), retainedBytes: retained, workspaceBytes: workspace,
            products: products))))
