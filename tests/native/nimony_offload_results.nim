# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and actually empty completion polls must not expose a fabricated generation or
## verdict.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
import "../../src/jamnp-s/offload"

# Exercise one rejected completion read per child process, after retiring any worker-created native owners.
proc main() {.raises.} =
  let args = commandLineParams()
  assert args.len == 1
  var checked = default(OffloadPollResult)
  if args[0] == "empty":
    # Enabled polls own a live mutex; disabled polls have no worker resource to initialize.
    var pool = default(OffloadPool)
    when OffloadEnabled:
      assert startPool(pool)
      checked = collectPool(pool)
      stopPool(pool)
    else:
      checked = collectPool(pool)
  echo uint64(checked.completion.id) # Both alternatives must stop at the success precondition.

# Trusted fixture/CLI errors are distinct from the contract assertion expected by the runner.
try:
  main()
except:
  quit(2)
