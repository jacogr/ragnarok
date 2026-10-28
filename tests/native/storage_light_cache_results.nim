# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic invalid/default light cache access probes retain successful empty-root controls under the same profile.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/storage/light_state_cache as storage_light_state_cache
import ../../src/storage/state_proof as storage_state_proof
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/bounded as codec_bounded
proc main() =
  ## Runtime arguments select invalid origins so compilation alone cannot stand in for checked refusal.
  let member = paramStr(1)
  let origin = paramStr(2)
  let policy = LightCacheLimits(items: ElementLimit(2), writes: ElementLimit(2),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(256)))
  let initial = newLightStateCache(default(StateRoot), policy)
  if member == "result":
    let initialized = initial.admit([LightStateProof(key: default(StateKey))]).value
    let selected = if origin == "default": default(LightCacheResult[VerifiedStateLookup])
      elif origin == "failed": initial.lookup(default(StateKey))
      else: initialized.lookup(default(StateKey))
    echo selected.value.kind # Unknown/default results cannot expose a verified lookup.
  elif member == "cache":
    let invalid = LightStateProof(key: default(StateKey), proof: StateProof(nodes: @[default(
        EncodedStateNode)]))
    let selected = if origin == "default": default(LightCacheResult[LightStateCache])
      elif origin == "failed": initial.admit([invalid])
      else: initial.admit([])
    echo selected.value.len # Failed/default batches cannot expose a cache snapshot.
  else:
    let selected = if origin == "default": default(LightStateCache) else: initial
    case member
    of "root": echo array[32, byte](selected.root)[0]
    of "len": echo selected.len
    of "values": echo selected.valueBytes
    of "limits": echo uint64(selected.limits.items)
    else: assert false, "unknown light cache probe"
main()
