# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit node/backend selection never converts incomplete light authority into full checkpoint recovery.
import std/[assertions, syncio]
import ../../../src/app/options
proc main() =
  ## Atomic refusals clear all formerly successful mode/path authority.
  let base = @["server", "--with-state", "--chain", "chain.json", "--node-mode", "light",
    "--state-trust", "trust", "--state-header", "header"]
  var selected = default(Options)
  assert parseCanonicalOptions(base, selected) and selected.lightMode and not selected.diskStorage
  assert selected.lightTrustPath == "trust" and selected.lightHeaderPath == "header"
  assert not selected.recoveryEnabled
  var disk = base
  for value in ["--state-storage", "disk", "--state-db", "light.db", "--state-layout", "paged"]:
    disk.add(value) # Disk ownership requires both explicit backend and explicit paged schema.
  assert parseCanonicalOptions(disk, selected) and selected.lightMode and selected.diskStorage and
      selected.pagedStorage
  for suffix in [@["--state-writes", "0"], @["--state-write-bytes", "0"],
      @["--state-checkpoint", "checkpoint"], @["--state-checkpoint-bytes", "1000"],
      @["--state-paged-resume"], @["--state-storage", "disk", "--state-db", "light.db"],
      @["--state-storage", "disk", "--state-db", "light.db", "--state-layout", "journal"],
      @["--state-layout", "paged"]]:
    var arguments = base
    for value in suffix: arguments.add(value) # Every unsupported full-state control refuses as one whole request.
    assert not parseCanonicalOptions(arguments, selected) and not selected.valid and
        not selected.lightMode
  for arguments in [@["server", "--node-mode", "light"],
      @["server", "--with-state", "--chain", "chain.json", "--node-mode", "light", "--state-trust",
          "trust"],
      @["server", "--with-state", "--chain", "chain.json", "--node-mode", "Light"],
      @["server", "--node-mode", "light", "--node-mode", "full"]]:
    assert not parseCanonicalOptions(arguments, selected) and
        not selected.valid # No implicit trust or case-insensitive fallback.
  var download = base
  download[0] = "download"
  assert not parseCanonicalOptions(download, selected)
  assert parseCanonicalOptions(@["server"], selected) and selected.nodeMode == NodeMode.Full
  assert parseCanonicalOptions(@["server", "--node-mode", "full"], selected) and
      not selected.lightMode
main()
echo "light runtime options: ok"
