# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Remote ancestry activation is positive, finite, download-only and atomically cleared on late failure.
import std/[assertions, syncio]
import ../../../src/app/options
proc main() =
  ## Parser boundaries remain independent of files, sockets, peers and storage startup.
  var selected = default(Options)
  assert selected.remoteDownloadAncestors == 0
  let base = @["download", "--with-state", "--chain", "chain.json"]
  assert parseOptions(base, selected) and selected.remoteDownloadAncestors == 0
  for count in 1..MaxDownloadAncestors:
    var arguments = base
    arguments.add("--download-remote-ancestors")
    arguments.add($count)
    assert parseOptions(arguments, selected) and selected.remoteDownloadAncestors == count
  for value in ["0", "00", "01", "65", "-1", "+1", "1.0", " 1", "1 ", "18446744073709551616", ""]:
    var arguments = base
    arguments.add("--download-remote-ancestors")
    arguments.add(value)
    assert not parseOptions(arguments, selected)
    assert not selected.valid and selected.remoteDownloadAncestors ==
        0 # Failure cannot retain a previous valid activation.
  for suffix in [@["--download-remote-ancestors"], @["--download-remote-ancestors", "--with-rpc"],
      @["--download-remote-ancestors", "1", "--download-remote-ancestors", "2"],
      @["--download-remote-ancestors", "1", "--rpc-port", "1", "--rpc-port", "2"]]:
    var arguments = base
    for value in suffix: arguments.add(value) # Malformed or duplicate late controls clear every parsed field.
    assert not parseOptions(arguments, selected) and selected.remoteDownloadAncestors == 0
  for command in ["server", "client", "mesh", "--help"]:
    assert not parseOptions(@[command, "--with-state", "--chain", "chain.json",
      "--download-remote-ancestors", "1"], selected)
    assert selected.remoteDownloadAncestors == 0
  assert not parseOptions(@["download", "--download-remote-ancestors", "1"], selected)
  assert parseOptions(@["download", "--with-state", "--chain", "chain.json",
    "--download-local-ancestors", "--download-ancestor", "older", "--download-remote-ancestors",
    "2"], selected)
  assert selected.localDownloadAncestors and selected.ancestorPaths == @["older"]
  assert selected.remoteDownloadAncestors == 2
  assert parseOptions(base, selected) and selected.remoteDownloadAncestors == 0
  echo "PASS application remote ancestor options: finite positive count, download-only and atomic activation"
main() # Ordinary assertions retain the native runner's failure status.
