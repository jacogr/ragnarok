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
  if member == "batch" or member == "batch-reason":
    # Dynamic batch outcomes require a guarded complete sequence and a separately selected proof reason.
    let key = default(StateKey)
    let absent = LightStateProof(key: key)
    let retained = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [absent], policy).value
    let bounds = LightProofBatchLimits(queries: ElementLimit(2), entries: ElementLimit(1))
    let selected = if origin == "default": default(LightSnapshotResult[seq[LightStateProof]])
      elif origin == "uninitialized": default(PreparedLightSnapshot).prove([key], bounds)
      elif origin == "unknown": complete.value.prove([key], bounds)
      elif origin == "limited": retained.prove([key], default(LightProofBatchLimits))
      elif origin == "duplicate" or (member == "batch-reason" and origin == "valid"):
        retained.prove([key, key], bounds)
      else: retained.prove([key], bounds)
    if member == "batch-reason": echo selected.proofError
    else: echo selected.value.len
    return
  if member == "proof":
    # Dynamic outcomes instantiate the detached proof result guard for every refusal class.
    let absent = LightStateProof(key: default(StateKey))
    let retained = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [absent], policy).value
    let bounds = LightProofReadLimits(entries: ElementLimit(1))
    let selected = if origin == "default": default(LightSnapshotResult[StateProof])
      elif origin == "uninitialized": default(PreparedLightSnapshot).prove(default(StateKey), bounds)
      elif origin == "unknown": complete.value.prove(default(StateKey), bounds)
      elif origin == "limited": retained.prove(default(StateKey), default(LightProofReadLimits))
      else: retained.prove(default(StateKey), bounds)
    echo selected.value.nodes.len
    return
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
