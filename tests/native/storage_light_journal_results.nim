# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic light-journal result and retirement guards require successful native builds and genuine positive controls.
import std/assertions
import std/cmdline
import std/syncio
import std/posix/posix
import ../../src/storage/light_journal_cache as storage_light_journal_cache
import ../../src/storage/light_snapshot as storage_light_snapshot
import ../../src/storage/light_state_cache as storage_light_state_cache
import ../../src/storage/database_identity as storage_database_identity
import ../../src/storage/file_errors as storage_file_errors
import ../../src/storage/durability as storage_durability
import ../../src/storage/light_journal_replay as storage_light_journal_replay
import ../../src/storage/light_delta as storage_light_delta
import ../../src/storage/managed_io as storage_managed_io
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_trie as codec_state_trie
proc processId(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Match the supported SDK pid_t ABI without assuming an unported stdlib export.
proc main() {.raises.} =
  ## Default/failed extraction and unclosed retirement fail only at the selected runtime contract.
  let member = paramStr(1)
  let origin = paramStr(2)
  var owner = default(LightJournalCache)
  if member == "image" and origin != "valid":
    # A fresh prepared-image result carries no default or failed payload.
    let selected = if origin == "default": default(LightJournalResult[
        PreparedLightSnapshot]) else: owner.preparedSnapshot
    echo selected.value.byteLength
    return
  if member == "result" and origin != "valid":
    let selected = if origin == "default": default(LightJournalResult[
        LightStateCache]) else: owner.snapshot
    echo selected.value.len
    return
  let config = LightJournalConfig(snapshot: LightSnapshotLimits(bytes: ByteLimit(4096)),
      journal: LightReplayLimits(bytes: ByteLimit(4096), frames: ElementLimit(4),
      frame: LightDeltaLimits(bytes: ByteLimit(4096))))
  let prepared = prepareLightSnapshot(config.chain, config.root, [], config.snapshot).value
  var path = "build/storage-light-journal-guard-" & $processId()
  let created = initializeLightJournalCache(owner, path, config, prepared)
  assert created.error == FileError.None
  if member == "result": echo created.value
  if member == "image": echo owner.preparedSnapshot.value.byteLength
  if origin == "unclosed": return # Destruction must require explicit retirement of the live lock.
  assert owner.close == FileError.None
  for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
    # Retired native guard fixtures remove only their exact owned selected epoch files.
    var file = path & "/" & managedFileName(kind, ManagedEpoch(1)).value
    assert posix.unlink(file.toCString()) == 0
  var current = path & "/CURRENT"
  var lock = path & "/LOCK"
  assert posix.unlink(current.toCString()) == 0
  assert posix.unlink(lock.toCString()) == 0
  assert posix.rmdir(path.toCString()) == 0
  if member == "retire": echo "closed"
try:
  main()
except:
  quit(2) # IO exceptions remain failures; assertion defects retain their exact native diagnostics.
