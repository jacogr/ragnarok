# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic light-file result and retirement guards require successful native builds and genuine positive controls.
import std/[assertions, cmdline, syncio]
import std/posix/posix
import ../../src/storage/[light_file_cache, light_snapshot, light_state_cache, database_identity,
  file_errors, durability]
import ../../src/codec/[bounded, state_trie]
proc processId(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Match the supported SDK pid_t ABI without assuming an unported stdlib export.
proc main() {.raises.} =
  ## Default/failed extraction and unclosed retirement fail only at the selected runtime contract.
  let member = paramStr(1)
  let origin = paramStr(2)
  var owner = default(LightFileCache)
  if member == "result" and origin != "valid":
    let selected = if origin == "default": default(LightFileResult[
        LightStateCache]) else: owner.snapshot
    echo selected.value.len
    return
  let config = LightFileConfig(limits: LightSnapshotLimits(bytes: ByteLimit(4096)))
  let prepared = prepareLightSnapshot(config.chain, config.root, [], config.limits).value
  var path = "build/storage-light-file-guard-" & $processId()
  let created = initializeLightFileCache(owner, path, config, prepared)
  assert created.error == FileError.None
  if member == "result": echo created.value
  if origin == "unclosed": return # Destruction must require explicit retirement of the live lock.
  assert owner.close == FileError.None
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
