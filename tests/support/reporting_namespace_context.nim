# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Qualify actual values at explicitly declared logical identities; unknown entries still fail exact-map inventory.
import std/assertions
import ./current_typed_context
import ../../src/state/store
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, accounts as state_accounts,
    service_values as state_service_values, requests as state_requests,
    composition as state_composition]
import ../../src/crypto/primitives

proc reportingServices*(source: StateStoreSnapshot): seq[StateService] =
  ## Service IDs/raw keys are authored declarations; actual metadata, code and histories retain their real owners.
  result = currentSuppliedServices(source)
  let histories = RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13))
  for index in 0..<result.len:
    let service = result[index].service
    let rawKeys: seq[seq[byte]] = if uint32(service) == 42: @[newSeq[byte](0), @[1'u8, 2], @[
        7'u8]] else: @[newSeq[byte](0), @[5'u8], @[7'u8]]
    for key in rawKeys:
      let entry = source.lookup(serviceStorageKey(service, key, ByteLimit(65)).value)
      if entry.error == StateStoreError.None:
        result[index].storage.add(StateStorageItem(key: key, value: entry.value.bytes))
    let payload = if uint32(service) == 42: @[97'u8, 98, 99] else: @[77'u8]
    let hashes = @[ServicePreimageHash(array[32, byte](blake2b256([]).value)),
      ServicePreimageHash(array[32, byte](blake2b256(payload).value)),
      ServicePreimageHash(array[32, byte](result[index].metadata.codeHash)),
      ServicePreimageHash(array[32, byte](blake2b256(if uint32(service) == 42: @[73'u8] else: @[
          81'u8]).value))]
    var seen: seq[array[32, byte]] = @[]
    for hash in hashes:
      var duplicate = false
      for prior in seen:
        if prior == array[32, byte](hash): duplicate = true
      if duplicate: continue # A declared code may itself be one of the original namespace payloads.
      seen.add(array[32, byte](hash))
      let entry = source.lookup(servicePreimageKey(service, hash, ByteLimit(32)).value)
      var length = 1'u32 # Explicit I/Q request-only payloads have one byte even before supply.
      if entry.error == StateStoreError.None:
        let bytes = entry.value.bytes
        length = uint32(bytes.len)
        result[index].preimages.add(StatePreimageItem(hash: hash, value: bytes))
      let request = source.lookup(serviceRequestKey(service, hash, RequestLength(length), ByteLimit(32)).value)
      if request.error == StateStoreError.None:
        let decoded = decodeRequestHistory(request.value.bytes, histories)
        assert decoded.error == RequestError.None and decoded.value.consumed ==
            request.value.bytes.len
        result[index].requests.add(StateRequestItem(hash: hash, length: RequestLength(length),
            history: decoded.value.history))
