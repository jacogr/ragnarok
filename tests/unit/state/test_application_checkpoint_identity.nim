# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_identity_arc_release"}

## Exact selected-head facts, profile mismatch and detached scalar ownership guard checkpoint identity capture.

import std/[assertions, syncio]
import ../../../src/app/checkpoint/identity as checkpoint_identity
import ../../../src/app/chain
import ../../../src/chain/[genesis, provider, parameters]
import ../../support/[application_checkpoint_context, arc_evidence]
proc detached(): ApplicationCheckpointIdentity {.raises.} =
  ## Source application, history, map and header retire before the caller uses metadata.
  captureApplicationCheckpointIdentity(checkpointFixture()).value
proc cycle(owner: ApplicationChain, expected: ApplicationCheckpointIdentity) =
  ## Captures and copied scalar tuples release all temporary borrowed views on return.
  assert sameApplicationCheckpoint(captureApplicationCheckpointIdentity(owner).value, expected)
proc main() {.raises.} =
  ## Different block identities, posterior maps and complete parameter tuples cannot collapse to root-only agreement.
  let absent = default(ApplicationCheckpointIdentity)
  assert not absent.ready and not sameApplicationCheckpoint(absent, absent)
  let inactive = default(ApplicationChain)
  let refused = captureApplicationCheckpointIdentity(inactive)
  assert refused.error == ApplicationCheckpointIdentityError.MissingHead
  let explicit = captureApplicationCheckpointIdentity(checkpointFixture(
      CheckpointFixtureVariant.ExplicitExpunge))
  assert explicit.error == ApplicationCheckpointIdentityError.InvalidParameters
  let owner = checkpointFixture()
  let selected = owner.chainView.bestBlock.value
  let captured = captureApplicationCheckpointIdentity(owner).value
  assert captured.ready and sameApplicationCheckpoint(captured, detached())
  assert array[32, byte](captured.blockHash) == array[32, byte](selected.blockHash)
  assert array[32, byte](captured.stateRoot) == array[32, byte](selected.stateRoot)
  assert uint32(captured.slot) == selected.slot
  assert captured.parameters.encodeParameters == selected.chainParameters.encodeParameters
  for variant in [CheckpointFixtureVariant.Header, CheckpointFixtureVariant.Profile,
      CheckpointFixtureVariant.State]:
    let other = captureApplicationCheckpointIdentity(checkpointFixture(variant)).value
    assert not sameApplicationCheckpoint(captured,
        other) # Every independent persistence-relevant mismatch refuses equality.
  cycle(owner, captured)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(owner, captured) # Fixed metadata retains no source graph between captures.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_checkpoint_identity", 1000, before, after)
  echo "PASS application checkpoint identity: exact canonical context, complete profile and detached scalars"
try:
  main() # Missing or invalid fixture inputs cannot become a successful empty witness.
except:
  quit(2)
