# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic default/refused root-advance outcomes and private plans have independent successful storage controls.
import std/[assertions, cmdline, syncio]
import std/posix/posix
import ../../src/storage/[light_journal_cache, light_journal_replay, light_delta, light_snapshot,
  light_state_cache, database_identity, managed_manifest, file_errors]
import ../../src/codec/[bounded, state_layout, state_trie]
proc processId(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Each positive control owns only one process-specific known fixture namespace.
proc main() {.raises.} =
  ## Runtime inputs select failed/default authority before a valid destination fixture is constructed.
  let member = paramStr(1)
  let origin = paramStr(2)
  var owner = default(LightJournalCache)
  if member == "plan" and origin != "valid":
    let outcome = if origin == "default": default(LightJournalResult[PreparedLightRootAdvance])
      else: prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(0), default(
          StateRoot), default(PreparedLightSnapshot))
    echo uint64(outcome.value.epoch)
    return
  if member == "receipt" and origin != "valid":
    let outcome = if origin == "default": default(LightJournalResult[LightRootAdvanceReceipt])
      else: owner.advanceRoot(default(PreparedLightRootAdvance))
    echo uint64(outcome.value.sequence)
    return
  if origin == "default":
    # No payload getter may interpret a default plan as a selected root or prepared image.
    let prepared = default(PreparedLightRootAdvance)
    if member == "epoch": echo uint64(prepared.epoch)
    elif member == "sequence": echo uint64(prepared.sequence)
    elif member == "root": echo array[32, byte](prepared.root)[0]
    else: echo prepared.snapshot.cache.len
    return
  let limits = LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(
      items: ElementLimit(4),
    writes: ElementLimit(4), valueBytes: ByteLimit(64)))
  let oldRoot = default(StateRoot)
  let newRoot = stateTrieRoot([StateEntry(key: default(StateKey), value: @[1'u8])],
    StateTrieLimits(items: ElementLimit(1), nodes: TrieNodeLimit(1000), perValue: ByteLimit(64),
        totalValueBytes: ByteLimit(64))).value.root
  let config = LightJournalConfig(root: oldRoot, snapshot: limits, journal: LightReplayLimits(
    bytes: ByteLimit(4096), frames: ElementLimit(4), frame: LightDeltaLimits(items: ElementLimit(4),
        bytes: ByteLimit(4096))))
  let before = prepareLightSnapshot(config.chain, oldRoot, [], limits).value
  let image = prepareLightSnapshot(config.chain, newRoot, [], limits).value
  let path = "build/light-root-guard-" & $processId()
  defer:
    if owner.opened: discard owner.close
    for child in ["CURRENT.next", "CURRENT", "LOCK", "snapshot-0000000000000001.bin",
      "journal-0000000000000001.wal",
      "snapshot-0000000000000002.bin", "journal-0000000000000002.wal"]:
      var filename = path & "/" & child
      if posix.unlink(filename.toCString()) != 0: assert posix.errno() == ENOENT
    var directory = path
    assert posix.rmdir(directory.toCString()) == 0
  assert initializeLightJournalCache(owner, path, config, before).error == FileError.None
  let prepared = prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(0), newRoot, image).value
  if member == "receipt":
    let selected = owner.advanceRoot(prepared)
    echo uint64(selected.value.sequence)
  elif member == "plan" or member == "epoch": echo uint64(prepared.epoch)
  elif member == "sequence": echo uint64(prepared.sequence)
  elif member == "root": echo array[32, byte](prepared.root) == array[32, byte](newRoot)
  else: echo prepared.snapshot.cache.len
try:
  main()
except:
  quit(2)
