# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_services_context_arc_release"}

## Services capture one canonical pair only outside execution leases; prepared output retains no canonical graph.
import std/[assertions, syncio, envvars]
import ../../../src/app/[services, options, checkpoint_identity, checkpoint_transfer, checkpoint_codec]
import ../../../src/codec/bounded
import ../../support/[application_checkpoint_context, arc_evidence]
proc cycle(owner: Services, expected: ApplicationCheckpointIdentity) =
  ## Temporary prepared bytes and fixed identity captures retire before each observation.
  let captured = owner.checkpointIdentity
  assert captured.error == ApplicationCheckpointIdentityError.None
  assert sameApplicationCheckpoint(captured.value, expected)
  var prepared = owner.prepareCheckpoint(ByteLimit(100000))
  assert prepared.error == ApplicationCheckpointError.None
  assert sameApplicationCheckpoint(prepared.identity, expected) and prepared.byteLength > 238
proc main() {.raises.} =
  ## Missing, configured, closed and restarted canonical service lifetimes preserve typed capture and explicit extent policy.
  var owner = default(Services)
  defer: owner.close()
  assert owner.checkpointIdentity.error == ApplicationCheckpointIdentityError.MissingHead
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-writes", "0", "--state-write-bytes", "0"], options)
  let expected = captureApplicationCheckpointIdentity(checkpointFixture()).value
  assert owner.start(options, "checkpoint capture")
  var limited = owner.prepareCheckpoint(ByteLimit(0))
  assert limited.error == ApplicationCheckpointError.LimitExceeded
  cycle(owner, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(owner, expected) # The canonical owner remains stable while each detached byte owner retires.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_checkpoint_services_context", 1000, before, after)
  owner.close()
  assert owner.checkpointIdentity.error == ApplicationCheckpointIdentityError.MissingHead
  assert owner.start(options, "checkpoint restart")
  cycle(owner, expected)
  owner.close()
  echo "PASS service checkpoint context: canonical capture, detached preparation, closed/restarted lifetimes and lease guards"
try:
  main() # Fixture/service startup errors cannot pass the canonical capture witness.
except:
  quit(2)
