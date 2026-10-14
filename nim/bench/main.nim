## Optimized checked M1/M2 measurement adapter. File loading, preflight and allocation instrumentation are outside timing.
import std/[os, strutils]
when not defined(nimAllocStats):
  # Allocator-counting binaries never read the clock or report performance.
  import std/[monotimes, times]
import ../src/[natural, fixed_unsigned, bounded, composite, work_digest, owned]
import ../crypto/primitives

# Opaque shared observation prevents result pruning; the separately compiled C function never touches its argument.
proc observe(data: pointer, size: csize_t) {.importc: "rb_observe", cdecl, raises: [].}
# Process RSS includes prepared fixtures/runtime, with platform units normalized by the common observer.
proc peakRss(): uint64 {.importc: "rb_peak_rss", cdecl, raises: [].}

type
  # One preflighted operation uses typed values and stable nonoverlapping input/output storage.
  BenchCase = object
    kind, operation: string
    wire, output: seq[byte]
    offset, length: int
    number: uint64
    values: seq[FixedUnsigned]
    decodedValues: seq[FixedUnsigned]
    digest: WorkDigest
    owner: OwnedFrame

# Return a small observed fingerprint; full encoder equivalence is checked outside timing.
proc wireMark(bytes: openArray[byte], length: int): uint64 {.raises: [].} =
  result = uint64(length)
  # Zero-width encodings have no valid byte addresses to sample.
  if length > 0: result = result xor uint64(bytes[0]) xor uint64(bytes[length - 1])

# Exercise one real API call and checked result selection; noinline keeps the runtime-input operation boundary intact.
proc step(item: var BenchCase): uint64 {.noinline, raises: [].} =
  # The baseline contains the same call/observation boundary but performs no codec work.
  if item.kind == "baseline":
    observe(addr item.number, csize_t(sizeof(item.number)))
    return item.number
  # Primitive inputs are typed values prepared from the independently generated wire.
  if item.kind == "natural":
    if item.operation == "encode":
      var encoded = natural.encode(JamNatural(item.number))
      observe(addr encoded, csize_t(sizeof(encoded)))
      return wireMark(encoded.bytes, encoded.len)
    else:
      var decoded = natural.decode(item.wire)
      observe(addr decoded, csize_t(sizeof(decoded)))
      doAssert decoded.ok
      return uint64(decoded.value) xor uint64(decoded.consumed)
  if item.kind == "fixed":
    if item.operation == "encode":
      var encoded = encodeFixed(FixedUnsigned(item.number), ByteWidth(item.wire.len))
      observe(addr encoded, csize_t(sizeof(encoded)))
      doAssert encoded.ok
      return wireMark(encoded.encoded.bytes, encoded.encoded.len)
    else:
      var decoded = decodeFixed(item.wire, ByteWidth(item.wire.len))
      observe(addr decoded, csize_t(sizeof(decoded)))
      doAssert decoded.ok
      return uint64(decoded.value) xor uint64(decoded.consumed)
  # The M2 case measures the existing provider as well as the native adapter; it is not a compiler-only comparison.
  if item.kind == "blake2b":
    var hashed = blake2b256(item.wire)
    observe(addr hashed, csize_t(sizeof(hashed)))
    doAssert hashed.error == CryptoError.None
    let bytes = array[32, byte](hashed.value)
    return wireMark(bytes, bytes.len)
  # Owned encoding measures a snapshot prepared once; it does not include a hidden decode/allocation.
  if item.operation == "owned-encode":
    let written = encodeOwned(item.owner, item.output)
    doAssert written.error == OwnershipError.None
    observe(addr item.output[0], csize_t(written.value))
    return wireMark(item.output, written.value)
  if item.operation == "owned-decode":
    let decoded = if item.kind == "blob": decodeOwnedBytes(item.wire, ByteLimit(
        1048576)) else: decodeOwnedDigest(item.wire, ByteLimit(1048576))
    doAssert decoded.error == OwnershipError.None
    let info = ownedInfo(decoded.value)
    doAssert info.error == OwnershipError.None
    var mark = uint64(info.value.consumed)
    if item.kind == "blob":
      let length = ownedBlobLength(decoded.value, 0)
      doAssert length.error == OwnershipError.None
      mark = mark xor uint64(length.value)
    else:
      let value = ownedDigestInfo(decoded.value)
      doAssert value.error == OwnershipError.None
      mark = mark xor uint64(uint32(value.value.service)) xor uint64(
          value.value.accumulateGas) xor uint64(value.value.refine.gasUsed)
    observe(unsafeAddr decoded, csize_t(sizeof(decoded)))
    return mark # Last ARC release is part of this operation, before the noinline call returns.
  # Caller-owned destination storage is reused across borrowed encode/decode calls.
  if item.operation == "encode":
    var written: int
    if item.kind == "blob":
      let encoded = encodeBytes(item.wire.toOpenArray(item.offset, item.offset + item.length - 1),
          ByteLimit(1048576), item.output)
      doAssert encoded.error == ContainerError.None
      written = encoded.written
    elif item.kind == "sequence":
      let encoded = encodeSequence(item.values, ByteWidth(4), ElementLimit(16384), item.output)
      doAssert encoded.error == ContainerError.None
      written = encoded.written
    else:
      let encoded = encodeDigestBorrowed(item.digest, item.wire, ByteLimit(1048576), item.output)
      doAssert encoded.error == CompositeError.None
      written = encoded.written
    observe(addr item.output[0], csize_t(written))
    return wireMark(item.output, written)
  # Borrowed decodes observe the complete returned structure, preventing optimization of unreported fields.
  if item.kind == "blob":
    var decoded = decodeBytesBorrowed(item.wire, ByteLimit(1048576))
    observe(addr decoded, csize_t(sizeof(decoded)))
    doAssert decoded.error == ContainerError.None
    return uint64(decoded.consumed) xor uint64(decoded.length)
  elif item.kind == "sequence":
    var decoded = decodeSequence(item.wire, ByteWidth(4), ElementLimit(16384), item.decodedValues)
    observe(addr decoded, csize_t(sizeof(decoded)))
    observe(addr item.decodedValues[0], csize_t(item.decodedValues.len * sizeof(FixedUnsigned)))
    doAssert decoded.error == ContainerError.None
    return uint64(decoded.consumed) xor uint64(decoded.count)
  else:
    var decoded = decodeDigestBorrowed(item.wire, ByteLimit(1048576))
    observe(addr decoded, csize_t(sizeof(decoded)))
    doAssert decoded.error == CompositeError.None
    return uint64(decoded.consumed) xor uint64(uint32(decoded.value.service)) xor uint64(
        decoded.value.accumulateGas) xor uint64(decoded.value.refine.gasUsed)

# Preflight input, prepare encode values and verify complete encoder bytes before timing any operations.
proc prepare(kind, operation, path: string): BenchCase =
  result.kind = kind
  result.operation = operation
  let raw = readFile(path)
  doAssert raw.len <= 1048832
  result.wire = newSeq[byte](raw.len)
  for i, value in raw: result.wire[i] = byte(value) # Fixtures are retained independently of file text.
  result.output = newSeq[byte](max(1, raw.len))
  # Primitive setup checks exact consumption and byte-level inverse behavior outside the measured loop.
  case kind
  of "baseline": result.number = 17
  of "natural":
    let decoded = natural.decode(result.wire)
    doAssert decoded.ok and decoded.consumed == result.wire.len
    result.number = uint64(decoded.value)
    let encoded = natural.encode(decoded.value)
    for i in 0..<encoded.len: doAssert encoded.bytes[i] == result.wire[i]
  of "fixed":
    let decoded = decodeFixed(result.wire, ByteWidth(result.wire.len))
    doAssert decoded.ok
    result.number = uint64(decoded.value)
    let encoded = encodeFixed(decoded.value, ByteWidth(result.wire.len))
    doAssert encoded.ok
    for i in 0..<result.wire.len: doAssert encoded.encoded.bytes[i] == result.wire[i]
  of "blob":
    let decoded = decodeBytesBorrowed(result.wire, ByteLimit(1048576))
    doAssert decoded.error == ContainerError.None and decoded.consumed == result.wire.len
    result.offset = decoded.offset
    result.length = decoded.length
  of "sequence":
    result.values = newSeq[FixedUnsigned](16384)
    let decoded = decodeSequence(result.wire, ByteWidth(4), ElementLimit(16384), result.values)
    doAssert decoded.error == ContainerError.None and decoded.consumed == result.wire.len
    result.values.setLen(decoded.count)
    result.decodedValues = newSeq[FixedUnsigned](max(1, decoded.count))
  of "digest":
    let decoded = decodeDigestBorrowed(result.wire, ByteLimit(1048576))
    doAssert decoded.error == CompositeError.None and decoded.consumed == result.wire.len
    result.digest = decoded.value
  of "blake2b":
    let hashed = blake2b256(result.wire)
    doAssert hashed.error == CryptoError.None
    var text = ""
    for value in array[32, byte](hashed.value): text.add(toHex(value, 2).toLowerAscii())
    echo "HASH ", text # Python independently validates the actual provider output before accepting timing.
  else: doAssert false # Trusted case selection still rejects undefined operations.
  # Only owned encoding needs a process-lived prepared snapshot; other operations allocate no hidden setup owner.
  if operation == "owned-encode":
    let decoded = if kind == "blob": decodeOwnedBytes(result.wire, ByteLimit(
        1048576)) else: decodeOwnedDigest(result.wire, ByteLimit(1048576))
    doAssert decoded.error == OwnershipError.None
    result.owner = decoded.value
  let mark = step(result)
  echo "VERIFY ", mark
  # Container encoders must reproduce every original byte; this full scan is deliberately untimed.
  if kind in ["blob", "sequence", "digest"] and operation in ["encode", "owned-encode"]:
    for i, value in result.wire: doAssert result.output[i] == value

# One bounded process reports native batch and single-operation timestamps, never Python startup/IPC latency.
proc main() =
  doAssert paramCount() == 6
  var item = prepare(paramStr(1), paramStr(2), paramStr(3))
  let iterations = parseInt(paramStr(4))
  let samples = parseInt(paramStr(5))
  let latencySamples = parseInt(paramStr(6))
  doAssert iterations in 1..20000000 and samples in 1..31 and latencySamples in 0..256
  var checksum = 0'u64
  # Warm allocator/code paths before either measurements or allocation accounting.
  for iteration in 0..<min(iterations, 64): checksum = checksum xor step(item)
  when defined(nimAllocStats):
    let before = getAllocStats()
    let live = getOccupiedMem()
    for iteration in 0..<iterations: checksum = checksum xor step(item)
    let after = getAllocStats() - before
    let delta = getOccupiedMem() - live
    # AllocStats deliberately keeps fields private; use its standard exported string representation, not a runtime patch.
    echo "ALLOC_NIM ", iterations, " ", delta, " ", after
  else:
    # Each batch amortizes timer calls while preserving identical operation counts across languages.
    for sample in 0..<samples:
      let started = getMonoTime()
      for iteration in 0..<iterations: checksum = checksum xor step(item)
      let elapsed = (getMonoTime() - started).inNanoseconds
      echo "BATCH ", iterations, " ", elapsed
    # These are real per-operation samples, including timer/observation overhead, distinct from batch averages.
    var latencies = newSeq[int64](latencySamples)
    for sample in 0..<latencySamples:
      let started = getMonoTime()
      checksum = checksum xor step(item)
      latencies[sample] = (getMonoTime() - started).inNanoseconds
    for elapsed in latencies: echo "LATENCY ", elapsed
  echo "END ", checksum, " ", peakRss()

main() # ARC releases prepared fixtures/snapshots after all measured calls return.
