## Identical checked workload compiled against isolated pre-port and current source snapshots.
import std/[assertions, syncio]
import ./src/codec/[natural, fixed_unsigned, bounded, owned]
import ./src/crypto/primitives

# Opaque non-LTO observation keeps complete operation results visible without altering their bytes.
proc observe(data: pointer, size: csize_t) {.importc: "rb_observe", cdecl.}
# OS monotonic timing and trusted controls are identical across both compiler runtimes.
proc now(): uint64 {.importc: "rb_now_ns", cdecl.}
# The harness supplies bounded case/iteration controls; native timing excludes process setup and output.
proc control(which: cint): cint {.importc: "rb_control", cdecl.}

type
  # Prepared owners and disjoint outputs live outside timing; owned decode's last ARC release stays inside each step.
  Workload = object
    kind: int
    naturalWire, sequenceWire, blobWire, payload, output: seq[byte]
    values, decoded: seq[FixedUnsigned]
    owner: OwnedFrame
    key: EdPublicKey
    signature: EdSignature

# Run one genuine checked API operation behind the same noinline observation boundary in both builds.
proc step(item: var Workload): uint64 {.noinline.} =
  case item.kind
  of 0:
    # The overhead reference contains the same function/observer boundary without protocol work.
    var mark = 17'u64
    observe(addr mark, csize_t(sizeof(mark)))
    return mark
  of 1:
    # Successful compact decoding must expose its exact copied value and consumed extent.
    var parsed = natural.decode(item.naturalWire)
    observe(addr parsed, csize_t(sizeof(parsed)))
    assert parsed.ok
    return uint64(parsed.value) xor uint64(parsed.consumed)
  of 2:
    # Caller-owned typed storage is reused; observe the full output to prevent pruning bulk copies.
    var parsed = decodeSequence(item.sequenceWire, ByteWidth(4), ElementLimit(4096), item.decoded)
    assert parsed.error == ContainerError.None
    observe(addr item.decoded[0], csize_t(item.decoded.len * sizeof(FixedUnsigned)))
    return uint64(parsed.count) xor uint64(parsed.consumed) xor uint64(item.decoded[4095])
  of 3:
    # Checked bulk encoding retains the original typed values and disjoint reusable output.
    let written = encodeSequence(item.values, ByteWidth(4), ElementLimit(4096), item.output)
    assert written.error == ContainerError.None
    observe(addr item.output[0], csize_t(written.written))
    return uint64(written.written) xor uint64(item.output[written.written - 1])
  of 4:
    # Snapshot allocation, copy and final ARC destruction are all included in this operation.
    let parsed = decodeOwnedBytes(item.blobWire, ByteLimit(65536))
    assert parsed.error == OwnershipError.None
    let size = ownedBlobLength(parsed.value, 0)
    assert size.error == OwnershipError.None
    observe(unsafeAddr parsed, csize_t(sizeof(parsed)))
    return uint64(size.value)
  of 5:
    # Encoding a process-lived immutable snapshot excludes capture/setup allocation in both builds.
    let written = encodeOwned(item.owner, item.output)
    assert written.error == OwnershipError.None
    observe(addr item.output[0], csize_t(written.value))
    return uint64(written.value) xor uint64(item.output[written.value - 1])
  of 6:
    # Both adapters call the very same pinned native Blake2b library; this is not a provider comparison.
    var hashed = blake2b256(item.payload)
    assert hashed.error == CryptoError.None
    observe(addr hashed, csize_t(sizeof(hashed)))
    return uint64(array[32, byte](hashed.value)[0])
  of 7:
    # The common legacy Keccak provider and payload remain unchanged across compilers.
    var hashed = keccak256(item.payload)
    assert hashed.error == CryptoError.None
    observe(addr hashed, csize_t(sizeof(hashed)))
    return uint64(array[32, byte](hashed.value)[0])
  of 8:
    # Verify the same signed 64-KiB message through the shared ordinary Ed25519 primitive ABI.
    var valid = verify(item.key, item.signature, item.payload)
    observe(addr valid, csize_t(sizeof(valid)))
    assert valid
    return 1
  else:
    assert false # Undefined trusted cases cannot produce a timing result.
    return 0

# Prepare all fixtures and check complete encoder bytes before timing any operations.
proc prepare(kind: int): Workload =
  result = default(Workload)
  result.kind = kind
  result.payload = newSeq[byte](65536)
  for i in 0..<result.payload.len: result.payload[i] = byte(
      i mod 251) # Public fixed fixture, independent of compiler layout.
  let compact = natural.encode(JamNatural(high(uint64) - 17))
  result.naturalWire = newSeq[byte](compact.len)
  for i in 0..<compact.len: result.naturalWire[i] = compact.bytes[i] # Retain only the actual wire prefix.
  result.values = newSeq[FixedUnsigned](4096)
  result.decoded = newSeq[FixedUnsigned](4096)
  for i in 0..<4096: result.values[i] = FixedUnsigned(i) # Every element fits the tested E4 domain.
  result.sequenceWire = newSeq[byte](16386)
  let encoded = encodeSequence(result.values, ByteWidth(4), ElementLimit(4096), result.sequenceWire)
  assert encoded.error == ContainerError.None and encoded.written == result.sequenceWire.len
  result.blobWire = newSeq[byte](65539)
  let blob = encodeBytes(result.payload, ByteLimit(65536), result.blobWire)
  assert blob.error == ContainerError.None and blob.written == result.blobWire.len
  let captured = decodeOwnedBytes(result.blobWire, ByteLimit(65536))
  assert captured.error == OwnershipError.None
  result.owner = captured.value
  result.output = newSeq[byte](65539)
  let seed = importSeed(default(array[32, byte]))
  assert seed.error == CryptoError.None
  let publicKey = publicKey(seed.value)
  let signed = sign(seed.value, result.payload)
  assert publicKey.error == CryptoError.None and signed.error == CryptoError.None
  result.key = publicKey.value
  result.signature = signed.value
  discard step(result) # All operations validate success outside timing before the warmed measurement.
  if kind == 3:
    # Check every byte of the bulk sequence encoding before accepting a fingerprint/timing.
    for i in 0..<result.sequenceWire.len: assert result.output[i] == result.sequenceWire[i]
  elif kind == 5:
    # Prepared snapshot encoding must reproduce the complete original byte-string wire.
    for i in 0..<result.blobWire.len: assert result.output[i] == result.blobWire[i]

# Time one batch; process startup, input preparation, warmup and output are outside the measured interval.
proc main() =
  let iterations = int(control(1))
  let kind = int(control(0))
  assert kind in 0..8 and iterations in 1..20000000
  var item = prepare(kind)
  var mark = 0'u64
  for i in 0..<64: mark = mark xor step(item) # Identical warmup for both compilers and every case.
  let started = now()
  for i in 0..<iterations: mark = mark xor step(item) # Observe each real operation, never only the final loop value.
  let elapsed = now() - started
  echo "TIME ", elapsed
  echo "CHECK ", mark

main() # Prepared snapshot owners retire normally after the measured work.
