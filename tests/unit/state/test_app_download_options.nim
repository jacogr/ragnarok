# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A finite positive download count remains atomic, command-specific and independent of storage or ancestry.
import std/assertions
import std/syncio
import ../../../src/app/options as app_options
proc main() =
  ## Every explicit count is parsed before IO; invalid reparses must erase previous usable requests.
  var selected = default(Options)
  assert selected.downloadBlocks == 0
  let base = @["download", "--with-state", "--chain", "chain.json"]
  assert parseCanonicalOptions(base, selected) and selected.downloadBlocks == 1
  for count in 1..MaxDownloadBlocks:
    var arguments = base
    arguments.add("--download-blocks")
    arguments.add($count)
    assert parseCanonicalOptions(arguments, selected) and selected.downloadBlocks ==
        count # Every admitted count has the exact requested value.
  for value in ["", "0", "00", "01", "65", "-1", "+1", "1 ", "1x", "18446744073709551615",
      "18446744073709551616", "--with-rpc"]:
    var arguments = base
    arguments.add("--download-blocks")
    arguments.add(value)
    assert not parseCanonicalOptions(arguments, selected)
    assert not selected.valid and selected.downloadBlocks == 0 # No partial count survives an invalid suffix.
  assert not parseCanonicalOptions(@["download", "--with-state", "--chain", "chain.json",
      "--download-blocks"], selected)
  assert not parseCanonicalOptions(@["download", "--with-state", "--chain", "chain.json",
    "--download-blocks",
    "2", "--download-blocks", "3"], selected)
  for command in ["server", "client", "mesh", "--help"]:
    assert not parseCanonicalOptions(@[command, "--with-state", "--chain", "chain.json",
      "--download-blocks",
      "2"], selected) # Other command lifecycles cannot ignore a finite import request.
  assert not parseCanonicalOptions(@["download", "--download-blocks", "2"], selected)
  assert parseCanonicalOptions(@["download", "--with-state", "--chain", "chain.json",
    "--state-storage", "disk",
    "--state-db", "local.db", "--download-blocks", "2", "--download-ancestor", "older.bin"], selected)
  assert selected.diskStorage and selected.downloadBlocks == 2 and selected.ancestorPaths == @["older.bin"]
  assert parseCanonicalOptions(base, selected) and selected.downloadBlocks == 1
  echo "PASS application download options: finite exact counts, default one and atomic command-specific refusal"
main() # Ordinary assertion failures remain native test failures.
