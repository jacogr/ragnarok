# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic light snapshot misuse probes preserve successful immutable-image and selected-proof-failure controls.
import std/[assertions, cmdline, syncio]
import ../../src/storage/[light_snapshot, light_state_cache, state_proof, database_identity]
import ../../src/codec/[bounded, state_layout, state_trie]
proc main() =
  ## Dynamic origin arguments require actual runtime guards after the whole driver builds successfully.
  let member = paramStr(1)
  let origin = paramStr(2)
  let policy = LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(
    items: ElementLimit(8), proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(256))))
  let complete = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy)
  assert complete.error == LightSnapshotError.None
  if member == "result":
    let selected = if origin == "default": default(LightSnapshotResult[PreparedLightSnapshot])
      elif origin == "failed": prepareLightSnapshot(default(StorageChainId), default(StateRoot), [],
          default(LightSnapshotLimits))
      else: complete
    echo selected.value.cache.len
  elif member == "reason":
    let repeated = LightStateProof(key: default(StateKey))
    let selected = if origin == "default": default(LightSnapshotResult[PreparedLightSnapshot])
      elif origin == "success": complete
      else: prepareLightSnapshot(default(StorageChainId), default(StateRoot), [repeated, repeated], policy)
    echo selected.proofError # Only a selected ProofFailure owns this reason.
  else:
    let selected = if origin == "default": default(PreparedLightSnapshot) else: complete.value
    case member
    of "chain": echo array[32, byte](selected.chainId)[0]
    of "root": echo array[32, byte](selected.root)[0]
    of "limits": echo uint64(selected.limits.bytes)
    of "cache": echo selected.cache.len
    of "checksum": echo array[32, byte](selected.checksum)[0]
    of "borrowed": echo selected.encodedBytes[0]
    of "bytes": echo selected.bytes.len
    of "length": echo selected.byteLength
    else: assert false, "unknown light snapshot probe"
main()
