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
  if member == "select-result" or member == "select-reason":
    # Selective exports refuse whole images; no missing key or policy refusal authorizes a prepared prefix.
    let key = default(StateKey)
    let selected = if origin == "default": default(LightSnapshotResult[PreparedLightSnapshot])
      elif origin == "uninitialized": default(PreparedLightSnapshot).select([], policy,
          ElementLimit(0))
      elif origin == "unknown" or (member == "select-reason" and origin == "valid"):
        complete.value.select([key], policy, ElementLimit(0))
      elif origin == "limited": complete.value.select([], default(LightSnapshotLimits),
          ElementLimit(0))
      elif origin == "duplicate": complete.value.select([key, key], policy, ElementLimit(0))
      else: complete.value.select([], policy, ElementLimit(0))
    if member == "select-reason": echo selected.proofError
    else: echo selected.value.cache.len
    return
  if member == "cursor-finished" or member == "cursor-root":
    # Default traversal handles have neither a meaningful terminal position nor root binding.
    let selected = if origin == "default": default(
        LightProofCursor) else: complete.value.proofCursor.value
    if member == "cursor-finished": echo selected.finished
    else: echo array[32, byte](selected.root)[0]
    return
  if member == "page-len" or member == "page-proofs" or member == "page-next":
    # Only a completed page grants evidence or an image-bound continuation, including a terminal empty page.
    let valid = complete.value.proofCursor.value.readPage(default(LightProofPageLimits)).value
    let selected = if origin == "default": default(LightProofPage) else: valid
    if member == "page-len": echo selected.len
    elif member == "page-proofs": echo selected.proofs.len
    else: echo selected.nextCursor.finished
    return
  if member == "cursor-result":
    let selected = if origin == "default": default(LightSnapshotResult[LightProofCursor])
      elif origin == "failed": default(PreparedLightSnapshot).proofCursor
      else: complete.value.proofCursor
    echo selected.value.finished
    return
  if member == "page-result":
    let selected = if origin == "default": default(LightSnapshotResult[LightProofPage])
      elif origin == "failed": default(LightProofCursor).readPage(default(LightProofPageLimits))
      else: complete.value.proofCursor.value.readPage(default(LightProofPageLimits))
    echo selected.value.len
    return
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
