# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit Services migration preserves a validated local legacy head and leaves both source bytes and existing targets untouched.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../support/managed_storage_samples
import ../../../src/app/[services, options]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/store
import ../../../src/storage/managed/manifest as managed_manifest
proc configured(path, layout, source: string): Options =
  ## Source selection is an explicit local migration intention, independent of normal restart and external import.
  var arguments = @["server", "--with-state", "--chain", getEnv("RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-storage", "disk", "--state-db", path, "--state-layout", layout]
  if source.len > 0:
    arguments.add("--state-migrate-from"); arguments.add(source)
  result = default(Options)
  assert parseCanonicalOptions(arguments, result)
proc main() {.raises.} =
  ## Copy creates a fresh managed directory; subsequent ordinary restart uses its own admitted local head.
  var sourcePath = "managed-services-migration-source.wal"
  let path = "managed-services-migration-target"
  var origin = default(Services)
  var target = default(Services)
  defer:
    target.close()
    origin.close()
  assert origin.start(configured(sourcePath, "journal", ""), "legacy source")
  let before = origin.stateSnapshot.value
  let expected = origin.chainView.bestBlock.value
  origin.close()
  let original = readFile(sourcePath)
  assert target.start(configured(path, "managed", sourcePath), "explicit migration")
  assert array[32, byte](target.chainView.bestBlock.value.blockHash) == array[32, byte](
      expected.blockHash)
  assert target.chainView.retainedCount == 1 and target.chainView.finalizedBlock.error ==
      GenesisError.Unavailable
  assert readFile(sourcePath) == original
  target.close()
  let current = readFile(path & "/CURRENT")
  assert not target.start(configured(path, "managed", sourcePath), "existing destination")
  target.close()
  assert readFile(sourcePath) == original and readFile(path & "/CURRENT") == current
  assert target.start(configured(path, "managed", ""), "normal managed restart")
  for index in 0..<before.commitment.entries:
    let key = before.keyAt(StateEntryIndex(index)).value
    assert target.stateSnapshot.value.lookup(key).value.bytes == before.lookup(key).value.bytes
  target.close()
  var corrupt = original
  corrupt[corrupt.high] = char(ord(corrupt[corrupt.high]) xor 1)
  writeFile(sourcePath, corrupt)
  assert not target.start(configured(path & "-refused", "managed", sourcePath), "corrupt source")
  target.close()
  assert readFile(sourcePath) == corrupt
  writeFile(sourcePath, original)
  assert origin.start(configured(sourcePath, "journal", ""), "source still independent")
  assert array[32, byte](origin.stateSnapshot.value.commitment.root) == array[32, byte](
      before.commitment.root)
  origin.close()
  assert posix.unlink(sourcePath.toCString()) == 0
  removeManagedSample(path, [ManagedEpoch(1)])
try:
  main()
except:
  quit(2)
echo "PASS managed Services migration: explicit local source, unchanged bytes, independent restart and no overwrite/fallback"
