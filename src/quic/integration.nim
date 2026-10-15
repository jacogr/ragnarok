## CE 143 test preimages are complete C.2 digests; codec/crypto policy stays native, outside the transport ABI.
import std/[os]
import ../[owned, bounded]
when defined(integration):
  # Only explicitly integrated binaries link the existing pinned crypto ABI.
  import ../crypto/primitives

const IntegrationEnabled* = defined(integration)
const WireCap* = 1024 * 1024 + 256

type
  # Requested CE preimage key has its own domain even though Blake2b supplies the underlying bytes.
  PreimageKey* = distinct array[32, byte]
  # Failure alternatives carry no snapshot, byte buffer or consumed extent.
  IntegrationError* {.pure.} = enum
    Uninitialized, None, Codec, Trailing, HashMismatch, Owner, Crypto
  # One immutable snapshot plus caller-owned serialization; the stream retains both until native close.
  VerifiedDigest* = object
    owner*: OwnedFrame
    wire*: seq[byte]
  # Default failures cannot accidentally yield a decoded digest or a response buffer.
  IntegrationResult*[T] = object
    case error*: IntegrationError
    of IntegrationError.None:
      value*: T
    else:
      discard
  # Trusted bounded fixture bank; requests select only exact keys, never filesystem paths.
  IntegrationBank* = object
    wires*: array[8, seq[byte]]
    keys*: array[8, PreimageKey]

# Hash exact raw preimage bytes using the existing M2 adapter; no codec field is reinterpreted as a hash assertion.
proc preimageKey*(input: openArray[byte]): IntegrationResult[PreimageKey] {.raises: [].} =
  when defined(integration):
    let digest = blake2b256(input)
    # Backend failure contains no default digest to import as a valid requested key.
    if digest.error != CryptoError.None: return IntegrationResult[PreimageKey](
        error: IntegrationError.Crypto)
    IntegrationResult[PreimageKey](error: IntegrationError.None,
      value: PreimageKey(array[32, byte](digest.value)))
  else:
    # Ordinary QUIC binaries do not claim the integrated path or link extra crypto symbols.
    IntegrationResult[PreimageKey](error: IntegrationError.Crypto)

# Load only eight trusted bounded public fixtures before opening transport callbacks.
proc loadBank*(bank: var IntegrationBank, directory: string): bool =
  # An empty control cannot silently select the current directory.
  if directory.len == 0: return false
  for index in 0..<8:
    let path = directory / ($index & ".bin")
    # Bound fixture allocation before reading; these paths are harness controls, never network input.
    if getFileSize(path) > WireCap or getFileSize(path) < 1: return false
    let text = readFile(path)
    if text.len > WireCap: return false # Recheck size after the trusted read.
    bank.wires[index] = newSeq[byte](text.len)
    for i, value in text: bank.wires[index][i] = byte(value) # Own the bank's bytes.
    let key = preimageKey(bank.wires[index])
    if key.error != IntegrationError.None: return false # A failed hash cannot seed a fixture lookup.
    bank.keys[index] = key.value
  true

# Look up an exact fixed-width key; minus one never indexes bank storage.
proc findFixture*(bank: IntegrationBank, key: openArray[byte]): int {.raises: [].} =
  if key.len != 32: return -1 # No key truncation/padding.
  for index, expected in bank.keys:
    var matches = true
    for i, value in array[32, byte](expected):
      if key[i] != value: matches = false; break # Entire key equality selects the entry.
    if matches: return index
  -1

# Capture one complete digest, overwrite the borrowed receive/scratch bytes, then hash its owner's serialization.
# This actively proves that asynchronous consumers do not retain source-buffer coordinates or mutable aliases.
proc captureDigest*(input: var openArray[byte], expected: PreimageKey): IntegrationResult[
    VerifiedDigest] {.raises: [].} =
  let parsed = decodeOwnedDigest(input, ByteLimit(1024 * 1024))
  if parsed.error != OwnershipError.None: return IntegrationResult[VerifiedDigest](
      error: IntegrationError.Codec) # No owner after malformed wire.
  let info = ownedInfo(parsed.value)
  if info.error != OwnershipError.None: return IntegrationResult[VerifiedDigest](
      error: IntegrationError.Owner)
  if info.value.consumed != input.len: return IntegrationResult[VerifiedDigest](
      error: IntegrationError.Trailing) # Prefix decoders need a standalone-frame guard.
  # Reuse the original bytes before serialization/hashing; only the immutable snapshot may supply later data.
  for value in input.mitems: value = 0xa5
  var wire = newSeq[byte](input.len)
  let encoded = encodeOwned(parsed.value, wire)
  if encoded.error != OwnershipError.None or encoded.value != wire.len: return IntegrationResult[
      VerifiedDigest](error: IntegrationError.Owner)
  let key = preimageKey(wire)
  if key.error != IntegrationError.None: return IntegrationResult[VerifiedDigest](
      error: IntegrationError.Crypto)
  if array[32, byte](key.value) != array[32, byte](expected): return IntegrationResult[
      VerifiedDigest](error: IntegrationError.HashMismatch) # Bind content to the actual CE query.
  IntegrationResult[VerifiedDigest](error: IntegrationError.None,
    value: VerifiedDigest(owner: parsed.value, wire: wire))

# Fuzz the composition boundary with bounded arbitrary wire and its actual independently retained request key.
proc integrationSelfTest*() =
  doAssert IntegrationEnabled # Ordinary QUIC binaries cannot claim this linked crypto test.
  var defaultResult: IntegrationResult[VerifiedDigest]
  doAssert defaultResult.error == IntegrationError.Uninitialized
  var random = 0x494e544547524154'u64
  # A successful parse must survive source reuse; every failing branch carries only its reason.
  for iteration in 0..<10000:
    var input: array[128, byte]
    for value in input.mitems:
      random = random xor (random shl 13)
      random = random xor (random shr 7)
      random = random xor (random shl 17)
      value = byte(random and 255)
    let original = input
    let length = iteration mod 129
    let key = preimageKey(input.toOpenArray(0, length - 1))
    doAssert key.error == IntegrationError.None
    let checked = captureDigest(input.toOpenArray(0, length - 1), key.value)
    if checked.error == IntegrationError.None:
      doAssert checked.value.wire.len == length
      for i, value in checked.value.wire: doAssert value == original[
          i] # Serialization must use the pre-mutation immutable owner.
    else:
      doAssert checked.error in [IntegrationError.Codec,
          IntegrationError.Trailing] # Actual key binding rules out a fabricated hash error.
  echo "Nim integration selftest: 10000 arbitrary digest captures passed"
