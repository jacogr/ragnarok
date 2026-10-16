## CE 143 test preimages are complete C.2 digests; codec/crypto policy stays native, outside the transport ABI.
import std/[os, assertions, syncio]
import ../codec/[owned, bounded]
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
  # Immutable acyclic data retains the validated codec owner and its matching serialization.
  VerifiedData = ref object
    owner: OwnedFrame
    wire: seq[byte]
  # Stream/alias handles retain one private snapshot until the last consumer retires.
  VerifiedDigest* = object
    data: nil VerifiedData
  # Default failures cannot accidentally yield a decoded digest or a response buffer.
  IntegrationResult*[T] = object
    case status: IntegrationError
    of None:
      completed: T
    else:
      discard
  # A completely loaded trusted fixture bank is published once; no mutable child storage escapes.
  BankData = ref object
    wires: array[8, seq[byte]]
    keys: array[8, PreimageKey]
  # Immutable bank handles may be retained across streams without a reference back to a peer.
  IntegrationBank* = object
    data: nil BankData

# Read only the reason; defaults/backend failures cannot be retagged as successful integration values.
func error*[T](value: IntegrationResult[T]): IntegrationError = value.status
# Only successful integration results carry a key, snapshot, child owner or completed byte count.
func value*[T](value: IntegrationResult[T]): T {.inline, requires: value.status ==
    IntegrationError.None.} = value.completed

# Obtain a retained immutable codec child; a default integration owner has no child.
proc verifiedOwner*(value: VerifiedDigest): IntegrationResult[OwnedFrame] =
  let data = value.data
  if data == nil: return IntegrationResult[OwnedFrame](status: IntegrationError.Owner) # No default child exists.
  IntegrationResult[OwnedFrame](status: IntegrationError.None, completed: data.owner)

# Inspect exact serialized size without returning mutable snapshot bytes.
proc wireLength*(value: VerifiedDigest): IntegrationResult[int] =
  let data = value.data
  if data == nil: return IntegrationResult[int](status: IntegrationError.Owner) # A retired/default handle has no wire.
  IntegrationResult[int](status: IntegrationError.None, completed: data.wire.len)

# Copy a complete wire into caller-owned storage, preflighting capacity before any output mutation.
proc copyVerifiedWire*(value: VerifiedDigest, output: var openArray[byte]): IntegrationResult[int] =
  let data = value.data
  if data == nil: return IntegrationResult[int](status: IntegrationError.Owner) # Never read a missing snapshot.
  if output.len < data.wire.len: return IntegrationResult[int](
      status: IntegrationError.Owner) # Failure is atomic.
  for i, b in data.wire: output[i] = b # Only caller storage is writable.
  IntegrationResult[int](status: IntegrationError.None, completed: data.wire.len)

# Select a copied fixed key only from a fully published bank and a valid fixture ordinal.
proc fixtureKey*(bank: IntegrationBank, index: int): IntegrationResult[PreimageKey] =
  let data = bank.data
  if data == nil or index < 0 or index >= 8: return IntegrationResult[PreimageKey](
      status: IntegrationError.Owner)
  IntegrationResult[PreimageKey](status: IntegrationError.None, completed: data.keys[index])

# Extract a defensive wire copy for the fixture workload's intentional scratch overwrite.
proc fixtureBytes*(bank: IntegrationBank, index: int): IntegrationResult[seq[byte]] =
  let data = bank.data
  if data == nil or index < 0 or index >= 8: return IntegrationResult[seq[byte]](
      status: IntegrationError.Owner)
  var copied = newSeq[byte](data.wires[index].len)
  for i, b in data.wires[index]: copied[i] = b # No mutable bank backing storage is exported.
  IntegrationResult[seq[byte]](status: IntegrationError.None, completed: copied)

# Hash exact raw preimage bytes using the existing M2 adapter; no codec field is reinterpreted as a hash assertion.
proc preimageKey*(input: openArray[byte]): IntegrationResult[PreimageKey] {.raises: [].} =
  when defined(integration):
    let digest = blake2b256(input)
    # Backend failure contains no default digest to import as a valid requested key.
    if digest.error != CryptoError.None: return IntegrationResult[PreimageKey](
        status: IntegrationError.Crypto)
    IntegrationResult[PreimageKey](status: IntegrationError.None,
      completed: PreimageKey(array[32, byte](digest.value)))
  else:
    # Ordinary QUIC binaries do not claim the integrated path or link extra crypto symbols.
    IntegrationResult[PreimageKey](status: IntegrationError.Crypto)

# Load only eight trusted bounded public fixtures before opening transport callbacks.
proc loadBank*(bank: var IntegrationBank, directory: string): bool =
  # An empty control cannot silently select the current directory.
  if directory.len == 0: return false
  let candidate = BankData(wires: default(array[8, seq[byte]]), keys: default(array[8, PreimageKey]))
  try:
    # Publish only after all eight reads and hashes succeed; failed reloads preserve the old bank.
    for index in 0..<8:
      let path = directory / ($index & ".bin")
      let size = getFileSize(path)
      if size > WireCap or size < 1: return false # These are bounded trusted fixture paths, never network input.
      let text = readFile(path)
      if text.len > WireCap: return false # Recheck after the trusted read.
      candidate.wires[index] = newSeq[byte](text.len)
      for i, value in text: candidate.wires[index][i] = byte(value) # Retain independent source bytes.
      let key = preimageKey(candidate.wires[index])
      if key.error != IntegrationError.None: return false # A refusal cannot publish partial keys/entries.
      candidate.keys[index] = key.value
  except:
    # Recoverable filesystem errors release the candidate and leave the prior snapshot unchanged.
    return false
  bank = IntegrationBank(data: candidate)
  true

# Look up an exact fixed-width key; minus one never indexes bank storage.
proc findFixture*(bank: IntegrationBank, key: openArray[byte]): int {.raises: [].} =
  let data = bank.data
  if data == nil: return -1 # Default banks never select their all-zero placeholder keys.
  if key.len != 32: return -1 # No key truncation/padding.
  for index, expected in data.keys:
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
      status: IntegrationError.Codec) # No owner after malformed wire.
  let info = ownedInfo(parsed.value)
  if info.error != OwnershipError.None: return IntegrationResult[VerifiedDigest](
      status: IntegrationError.Owner)
  if info.value.consumed != input.len: return IntegrationResult[VerifiedDigest](
      status: IntegrationError.Trailing) # Prefix decoders need a standalone-frame guard.
  # Reuse the original bytes before serialization/hashing; only the immutable snapshot may supply later data.
  for i in 0..<input.len: input[i] = 0xa5
  var wire = newSeq[byte](input.len)
  let encoded = encodeOwned(parsed.value, wire)
  if encoded.error != OwnershipError.None or encoded.value != wire.len: return IntegrationResult[
      VerifiedDigest](status: IntegrationError.Owner)
  let key = preimageKey(wire)
  if key.error != IntegrationError.None: return IntegrationResult[VerifiedDigest](
      status: IntegrationError.Crypto)
  if array[32, byte](key.value) != array[32, byte](expected): return IntegrationResult[
      VerifiedDigest](status: IntegrationError.HashMismatch) # Bind content to the actual CE query.
  IntegrationResult[VerifiedDigest](status: IntegrationError.None,
    completed: VerifiedDigest(data: VerifiedData(owner: parsed.value, wire: wire)))

# Fuzz the composition boundary with bounded arbitrary wire and its actual independently retained request key.
proc integrationSelfTest*() =
  assert IntegrationEnabled # Ordinary QUIC binaries cannot claim this linked crypto test.
  var defaultResult = default(IntegrationResult[VerifiedDigest])
  assert defaultResult.error == IntegrationError.Uninitialized
  var random = 0x494e544547524154'u64
  # A successful parse must survive source reuse; every failing branch carries only its reason.
  for iteration in 0..<10000:
    var input = default(array[128, byte])
    for i in 0..<input.len:
      random = random xor (random shl 13)
      random = random xor (random shr 7)
      random = random xor (random shl 17)
      input[i] = byte(random and 255)
    let original = input
    let length = iteration mod 129
    let key = preimageKey(input.toOpenArray(0, length - 1))
    assert key.error == IntegrationError.None
    let checked = captureDigest(input.toOpenArray(0, length - 1), key.value)
    if checked.error == IntegrationError.None:
      assert wireLength(checked.value).value == length
      var copied = newSeq[byte](length)
      assert copyVerifiedWire(checked.value, copied).value == length
      for i, value in copied: assert value == original[
          i] # Serialization retains the pre-mutation immutable owner.
    else:
      assert checked.error in [IntegrationError.Codec,
          IntegrationError.Trailing] # Actual key binding rules out a fabricated hash error.
  echo "Nim integration selftest: 10000 arbitrary digest captures passed"
