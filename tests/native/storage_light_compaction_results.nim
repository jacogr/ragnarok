# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic compaction result and candidate guards require complete native positive controls.
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
import ../../src/codec/bounded as codec_bounded
proc processId(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Guard fixtures own one process-specific namespace.
proc main() {.raises.} =
  ## Dynamic selected alternatives exercise real default/failed and uninitialized candidate contracts.
  let member = paramStr(1)
  let origin = paramStr(2)
  var owner = default(LightJournalCache)
  if member == "plan" and origin != "valid":
    # A default or failed preparation never grants an opaque replacement plan.
    let outcome = if origin == "default": default(LightJournalResult[PreparedLightCompaction])
      else: prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(0))
    echo uint64(outcome.value.epoch)
    return
  if member == "receipt" and origin != "valid":
    # Passive receipt metadata belongs only to a confirmed successful result.
    let outcome = if origin == "default": default(LightJournalResult[LightCompactionReceipt])
      else: owner.compact(default(PreparedLightCompaction))
    echo uint64(outcome.value.epoch)
    return
  if origin == "default":
    # Neither candidate scalar getter can inspect a default opaque handle.
    let prepared = default(PreparedLightCompaction)
    if member == "epoch": echo uint64(prepared.epoch)
    else: echo uint64(prepared.sequence)
    return
  let config = LightJournalConfig(snapshot: LightSnapshotLimits(bytes: ByteLimit(4096)),
    journal: LightReplayLimits(bytes: ByteLimit(4096), frames: ElementLimit(4),
        frame: LightDeltaLimits(bytes: ByteLimit(4096))))
  let image = prepareLightSnapshot(config.chain, config.root, [], config.snapshot).value
  var path = "build/storage-light-compaction-guard-" & $processId()
  assert initializeLightJournalCache(owner, path, config, image).error == FileError.None
  let prepared = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(0)).value
  if member == "receipt": echo uint64(owner.compact(prepared).value.epoch)
  elif member == "sequence": echo uint64(prepared.sequence)
  else: echo uint64(prepared.epoch)
  assert owner.close == FileError.None
  for epoch in [ManagedEpoch(1), ManagedEpoch(2)]:
    # Successful guard controls retire only their exact known epoch children after closing the lease.
    for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
      var file = path & "/" & managedFileName(kind, epoch).value
      let removed = posix.unlink(file.toCString())
      if removed != 0: assert posix.errno() == ENOENT
  for name in ["CURRENT", "LOCK"]:
    var file = path & "/" & name
    assert posix.unlink(file.toCString()) == 0
  assert posix.rmdir(path.toCString()) == 0
try:
  main()
except:
  quit(2)
