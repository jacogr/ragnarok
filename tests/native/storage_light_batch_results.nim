# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic default/failed batch authority guards have complete independent successful native controls.
import std/assertions
import std/cmdline
import std/syncio
import std/posix/posix
import ../../src/storage/light_journal_cache as storage_light_journal_cache
import ../../src/storage/light_journal_replay as storage_light_journal_replay
import ../../src/storage/light_snapshot as storage_light_snapshot
import ../../src/storage/light_delta as storage_light_delta
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/storage/managed_io as storage_managed_io
import ../../src/storage/file_errors as storage_file_errors
import ../../src/storage/durability as storage_durability
import ../../src/codec/bounded as codec_bounded
proc processId(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Each positive control owns only one process-specific fixture namespace.
proc main() {.raises.} =
  ## Runtime arguments choose genuinely failed/default results before any successful fixture is constructed.
  let member = paramStr(1)
  let origin = paramStr(2)
  var owner = default(LightJournalCache)
  if member == "plan" and origin != "valid":
    let outcome = if origin == "default": default(LightJournalResult[PreparedLightJournalBatch])
      else: prepareLightJournalBatch(owner, [LightJournalEdit()])
    echo outcome.value.frameCount
    return
  if member == "receipt" and origin != "valid":
    let outcome = if origin == "default": default(LightJournalResult[StorageDurability])
      else: owner.append(default(PreparedLightJournalBatch))
    echo outcome.value
    return
  if origin == "default":
    # Each private-initialization contract must run before any candidate getter can observe a payload.
    let prepared = default(PreparedLightJournalBatch)
    if member == "count": echo prepared.frameCount
    elif member == "length": echo prepared.byteLength
    elif member == "sequence": echo uint64(prepared.sequence)
    else: echo prepared.snapshot.cache.len
    return
  let config = LightJournalConfig(snapshot: LightSnapshotLimits(bytes: ByteLimit(4096)),
    journal: LightReplayLimits(bytes: ByteLimit(4096), frames: ElementLimit(4),
        frame: LightDeltaLimits(bytes: ByteLimit(4096))))
  let image = prepareLightSnapshot(config.chain, config.root, [], config.snapshot).value
  var path = "build/storage-light-batch-guard-" & $processId()
  assert initializeLightJournalCache(owner, path, config, image).error == FileError.None
  let prepared = prepareLightJournalBatch(owner, [LightJournalEdit(), LightJournalEdit()]).value
  if member == "receipt": echo owner.append(prepared).value
  elif member == "length": echo prepared.byteLength
  elif member == "sequence": echo uint64(prepared.sequence)
  elif member == "snapshot": echo prepared.snapshot.cache.len
  else: echo prepared.frameCount
  assert owner.close == FileError.None
  for name in ["CURRENT", "snapshot-0000000000000001.bin", "journal-0000000000000001.wal", "LOCK"]:
    # Retire only exact owned positive-control files after releasing the native lease.
    var file = path & "/" & name
    assert posix.unlink(file.toCString()) == 0
  assert posix.rmdir(path.toCString()) == 0
try:
  main()
except:
  quit(2)
