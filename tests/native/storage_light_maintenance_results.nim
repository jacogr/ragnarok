# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic missing maintenance authority guards have genuine idle-plan and confirmed no-op receipt controls.
import std/[assertions, cmdline, syncio]
import std/posix/posix
import ../../src/storage/[light_snapshot, light_journal_cache, light_journal_replay, light_delta,
  database_identity, managed_manifest, file_errors]
import ../../src/codec/[bounded, state_trie]
proc processId(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Controls use one exact process-owned fixture namespace.
proc main() {.raises.} =
  ## Select default/failed authority before constructing any successful source, then exercise every public plan payload getter.
  let member = paramStr(1)
  let origin = paramStr(2)
  var owner = default(LightJournalCache)
  if member == "result" and origin != "valid":
    let outcome = if origin == "default": default(LightJournalResult[PreparedLightMaintenance])
      else: prepareLightMaintenance(owner, ManagedEpoch(1), LightDeltaSequence(0), default(LightMaintenanceLimits))
    echo uint64(outcome.value.retiredCount)
    return
  if member == "receipt" and origin != "valid":
    let outcome = if origin == "default": default(LightJournalResult[LightMaintenanceReceipt])
      else: owner.maintain(default(PreparedLightMaintenance))
    echo uint64(outcome.value.retired)
    return
  if origin == "default":
    let prepared = default(PreparedLightMaintenance)
    if member == "compact": echo ord(prepared.compactionNeeded)
    elif member == "count": echo uint64(prepared.retiredCount)
    else: echo uint64(prepared.firstRetiredEpoch)
    return
  let path = "build/maintenance-guard-" & $processId()
  let policy = LightSnapshotLimits(bytes: ByteLimit(4096))
  let config = LightJournalConfig(snapshot: policy, journal: LightReplayLimits(bytes: ByteLimit(4096),
    frames: ElementLimit(4), frame: LightDeltaLimits(bytes: ByteLimit(4096))))
  let image = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy).value
  defer:
    if owner.opened: discard owner.close
    for name in ["CURRENT.next", "CURRENT", "LOCK", "snapshot-0000000000000001.bin",
        "journal-0000000000000001.wal"]:
      var child = path & "/" & name
      if posix.unlink(child.toCString()) != 0: assert posix.errno() == ENOENT
    var directory = path
    assert posix.rmdir(directory.toCString()) == 0
  assert initializeLightJournalCache(owner, path, config, image).error == FileError.None
  let prepared = prepareLightMaintenance(owner, ManagedEpoch(1), LightDeltaSequence(0), default(
      LightMaintenanceLimits)).value
  if member == "receipt": echo uint64(owner.maintain(prepared).value.retired)
  elif member == "compact": echo ord(prepared.compactionNeeded)
  elif member == "first": echo uint64(prepared.firstRetiredEpoch)
  else: echo uint64(prepared.retiredCount)
  assert owner.close == FileError.None
try:
  main()
except:
  quit(2)
