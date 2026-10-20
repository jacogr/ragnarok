# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service parent relocation and forgotten export shutdown enforce actual native child lifetimes.
import std/[assertions, cmdline, syncio]
import ../../src/app/[services, options, checkpoint_file]
proc started(): Options =
  ## No listeners, chain or fixtures are needed to test a genuine stable service lifecycle.
  result = default(Options)
  assert parseOptions(@["server"], result)
proc forgotten() {.raises.} =
  ## An actual native export worker must not outlive aggregate destruction.
  var owner = default(Services)
  assert owner.start(started(), "guard")
  assert owner.startCheckpointExport("build/application-checkpoint-services-unclosed") ==
      ApplicationCheckpointFileError.None
proc main() {.raises.} =
  ## Genuine inactive moves and explicit joined aggregate close are positive controls.
  let mode = paramStr(1)
  if mode == "unclosed":
    forgotten() # Destructor must reach the actual managed child guard.
  elif mode == "moved":
    var owner = default(Services)
    assert owner.start(started(), "guard")
    assert owner.startCheckpointExport("build/application-checkpoint-services-moved") ==
        ApplicationCheckpointFileError.None
    var transferred = move(owner)
    transferred.close() # Live aggregate relocation must fail before any native address can dangle.
  elif mode == "shutdown":
    let owner = default(Services)
    discard owner.checkpointShutdown # No default fixed receipt exists.
  else:
    assert mode == "positive"
    var owner = default(Services)
    var relocated = move(owner)
    assert relocated.start(started(), "guard")
    assert relocated.startCheckpointExport("build/application-checkpoint-services-guard") ==
        ApplicationCheckpointFileError.None
    relocated.close()
    relocated.close()
    assert not relocated.checkpointShutdownPending
try:
  main() # Startup errors are distinct from exact runtime contract failures.
except:
  quit(2)
