# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## On-demand ancestry activation is positive, finite, download-only and atomically cleared on late failure.
import std/[assertions, syncio]
import ../../../src/app/options
proc main() =
  ## Parser boundaries remain independent of files, sockets, peers and storage startup.
  var selected = default(Options)
  assert selected.discoverDownloadAncestors == 0
  let base = @["download", "--with-state", "--chain", "chain.json"]
  assert parseCanonicalOptions(base, selected) and selected.discoverDownloadAncestors == 0
  for count in 1..MaxDownloadAncestors:
    var arguments = base
    arguments.add("--download-discover-ancestors")
    arguments.add($count)
    assert parseCanonicalOptions(arguments, selected) and selected.discoverDownloadAncestors == count
  for value in ["0", "00", "01", "65", "-1", "+1", "1.0", " 1", "1 ", "18446744073709551616", ""]:
    var arguments = base
    arguments.add("--download-discover-ancestors")
    arguments.add(value)
    assert not parseCanonicalOptions(arguments, selected)
    assert not selected.valid and selected.discoverDownloadAncestors ==
        0 # Failure cannot retain a previous valid activation.
  for suffix in [@["--download-discover-ancestors"], @["--download-discover-ancestors",
      "--with-rpc"], @["--download-discover-ancestors", "1", "--download-discover-ancestors", "2"],
      @["--download-discover-ancestors", "1", "--rpc-port", "1", "--rpc-port", "2"]]:
    var arguments = base
    for value in suffix: arguments.add(value) # Malformed or duplicate late controls clear every parsed field.
    assert not parseCanonicalOptions(arguments, selected) and selected.discoverDownloadAncestors == 0
  for command in ["server", "client", "mesh", "--help"]:
    assert not parseCanonicalOptions(@[command, "--with-state", "--chain", "chain.json",
      "--download-discover-ancestors", "1"], selected)
    assert selected.discoverDownloadAncestors == 0
  assert not parseCanonicalOptions(@["download", "--download-discover-ancestors", "1"], selected)
  assert parseCanonicalOptions(@["download", "--with-state", "--chain", "chain.json",
    "--download-local-ancestors", "--download-ancestor", "older", "--download-discover-ancestors",
    "2"], selected)
  assert selected.localDownloadAncestors and selected.ancestorPaths == @["older"]
  assert selected.discoverDownloadAncestors == 2
  assert parseCanonicalOptions(base, selected) and selected.discoverDownloadAncestors == 0
  for suffix in [@["--download-remote-ancestors", "1", "--download-discover-ancestors", "1"],
      @["--download-discover-ancestors", "1", "--download-remote-ancestors", "1"]]:
    var arguments = base
    for value in suffix: arguments.add(value) # Both spellings and orders must refuse atomically.
    assert not parseCanonicalOptions(arguments, selected)
    assert selected.discoverDownloadAncestors == 0 and selected.remoteDownloadAncestors == 0
  echo "PASS application discovery ancestor options: finite positive count, download-only and atomic activation"
main() # Ordinary assertions retain the native runner's failure status.
