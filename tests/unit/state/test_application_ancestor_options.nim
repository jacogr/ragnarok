# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Repeatable ancestry paths remain bounded, download-only, ordered and atomic on every refusal.
import std/[assertions, syncio]
import ../../../src/app/options
proc main() =
  ## Parser tests need no files or native services; invalid paths cannot trigger IO during parsing.
  var selected = default(Options)
  assert selected.ancestorPaths.len == 0
  let base = @["download", "--with-state", "--chain", "chain.json"]
  assert parseOptions(base, selected) and selected.ancestorPaths.len == 0
  var arguments = base
  for index in 0..<MaxDownloadAncestors:
    arguments.add("--download-ancestor")
    arguments.add("header-" & $index)
    assert parseOptions(arguments, selected)
    assert selected.ancestorPaths.len == index + 1
    assert selected.ancestorPaths[index] == "header-" &
        $index # Repeated controls preserve exact newest-first order.
  var copied = selected.ancestorPaths
  copied[0] = "changed"
  assert selected.ancestorPaths[0] == "header-0"
  arguments.add("--download-ancestor")
  arguments.add("overflow")
  assert not parseOptions(arguments, selected) and selected.ancestorPaths.len == 0
  for suffix in [@["--download-ancestor"], @["--download-ancestor", ""],
      @["--download-ancestor", "--with-rpc"], @["--download-ancestor", "x" & char(0) & "y"],
      @["--download-ancestor", "same", "--download-ancestor", "same"],
      @["--download-ancestor", "one", "--rpc-port", "1", "--rpc-port", "2"]]:
    arguments = base
    for value in suffix: arguments.add(value) # Each malformed late control must clear a previous successful parse.
    assert not parseOptions(arguments, selected)
    assert not selected.valid and selected.ancestorPaths.len == 0
  for command in ["server", "client", "mesh", "--help"]:
    assert not parseOptions(@[command, "--with-state", "--chain", "chain.json",
      "--download-ancestor", "older"], selected) # No unrelated command silently drops supplied ancestors.
    assert not selected.valid and selected.ancestorPaths.len == 0
  assert not parseOptions(@["download", "--download-ancestor", "older"], selected)
  assert parseOptions(@["download", "--with-state", "--chain", "chain.json", "--state-storage",
    "disk", "--state-db", "local.db", "--download-ancestor", "newest",
    "--download-ancestor", "older"], selected)
  assert selected.diskStorage and selected.ancestorPaths == @["newest", "older"]
  assert parseOptions(base, selected) and selected.ancestorPaths.len == 0
  assert not selected.localDownloadAncestors
  var localArgs = base
  localArgs.add("--download-local-ancestors")
  assert parseOptions(localArgs, selected) and selected.localDownloadAncestors
  localArgs.add("--download-local-ancestors")
  assert not parseOptions(localArgs, selected) and not selected.localDownloadAncestors
  for command in ["server", "client", "mesh", "--help"]:
    assert not parseOptions(@[command, "--with-state", "--chain", "chain.json",
        "--download-local-ancestors"], selected)
    assert not selected.valid and not selected.localDownloadAncestors
  assert not parseOptions(@["download", "--download-local-ancestors"], selected)
  assert parseOptions(base, selected) and not selected.localDownloadAncestors
  echo "PASS application ancestor options: bounded ordered paths, download-only activation and atomic refusal"
main() # Assertion failures retain the native runner's ordinary verdict.
