# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Logical corpus inputs shared by single/multi-service tests; expected bytes come only from Python fixtures.
import std/[assertions, parseutils]
import ../../src/crypto/primitives
import ../../src/codec/state/[composition as state_composition, accounts as state_accounts,
    service_values as state_service_values, requests as state_requests]
const sizes = [0, 1, 31, 32, 33, 63, 64, 65]
proc serializationWord*(caseId, field, bits: int): uint64 =
  ## Fingerprint logical inputs without encoding them; zero/all-ones exercise unsigned domains.
  if caseId mod 8 == 0: return 0
  if caseId mod 8 == 1:
    if bits == 32: return uint64(high(uint32))
    return high(uint64)
  (uint64(caseId) shl (bits-8)) or (uint64(field) shl (bits-16)) or 0x0102'u64
proc serializationOctets*(text: string): seq[byte] =
  ## Decode only the pinned fixture's complete hex octets; malformed setup cannot qualify a case.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var octet: byte = 0
    assert parseHex(text[2*i..2*i+1], octet) == 2
    result[i] = octet
proc serializationPattern(size, seed: int): seq[byte] =
  ## Author raw storage and preimage inputs across inline/hash and block-size boundaries.
  result = newSeq[byte](size)
  for i in 0..<size: result[i] = byte((seed+i) mod 256)
proc serializationService*(caseId: int): StateService =
  ## Construct every logical field independently of the expected serialized metadata/map bytes.
  let rawKey = serializationPattern(sizes[caseId mod 8], caseId)
  let stored = serializationPattern(sizes[(caseId+2) mod 8], 3*caseId)
  let payload = serializationPattern(sizes[(caseId+4) mod 8], 7*caseId)
  # Hash only the logical input payload; complete expected keys and roots come from Python.
  var identity = default(array[32, byte])
  let contentHash = blake2b256(payload)
  assert contentHash.error == CryptoError.None
  identity = array[32, byte](contentHash.value)
  var code = default(array[32, byte])
  for i in 0..<32: code[i] = byte(i)
  let metadata = ServiceMetadata(codeHash: CodeHash(code),
    balance: AccountBalance(serializationWord(caseId, 1, 64)), supervisorBalance: AccountBalance(
        serializationWord(caseId, 2, 64)),
    minimumAccumulationGas: Gas(serializationWord(caseId, 3, 64)), minimumTransferGas: Gas(
        serializationWord(caseId, 4, 64)),
    storageBytes: AccountStorageBytes(uint64(115+rawKey.len+stored.len+payload.len)),
    depositOffset: AccountBalance(serializationWord(caseId, 6, 64)),
        storageItems: AccountStorageItems(3),
    created: AccountSlot(uint32(serializationWord(caseId, 2, 32))), lastAccumulation: AccountSlot(
        uint32(serializationWord(caseId, 3, 32))),
    parent: ServiceIndex(uint32(serializationWord(caseId, 4, 32))), supervisor: ServiceIndex(uint32(
        serializationWord(caseId, 5, 32))),
    supervisorCreated: AccountSlot(uint32(serializationWord(caseId, 6, 32))))
  let id = [0'u32, high(uint32), 0x01020304'u32, 256'u32][caseId mod 4]
  var history = requestedHistory()
  case caseId mod 4
  of 1: history = availableHistory(RequestSlot(1))
  of 2: history = unavailableHistory(RequestSlot(1), RequestSlot(2))
  of 3: history = reavailableHistory(RequestSlot(1), RequestSlot(2), RequestSlot(3))
  else: discard # The empty requested mode remains a real serialized key/value entry.
  StateService(service: ServiceIndex(id), metadata: metadata,
    storage: @[StateStorageItem(key: rawKey, value: stored)],
    preimages: @[StatePreimageItem(hash: ServicePreimageHash(identity), value: payload)],
    requests: @[StateRequestItem(hash: ServicePreimageHash(identity), length: RequestLength(uint32(
        payload.len)), history: history)])
