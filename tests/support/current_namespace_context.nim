# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit logical namespace declarations for genuine signed complete parents and untouched successors.
import std/assertions
import ./[service_namespace_seed, current_typed_context]
import ../../src/state/store
import ../../src/codec/state/[accounts as state_accounts, service_values as state_service_values,
    requests as state_requests, composition as state_composition]
import ../../src/crypto/primitives
proc namespaceSeeds*(): seq[ServiceNamespaceSeed] =
  ## Independent known contents include empty raw keys, present-empty values/preimages and available histories.
  result = @[]
  for id in [42'u32, 99'u32]:
    let payload = if id == 42: @[97'u8, 98, 99] else: @[77'u8]
    let empty = ServicePreimageHash(array[32, byte](blake2b256([]).value))
    let hash = ServicePreimageHash(array[32, byte](blake2b256(payload).value))
    let storage = if id == 42: @[StateStorageItem(key: @[], value: @[]), StateStorageItem(key: @[
        1'u8, 2], value: @[3'u8])]
      else: @[StateStorageItem(key: @[], value: @[4'u8]), StateStorageItem(key: @[5'u8], value: @[])]
    result.add(ServiceNamespaceSeed(service: ServiceIndex(id), storage: storage,
      preimages: @[StatePreimageItem(hash: empty, value: @[]), StatePreimageItem(hash: hash,
          value: payload)],
      requests: @[StateRequestItem(hash: empty, length: RequestLength(0), history: availableHistory(
          RequestSlot(1))),
        StateRequestItem(hash: hash, length: RequestLength(uint32(payload.len)),
            history: availableHistory(RequestSlot(1)))]))
proc currentNamespaceServices*(source: StateStoreSnapshot, seeds: openArray[
    ServiceNamespaceSeed]): seq[StateService] =
  ## Metadata comes from the actual original map; explicit raw identities are declarations that whole-map matching must verify.
  result = currentSuppliedServices(source)
  assert result.len == seeds.len
  for i in 0..<result.len:
    assert uint32(result[i].service) == uint32(seeds[i].service)
    result[i].storage = seeds[i].storage
    result[i].preimages = seeds[i].preimages
    result[i].requests = seeds[i].requests
