# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit local migration cannot be confused with layout inference, in-place conversion or checkpoint import intent.
import std/[assertions, syncio]
import ../../../src/app/options
proc main() =
  ## A distinct source and destination are both explicit; failed/default options grant no migration path.
  let base = @["server", "--with-state", "--chain", "chain.json", "--state-storage", "disk",
      "--state-db", "managed.db"]
  var selected = default(Options)
  assert parseOptions(base, selected) and not selected.stateMigration
  var managed = base
  managed.add("--state-layout"); managed.add("managed")
  var valid = managed
  valid.add("--state-migrate-from"); valid.add("legacy.db")
  assert parseOptions(valid, selected) and selected.managedStorage and selected.stateMigration
  assert selected.stateMigrationSource == "legacy.db" and selected.stateDatabase == "managed.db"
  let invalid = @[@["--state-migrate-from", "managed.db"],
    @["--state-migrate-from", "legacy.db", "--state-migrate-from", "other.db"],
    @["--state-migrate-from", ""], @["--state-migrate-from", "--state-db"],
    @["--state-migrate-from", "bad" & char(0) & "path"],
    @["--state-migrate-from", "legacy.db", "--state-checkpoint", "checkpoint", "--state-trust",
      "trust",
      "--state-header", "header", "--state-checkpoint-bytes", "10000"]]
  for suffix in invalid:
    var arguments = managed
    for value in suffix: arguments.add(value)
    assert not parseOptions(arguments, selected) and not selected.valid and
        not selected.stateMigration
  var journal = base
  journal.add("--state-migrate-from"); journal.add("legacy.db")
  assert not parseOptions(journal, selected) and not selected.stateMigration
  assert not parseOptions(@["server", "--with-state", "--chain", "chain.json", "--state-layout",
    "managed",
    "--state-migrate-from", "legacy.db"], selected)
main()
echo "PASS managed migration options: explicit distinct paths, managed-only intent, no import mixing and atomic refusal"
