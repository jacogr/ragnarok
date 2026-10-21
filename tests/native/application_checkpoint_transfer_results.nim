# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque access helpers exercise the same runtime contracts on invalid and genuine prepared owners.
import std/[assertions, cmdline, syncio]
import ../../src/app/[chain, checkpoint_identity, checkpoint_transfer]
import ../../src/codec/bounded
import ../support/application_checkpoint_context
proc inspectLength(prepared: PreparedApplicationCheckpoint) =
  ## Only ready bytes grant an observable extent.
  discard prepared.byteLength
proc inspectIdentity(prepared: PreparedApplicationCheckpoint) =
  ## Only ready bytes carry captured application context.
  discard prepared.identity
proc inspectReason(prepared: PreparedApplicationCheckpoint) =
  ## Only capture refusal carries its typed cause.
  discard prepared.identityError
proc inspectCheckpoint(prepared: PreparedApplicationCheckpoint) =
  ## Default objects cannot invent a checkpoint refusal.
  discard prepared.checkpointError
proc main() {.raises.} =
  ## Genuine preparation and selected missing-head refusal also pass the checked access paths.
  let mode = paramStr(1)
  let inactive = default(ApplicationChain)
  var missing = prepareApplicationCheckpoint(inactive, ByteLimit(1000))
  var absent = default(PreparedApplicationCheckpoint)
  if mode == "default-length":
    inspectLength(absent) # Default owners have no buffer.
  elif mode == "default-identity":
    inspectIdentity(absent) # Default owners have no captured context.
  elif mode == "failed-length":
    inspectLength(missing) # Failed capture cannot retain prepared bytes.
  elif mode == "reason":
    inspectReason(absent) # Uninitialized alternatives carry no identity reason.
  elif mode == "checkpoint-reason":
    inspectCheckpoint(absent) # Uninitialized alternatives carry no checkpoint reason.
  else:
    assert mode == "positive"
    let owner = checkpointFixture()
    var prepared = prepareApplicationCheckpoint(owner, ByteLimit(100000))
    inspectLength(prepared)
    inspectIdentity(prepared)
    inspectReason(missing)
try:
  main() # Setup errors must not masquerade as checked assertion exits.
except:
  quit(2)
