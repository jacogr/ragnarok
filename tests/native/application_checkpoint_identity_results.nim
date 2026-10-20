# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime guards use opaque extraction helpers, with the same helpers exercised on genuine captured context.
import std/[assertions, cmdline, syncio]
import ../../src/app/[checkpoint_identity, chain]
import ../support/application_checkpoint_context
proc extract(outcome: ApplicationCheckpointIdentityResult) =
  ## Prevent compile-time propagation of an intentionally invalid discriminator from replacing the runtime witness.
  discard outcome.value
proc inspect(identity: ApplicationCheckpointIdentity, field: string) =
  ## Each branch reaches one real checked getter without knowing the caller's initialization state.
  case field
  of "block": discard identity.blockHash # Sealed-header identity requires initialized metadata.
  of "root": discard identity.stateRoot # Complete-root authority requires initialized metadata.
  of "slot": discard identity.slot # A time value must belong to initialized metadata.
  else: discard identity.parameters # Complete profiles have the same initialization gate.
proc main() {.raises.} =
  ## Positive mode reads an explicit hash-checked fixture; malformed/default cases do not depend on file availability.
  let mode = paramStr(1)
  if mode == "default":
    let absent = default(ApplicationCheckpointIdentityResult)
    extract(absent) # Default results never expose a successful identity.
  elif mode == "missing":
    let inactive = default(ApplicationChain)
    let refused = captureApplicationCheckpointIdentity(inactive)
    extract(refused) # Missing canonical heads grant no persistence context.
  elif mode == "positive":
    let owner = checkpointFixture()
    let captured = captureApplicationCheckpointIdentity(owner)
    extract(captured)
    let identity = captured.value
    assert identity.ready and sameApplicationCheckpoint(identity, identity)
    for field in ["block", "root", "slot", "parameters"]:
      inspect(identity, field) # The exact helpers also succeed on genuine initialized context.
  else:
    let absent = default(ApplicationCheckpointIdentity)
    inspect(absent, mode) # No default getter may succeed.
try:
  main() # Fixture/native startup errors remain distinct from contract assertions.
except:
  quit(2)
