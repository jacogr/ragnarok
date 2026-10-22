# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent rooted sources reject substituted logical declarations in every complete service namespace.
import std/[assertions, envvars, strutils, syncio]
import ../../support/state_complete_serialization_context
import ../../../src/state/[checkpoint, store, manifest, global_snapshot, validated_checkpoint]
import ../../../src/codec/[bounded, assurances, state_consensus, state_layout, state_trie,
  state_composition, state_accounts, state_service_values, state_requests]
const
  profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6), previous: ValidatorCount(
      6), epochSlots: EpochSlots(2))
  mapLimits = StateTrieLimits(items: ElementLimit(64), nodes: TrieNodeLimit(4096),
      perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  limits = StateCheckpointLimits(checkpointBytes: ByteLimit(524288),
    store: StateStoreLimits(trie: mapLimits, writes: ElementLimit(64), writeValueBytes: ByteLimit(
        262144)),
    globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
        maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
    manifest: StateManifestLimits(services: ElementLimit(4), serialized: mapLimits,
        storageKeyBytes: ByteLimit(65)))
proc changed(input: seq[byte]): seq[byte] =
  ## Own a fresh same-extent mutation when possible; an empty value becomes a one-byte value.
  if input.len == 0: return @[byte(1)]
  result = newSeq[byte](input.len)
  for i in 0..<input.len: result[i] = input[i]
  result[0] = result[0] xor 1
proc other(hash: ServicePreimageHash): ServicePreimageHash =
  ## Copy the fixed identity before flipping one bit, independently of content or expected roots.
  var raw = array[32, byte](hash)
  raw[0] = raw[0] xor 1
  ServicePreimageHash(raw)
proc check(globals: ValidatedGlobalState, caseId, mode: int) =
  ## Change one logical fact while retaining an independently authenticated immutable complete source.
  var item = serializationService(caseId)
  case mode
  of 0: item.metadata.balance = AccountBalance(uint64(item.metadata.balance) xor 1)
  of 1: item.service = ServiceIndex(uint32(item.service) xor 1)
  of 2: item.storage = @[StateStorageItem(key: changed(item.storage[0].key), value: item.storage[0].value)]
  of 3: item.storage = @[StateStorageItem(key: item.storage[0].key, value: changed(item.storage[0].value))]
  of 4: item.preimages = @[StatePreimageItem(hash: other(item.preimages[0].hash),
      value: item.preimages[0].value)]
  of 5: item.preimages = @[StatePreimageItem(hash: item.preimages[0].hash, value: changed(
      item.preimages[0].value))]
  of 6: item.requests = @[StateRequestItem(hash: other(item.requests[0].hash),
      length: item.requests[0].length, history: item.requests[0].history)]
  of 7: item.requests = @[StateRequestItem(hash: item.requests[0].hash, length: RequestLength(
      uint32(item.requests[0].length)+1), history: item.requests[0].history)]
  of 8:
    let history = if caseId mod 4 == 0: availableHistory(RequestSlot(1)) else: requestedHistory()
    item.requests = @[StateRequestItem(hash: item.requests[0].hash, length: item.requests[0].length,
        history: history)]
  of 9: item.storage = @[]
  of 10: item.preimages = @[]
  of 11: item.requests = @[]
  else: discard # Remaining cases change descriptor count or supply explicitly opaque evidence.
  var services = @[item]
  if mode == 12: services = @[]
  elif mode == 13: services.add(serializationService(caseId+1))
  elif mode == 14: services.add(item)
  elif mode == 15:
    item.captured = @[default(ServiceValueSnapshot)]
    services = @[item]
  let refused = validateStateManifest(globals, services, limits.manifest)
  if mode == 14:
    assert refused.error == StateManifestError.CompositionFailure
    assert refused.compositionError == StateCompositionError.DuplicateKey
  elif mode == 15:
    assert refused.error == StateManifestError.OpaqueValues
  else:
    assert refused.error == StateManifestError.MappingMismatch
proc main() {.raises.} =
  ## Cover eight source shapes, full-width fields, every history mode and all namespace substitutions.
  var row = 0
  for line in readFile(getEnv("RAGNAROK_COMPLETE_SERIALIZATION")).splitLines():
    if line.len == 0: continue # The SHA-pinned transport ends in a newline.
    if row < 8:
      let input = serializationOctets(line)
      var root = default(array[32, byte])
      for i in 0..<32: root[i] = input[25+i]
      let completed = decodeValidatedCheckpoint(input, StateRoot(root), @[serializationService(
          row)], profile, limits)
      assert completed.error == ValidatedCheckpointError.None
      let source = completed.value
      let globals = source.manifestGlobals.value
      for mode in 0..<16: check(globals, row, mode)
      assert encodeFullCheckpoint(source.manifestSource.value, limits.checkpointBytes).value == input
    inc row
  assert row == 32
  echo "state-manifest-substitutions: ok (128 cases)"
try:
  main()
except:
  quit(2) # Source/setup errors cannot satisfy a substitution refusal.
