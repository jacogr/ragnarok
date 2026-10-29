# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic light-delta result/owner misuse requires real runtime contracts and independent success controls.
import std/[assertions, cmdline, syncio]
import ../../src/storage/light/[delta as light_delta, snapshot as light_snapshot,
    state_cache as light_state_cache]
import ../../src/storage/[state_proof, database_identity]
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, trie as state_trie]
proc main() =
  ## Dynamic origins keep default/failed extraction from becoming a compile-only rejection.
  let member = paramStr(1)
  let origin = paramStr(2)
  let policy = LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(
    items: ElementLimit(4), writes: ElementLimit(4),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(256))))
  let before = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy).value
  let bounds = LightDeltaLimits(items: ElementLimit(4), bytes: ByteLimit(4096))
  let complete = prepareLightDelta(before, LightDeltaSequence(1), [], [], bounds)
  if member == "result":
    let selected = if origin == "default": default(LightDeltaResult[PreparedLightDelta])
      elif origin == "failed": prepareLightDelta(before, LightDeltaSequence(0), [], [], bounds)
      else: complete
    echo selected.value.byteLength
  elif member == "reason":
    let selected = if origin == "default": default(LightDeltaResult[PreparedLightDelta])
      elif origin == "success": complete
      else: prepareLightDelta(before, LightDeltaSequence(1), [], [default(StateKey), default(
          StateKey)], bounds)
    echo selected.proofError
  else:
    let selected = if origin == "default": default(PreparedLightDelta) else: complete.value
    case member
    of "snapshot": echo selected.snapshot.cache.len
    of "sequence": echo uint64(selected.sequence)
    of "base": echo array[32, byte](selected.baseChecksum)[0]
    of "checksum": echo array[32, byte](selected.checksum)[0]
    of "length": echo selected.byteLength
    of "bytes": echo selected.bytes.len
    of "borrowed": echo selected.encodedBytes[0]
    else: assert false, "unknown light delta probe"
main()
