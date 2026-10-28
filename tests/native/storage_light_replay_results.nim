# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic replay and explicit-tail-plan probes require real runtime guards with successful controls.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/storage/light_journal_replay as storage_light_journal_replay
import ../../src/storage/light_journal_manifest as storage_light_journal_manifest
import ../../src/storage/light_delta as storage_light_delta
import ../../src/storage/light_snapshot as storage_light_snapshot
import ../../src/storage/light_state_cache as storage_light_state_cache
import ../../src/storage/state_proof as storage_state_proof
import ../../src/storage/database_identity as storage_database_identity
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_trie as codec_state_trie
proc main() =
  ## Dynamic origins select default, failed and complete alternatives without compile-time guard folding.
  let member = paramStr(1)
  let origin = paramStr(2)
  let policy = LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(
      items: ElementLimit(4),
    writes: ElementLimit(4), proof: StateProofLimits(nodes: ElementLimit(249),
        valueBytes: ByteLimit(256))))
  let image = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy).value
  let manifest = prepareLightJournalManifest(image, ManagedEpoch(1), LightDeltaSequence(0),
      ByteLimit(171)).value
  let anchor = encodeLightJournalAnchor(manifest, ByteLimit(98)).value
  let limits = LightReplayLimits(bytes: ByteLimit(4096), frames: ElementLimit(4),
      frame: LightDeltaLimits(items: ElementLimit(4), bytes: ByteLimit(1024)))
  let complete = replayLightJournal(anchor, manifest, image, limits)
  if member == "result" or member == "delta" or member == "reason":
    # Nested causes and completed data each belong to only one private selected alternative.
    var invalid = anchor
    invalid.add(0)
    var invalidAnchor = anchor
    invalidAnchor[0] = 0
    let outcome = if origin == "default": default(LightReplayResult[LightJournalReplay])
      elif origin == "failed": replayLightJournal([], manifest, image, limits)
      elif origin == "cause" and member == "delta": replayLightJournal(invalid, manifest, image, limits)
      elif origin == "cause": replayLightJournal(invalidAnchor, manifest, image, limits)
      else: complete
    case member
    of "result": echo outcome.value.byteLength
    of "delta": echo outcome.deltaError
    else: echo outcome.selectionError
  elif member == "prefix" or member == "total" or member == "selection":
    # A one-byte matching frame prefix creates the smallest explicit nonempty-tail plan.
    var partial = anchor
    partial.add(byte('R'))
    let selected = if origin == "default": default(LightTailPlan)
      else: planLightJournalTail(partial, manifest, image, limits).value
    case member
    of "prefix": echo selected.prefix.frameCount
    of "total": echo selected.totalBytes
    of "selection": echo array[32, byte](selected.selectionChecksum)[0]
    else: assert false, "unknown plan probe"
  else:
    # Default progress never grants an image, count, sequence or truncation extent.
    let selected = if origin == "default": default(LightJournalReplay) else: complete.value
    case member
    of "snapshot": echo selected.snapshot.cache.len
    of "sequence": echo uint64(selected.sequence)
    of "count": echo selected.frameCount
    of "length": echo selected.byteLength
    else: assert false, "unknown replay probe"
main()
