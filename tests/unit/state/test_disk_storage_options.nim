# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Atomic backend parsing keeps explicit disk selection independent from state activation and import trust.
import std/[assertions, syncio]
import ../../../src/app/options
import ../../../src/codec/bounded
proc main() =
  ## Each failed/default parse clears prior successful disk/path ownership.
  let base = @["server", "--with-state", "--chain", "chain.json", "--state-writes", "1",
      "--state-write-bytes", "4"]
  var selected = default(Options)
  assert parseCanonicalOptions(base, selected) and not selected.diskStorage
  var disk = base
  disk.add("--state-storage"); disk.add("disk"); disk.add("--state-db"); disk.add("state.db")
  assert parseCanonicalOptions(disk, selected) and selected.diskStorage and
      selected.stateDatabase == "state.db"
  let defaults = @["server", "--with-state", "--chain", "chain.json", "--state-storage", "disk",
      "--state-db", "state.db"]
  assert parseCanonicalOptions(defaults, selected) and selected.diskStorage
  assert uint64(selected.stateWrites) == 1000 and uint64(selected.stateWriteBytes) == 100000
  let cases = @[
    @["--state-storage", "disk"], @["--state-db", "state.db"],
    @["--state-storage", "memory", "--state-db", "state.db"],
    @["--state-storage", "light"], @["--state-storage", "Disk", "--state-db", "state.db"],
    @["--state-storage", "disk", "--state-db", ""],
    @["--state-storage", "disk", "--state-db", "--with-rpc"],
    @["--state-storage", "disk", "--state-db", "a", "--state-db", "b"]]
  for suffix in cases:
    var arguments = base
    for value in suffix: arguments.add(value)
    assert not parseCanonicalOptions(arguments, selected)
    assert not selected.valid and not selected.diskStorage
  assert not parseCanonicalOptions(@["server", "--state-storage", "disk", "--state-db", "state.db"], selected)
  var memory = base
  memory.add("--state-storage"); memory.add("memory")
  assert parseCanonicalOptions(memory, selected) and not selected.diskStorage
  var imported = disk
  for value in ["--state-checkpoint", "checkpoint", "--state-trust", "trust", "--state-header",
      "header", "--state-checkpoint-bytes", "1024"]:
    imported.add(value) # Parsing preserves the independent complete external-trust request.
  assert parseCanonicalOptions(imported, selected) and selected.diskStorage and
      selected.recoveryEnabled
main()
echo "PASS disk storage options: explicit backend/path, atomic refusal and independent import controls"
