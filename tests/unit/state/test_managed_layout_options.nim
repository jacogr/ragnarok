# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit managed layout and finite compaction thresholds preserve legacy defaults and atomic parser refusals.
import std/[assertions, syncio]
import ../../../src/app/options
import ../../../src/codec/bounded
proc main() =
  ## Omitted layout remains journal; managed policy is available only with an explicitly selected disk backend.
  let base = @["server", "--with-state", "--chain", "chain.json", "--state-storage", "disk",
      "--state-db", "state.db"]
  var selected = default(Options)
  assert parseOptions(base, selected) and selected.diskStorage and not selected.managedStorage
  var managed = base
  managed.add("--state-layout"); managed.add("managed")
  assert parseOptions(managed, selected) and selected.managedStorage
  assert uint64(selected.stateCompactionBytes) == 64'u64*1024*1024
  assert uint64(selected.stateWrites) == 1000 and uint64(selected.stateWriteBytes) == 100000
  for value in ["0", "1", "134217728"]:
    var arguments = managed
    arguments.add("--state-compact-bytes"); arguments.add(value)
    assert parseOptions(arguments, selected) and selected.managedStorage
    if value == "0": assert uint64(selected.stateCompactionBytes) == 0
  var paged = base
  paged.add("--state-layout"); paged.add("paged")
  assert parseOptions(paged, selected) and selected.pagedStorage and not selected.managedStorage
  for suffix in [@["--state-compact-bytes", "0"], @["--state-migrate-from", "legacy.db"]]:
    # A paged request cannot silently inherit managed maintenance or conversion controls.
    var arguments = paged
    for value in suffix: arguments.add(value)
    assert not parseOptions(arguments, selected) and not selected.valid and
        not selected.pagedStorage
  assert not parseOptions(@["server", "--with-state", "--chain", "chain.json", "--state-layout",
      "paged"], selected)
  var resumed = paged
  resumed.add("--state-paged-resume")
  assert parseOptions(resumed, selected) and selected.resumePagedStorage
  assert parseOptions(paged, selected) and not selected.resumePagedStorage
  for initial in [base, managed, @["server", "--with-state", "--chain", "chain.json"], @["server"]]:
    # Replay is explicit and paged-disk-only; every refusal clears the parsed owner.
    var arguments = initial
    arguments.add("--state-paged-resume")
    assert not parseOptions(arguments, selected) and not selected.valid
  resumed.add("--state-paged-resume")
  assert not parseOptions(resumed, selected) and not selected.valid # Duplicate explicit authority is rejected atomically.
  let invalid = @[@["--state-layout", "unknown"], @["--state-layout", "Managed"],
    @["--state-layout", "managed", "--state-layout", "managed"], @["--state-compact-bytes", "0"],
    @["--state-layout", "managed", "--state-compact-bytes", "134217729"],
    @["--state-layout", "managed", "--state-compact-bytes", "-1"],
    @["--state-layout", "managed", "--state-compact-bytes", "18446744073709551616"]]
  for suffix in invalid:
    var arguments = base
    for value in suffix: arguments.add(value)
    assert not parseOptions(arguments, selected) and not selected.valid and
        not selected.managedStorage
  assert not parseOptions(@["server", "--with-state", "--chain", "chain.json", "--state-layout",
      "managed"], selected)
  assert not parseOptions(@["server", "--state-layout", "managed"], selected)
main()
echo "PASS managed layout options: opt-in layout, finite threshold, explicit zero and atomic refusal"
