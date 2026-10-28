# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## CE 143 test preimages are complete C.2 digests; codec/crypto policy stays native, outside the
## transport ABI.
##
## Exposes owned fixture banks and verified digest/wire results, fixture lookup/capture and an
## integration selftest.

import std/os
import std/assertions
import std/syncio
import ../codec/owned as codec_owned
import ../codec/bounded as codec_bounded
when defined(integration):
  # Only explicitly integrated binaries link the existing pinned crypto ABI.
  import ../crypto/primitives as crypto_primitives

const IntegrationEnabled* = defined(integration)
const WireCap* = 1024 * 1024 + 256

type
  PreimageKey* = distinct array[32, byte] ## Requested CE preimage key has its own domain even though Blake2b supplies the underlying bytes.
  IntegrationError* {.pure.} = enum ## Failure alternatives carry no snapshot, byte buffer or consumed extent.
    Uninitialized, None, Codec, Trailing, HashMismatch, Owner, Crypto
  # Immutable acyclic data retains the validated codec owner and its matching serialization.
  VerifiedData = ref object
    owner: OwnedFrame
    wire: seq[byte]
  VerifiedDigest* = object ## Stream/alias handles retain one private snapshot until the last consumer retires.
    data: nil VerifiedData
  IntegrationResult*[T] = object ## Default failures cannot accidentally yield a decoded digest or a response buffer.
    case status: IntegrationError
    of None:
      completed: T
    else:
      discard
  # A completely loaded trusted fixture bank is published once; no mutable child storage escapes.
  BankData = ref object
    wires: array[8, seq[byte]]
    keys: array[8, PreimageKey]
  IntegrationBank* = object ## Immutable bank handles may be retained across streams without a reference back to a peer.
    data: nil BankData

func error*[T](value: IntegrationResult[T]): IntegrationError =
  ## Read only the reason; defaults/backend failures cannot be retagged as successful integration values.
  value.status
func value*[T](value: IntegrationResult[T]): T {.inline, requires: value.status ==
    IntegrationError.None.} =
  ## Only successful integration results carry a key, snapshot, child owner or completed byte count.
  value.completed

proc verifiedOwner*(value: VerifiedDigest): IntegrationResult[OwnedFrame] =
  ## Obtain a retained immutable codec child; a default integration owner has no child.
  let data = value.data
  if data == nil: return IntegrationResult[OwnedFrame](status: IntegrationError.Owner) # No default child exists.
  IntegrationResult[OwnedFrame](status: IntegrationError.None, completed: data.owner)

proc wireLength*(value: VerifiedDigest): IntegrationResult[int] =
  ## Inspect exact serialized size without returning mutable snapshot bytes.
  let data = value.data
  if data == nil: return IntegrationResult[int](status: IntegrationError.Owner) # A retired/default handle has no wire.
  IntegrationResult[int](status: IntegrationError.None, completed: data.wire.len)

proc copyVerifiedWire*(value: VerifiedDigest, output: var openArray[byte]): IntegrationResult[int] =
  ## Copy a complete wire into caller-owned storage, preflighting capacity before any output mutation.
  let data = value.data
  if data == nil: return IntegrationResult[int](status: IntegrationError.Owner) # Never read a missing snapshot.
  if output.len < data.wire.len: return IntegrationResult[int](
      status: IntegrationError.Owner) # Failure is atomic.
  for i in 0..<data.wire.len: output[i] = data.wire[i] # Only caller storage is writable.
  IntegrationResult[int](status: IntegrationError.None, completed: data.wire.len)

proc fixtureKey*(bank: IntegrationBank, index: int): IntegrationResult[PreimageKey] =
  ## Select a copied fixed key only from a fully published bank and a valid fixture ordinal.
  let data = bank.data
  if data == nil or index < 0 or index >= 8: return IntegrationResult[PreimageKey](
      status: IntegrationError.Owner)
  IntegrationResult[PreimageKey](status: IntegrationError.None, completed: data.keys[index])

proc fixtureBytes*(bank: IntegrationBank, index: int): IntegrationResult[seq[byte]] =
  ## Extract a defensive wire copy for the fixture workload's intentional scratch overwrite.
  let data = bank.data
  if data == nil or index < 0 or index >= 8: return IntegrationResult[seq[byte]](
      status: IntegrationError.Owner)
  var copied = newSeq[byte](data.wires[index].len)
  for i in 0..<data.wires[index].len: copied[i] = data.wires[index][
      i] # No mutable bank backing storage is exported.
  IntegrationResult[seq[byte]](status: IntegrationError.None, completed: copied)

proc preimageKey*(input: openArray[byte]): IntegrationResult[PreimageKey] {.raises: [].} =
  ## Hash exact raw preimage bytes using the existing M2 adapter; no codec field is reinterpreted as a hash assertion.
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

proc loadBank*(bank: var IntegrationBank, directory: string): bool =
  ## Load only eight trusted bounded public fixtures before opening transport callbacks.
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

proc findFixture*(bank: IntegrationBank, key: openArray[byte]): int {.raises: [].} =
  ## Look up an exact fixed-width key; minus one never indexes bank storage.
  let data = bank.data
  if data == nil: return -1 # Default banks never select their all-zero placeholder keys.
  if key.len != 32: return -1 # No key truncation/padding.
  for index in 0..<data.keys.len:
    # Copy each fixed key before examining it, keeping no iterator borrow through the ref.
    let expected = data.keys[index]
    var matches = true
    for i, value in array[32, byte](expected):
      if key[i] != value: matches = false; break # Entire key equality selects the entry.
    if matches: return index
  -1

proc captureDigest*(input: var openArray[byte], expected: PreimageKey): IntegrationResult[
    VerifiedDigest] {.raises: [].} =
  ## Capture one complete digest, overwrite the borrowed receive/scratch bytes, then hash its owner's serialization.
  ## This actively proves that asynchronous consumers do not retain source-buffer coordinates or mutable aliases.
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

proc integrationSelfTest*() =
  ## Fuzz the composition boundary with bounded arbitrary wire and its actual independently retained request key.
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
