# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic recovery-result and unclosed-inspection guards require real native assertion diagnostics and valid retirement controls.
import std/assertions
import std/cmdline
import std/syncio
import std/posix/posix
import ../../src/storage/light_journal_cache as storage_light_journal_cache
import ../../src/storage/light_journal_replay as storage_light_journal_replay
import ../../src/storage/light_snapshot as storage_light_snapshot
import ../../src/storage/light_delta as storage_light_delta
import ../../src/storage/database_identity as storage_database_identity
import ../../src/storage/managed_io as storage_managed_io
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/storage/file_errors as storage_file_errors
import ../../src/codec/bounded as codec_bounded
proc processId(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## SDK pid_t keeps each process-owned native guard namespace independent.
proc main() {.raises.} =
  ## Dynamic origins keep result and lifecycle misuse as actual runtime guards.
  let member = paramStr(1)
  let origin = paramStr(2)
  var recovery = default(LightJournalRecovery)
  if member == "plan" and origin != "valid":
    # Default or failed extraction never grants a prefix extent.
    let outcome = if origin == "default": default(LightJournalResult[
        LightTailPlan]) else: recovery.plan
    echo outcome.value.prefix.byteLength
    return
  let config = LightJournalConfig(snapshot: LightSnapshotLimits(bytes: ByteLimit(4096)),
    journal: LightReplayLimits(bytes: ByteLimit(4096), frames: ElementLimit(4),
        frame: LightDeltaLimits(bytes: ByteLimit(4096))))
  let image = prepareLightSnapshot(config.chain, config.root, [], config.snapshot).value
  var path = "build/storage-light-recovery-guard-" & $processId()
  var owner = default(LightJournalCache)
  assert initializeLightJournalCache(owner, path, config, image).error == FileError.None
  assert owner.close == FileError.None
  let journal = path & "/" & managedFileName(ManagedFileKind.Journal, ManagedEpoch(1)).value
  writeFile(journal, readFile(journal) & "R")
  assert inspectLightJournalTail(recovery, path, config) == FileError.None
  if member == "plan": echo recovery.plan.value.prefix.byteLength
  if origin == "unclosed": return # Explicit close or successful repair transfer must retire this held native lease.
  assert recovery.close == FileError.None
  for name in ["CURRENT", "snapshot-0000000000000001.bin", "journal-0000000000000001.wal", "LOCK"]:
    # Only exact owned native guard children are retired after the inspection lease is closed.
    var file = path & "/" & name
    assert posix.unlink(file.toCString()) == 0
  assert posix.rmdir(path.toCString()) == 0
  if member == "retire": echo "closed"
try:
  main()
except:
  quit(2)
