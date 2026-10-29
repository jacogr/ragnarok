# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic selected-metadata guards have independent successful controls.
import std/[assertions, cmdline, syncio]
import ../../src/storage/light/journal/manifest as light_journal_manifest
import ../../src/storage/light/[snapshot as light_snapshot, delta as light_delta]
import ../../src/storage/managed/manifest as managed_manifest
import ../../src/storage/light/state_cache as light_state_cache
import ../../src/storage/[state_proof, database_identity]
import ../../src/codec/bounded
import ../../src/codec/state/trie as state_trie
proc main() =
  ## Dynamic command input keeps invalid accesses as real runtime guard probes.
  let member = paramStr(1)
  let origin = paramStr(2)
  let policy = LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(
      items: ElementLimit(4),
    writes: ElementLimit(4), proof: StateProofLimits(nodes: ElementLimit(249),
        valueBytes: ByteLimit(256))))
  let image = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy).value
  let complete = prepareLightJournalManifest(image, ManagedEpoch(1), LightDeltaSequence(0),
      ByteLimit(171))
  if member == "result":
    # Only the successful result can grant checked metadata.
    let outcome = if origin == "default": default(LightSelectionResult[LightJournalManifest])
      elif origin == "failed": prepareLightJournalManifest(image, ManagedEpoch(0),
          LightDeltaSequence(0), ByteLimit(171))
      else: complete
    echo uint64(outcome.value.epoch)
  else:
    # Every public metadata getter requires the private initialization authority.
    let selected = if origin == "default": default(LightJournalManifest) else: complete.value
    case member
    of "chain": echo array[32, byte](selected.chainId)[0]
    of "root": echo array[32, byte](selected.root)[0]
    of "epoch": echo uint64(selected.epoch)
    of "sequence": echo uint64(selected.baseSequence)
    of "image": echo array[32, byte](selected.snapshotChecksum)[0]
    of "checksum": echo array[32, byte](selected.checksum)[0]
    of "bytes": echo selected.bytes.len
    else: assert false, "unknown light selection probe"
main()
