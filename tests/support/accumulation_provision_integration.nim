# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored complete maps and retained implication contexts for union/fulfillment tests and result guards.
## Helpers use public preparation APIs; caller-selected contexts/posterior state are explicitly synthetic.

import ../../src/state/[accumulation_provisions, accumulation_effects, accumulation_context, store]
import ../../src/codec/[bounded, composite, state_accounts, state_requests, state_service_values,
  state_layout, state_trie]
import ../../src/crypto/primitives
import ./accumulation_effect_context

proc integrationPolicy*(contexts = 8'u64, items = 16'u64, perBlob = 16'u64,
    total = 128'u64, encoded = 512'u64): AccumulationProvisionUnionLimits =
  ## Keep independent context/traversal/copy/wire ceilings small and explicit.
  AccumulationProvisionUnionLimits(contexts: ElementLimit(contexts),
    values: PreimageLimits(items: ElementLimit(items), perBlob: ByteLimit(perBlob),
        totalBlobBytes: ByteLimit(total)),
    encodedBytes: ByteLimit(encoded))

proc integrationRequest*(service: uint32, bytes: seq[byte], history: seq[byte] = @[
    0'u8]): StateEntry =
  ## Derive a real canonical request key while permitting explicit posterior history alternatives.
  let digest = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
  StateEntry(key: serviceRequestKey(ServiceIndex(service), digest, RequestLength(uint32(bytes.len)),
      ByteLimit(32)).value,
    value: history)

proc integrationEntries*(): seq[StateEntry] =
  ## Posterior metadata deliberately differs from the contexts' credited source; fulfillment must preserve it exactly.
  result = @[serviceMetadataEntry(ServiceIndex(42), ServiceMetadata(balance: AccountBalance(123)),
      ByteLimit(ServiceMetadataBytes)).value,
    serviceMetadataEntry(ServiceIndex(99), ServiceMetadata(balance: AccountBalance(456)), ByteLimit(
        89)).value,
    StateEntry(key: chapterKey(StateChapter(250)), value: @[7'u8, 8]),
    serviceStorageEntry(ServiceIndex(42), @[1'u8], @[2'u8], ServiceEntryLimits(keyBytes: ByteLimit(
        1), valueBytes: ByteLimit(1))).value]
  for service in [42'u32, 99'u32]:
    for bytes in [newSeq[byte](0), @[2'u8], @[2'u8, 0], @[9'u8, 8, 7]]:
      result.add(integrationRequest(service, bytes)) # Independent canonical outstanding records cover every authored pair.

proc integrationStoreLimits*(writes = 100'u64, bytes = 100000'u64): StateStoreLimits =
  ## Complete-map store ceilings expose atomic write and byte-budget failures without partial-state shortcuts.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(100), perValue: ByteLimit(10000),
    totalValueBytes: ByteLimit(100000), nodes: TrieNodeLimit(10000)),
    writes: ElementLimit(writes), writeValueBytes: ByteLimit(bytes))

proc integrationContexts*(sameBytes = false): seq[AccumulationEffectContext] =
  ## A/B/A inspect eight contributions but union into four pairs and six bytes; original contexts remain immutable.
  var entries = @[serviceMetadataEntry(ServiceIndex(99), default(ServiceMetadata), ByteLimit(
      ServiceMetadataBytes)).value]
  for service in [42'u32, 99'u32]:
    for bytes in [newSeq[byte](0), @[2'u8], @[2'u8, 0], @[9'u8, 8, 7]]:
      entries.add(integrationRequest(service, bytes)) # Requests are validated when each source provision is recorded.
  let initial = prepareAccumulationEffects(preparedEffectContexts(entries)).value
  let limits = AccumulationProvisionLimits(items: ElementLimit(4), perBlob: ByteLimit(3),
      totalBlobBytes: ByteLimit(10))
  var first = initial
  for bytes in [newSeq[byte](0), @[2'u8], @[2'u8, 0]]:
    first = recordAccumulationProvision(first, ServiceIndex(42), bytes, limits).value
  let second = recordAccumulationProvision(recordAccumulationProvision(initial, ServiceIndex(42),
    @[2'u8], limits).value, ServiceIndex(99),
    (if sameBytes: @[2'u8] else: @[9'u8, 8, 7]), limits).value
  let a = first.effectContext(AccumulationDimension.Regular).value
  let b = second.effectContext(AccumulationDimension.Regular).value
  @[a, b, a]


proc integrationNumericContexts*(): seq[AccumulationEffectContext] =
  ## Targets 1/256 distinguish numeric service order from little-endian service transport order.
  var entries: seq[StateEntry] = @[]
  for service in [1'u32, 256'u32]:
    entries.add(serviceMetadataEntry(ServiceIndex(service), default(ServiceMetadata), ByteLimit(
        ServiceMetadataBytes)).value)
    entries.add(integrationRequest(service, @[2'u8])) # Both existing targets explicitly request the same bytes.
  let initial = prepareAccumulationEffects(preparedEffectContexts(entries)).value
  let limits = AccumulationProvisionLimits(items: ElementLimit(1), perBlob: ByteLimit(1),
      totalBlobBytes: ByteLimit(1))
  let upper = recordAccumulationProvision(initial, ServiceIndex(256), @[2'u8], limits).value
  let lower = recordAccumulationProvision(initial, ServiceIndex(1), @[2'u8], limits).value
  @[upper.effectContext(AccumulationDimension.Regular).value, lower.effectContext(
      AccumulationDimension.Regular).value]
