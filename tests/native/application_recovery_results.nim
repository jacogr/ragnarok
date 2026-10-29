# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque runtime result helpers reject default/refused payloads with genuine success controls.
import std/[assertions, cmdline, syncio]
import ../../src/app/chain
import ../../src/app/checkpoint/[identity as checkpoint_identity, recovery as checkpoint_recovery,
    codec as checkpoint_codec]
import ../../src/codec/bounded
import ../../src/chain/[genesis, provider]
import ../../src/codec/header
import ../../src/state/store
import ../support/application_checkpoint_context
proc extract(outcome: ApplicationRecoveryResult) =
  ## The helper cannot prove a caller discriminator at compile time.
  discard outcome.value
proc inspectState(outcome: ApplicationRecoveryResult) =
  ## Nested error access requires the actual matching refusal.
  discard outcome.stateError
proc inspectEnvelope(outcome: ApplicationRecoveryResult) =
  ## Envelope reasons are inaccessible on default or successful recovery.
  discard outcome.envelopeFailure
proc inspectFile(outcome: ApplicationRecoveryResult) =
  ## A file failure reason requires that exact alternative.
  discard outcome.fileFailure
proc main() {.raises.} =
  ## Genuine binding and missing-map controls exercise both guarded helpers.
  let mode = paramStr(1)
  if mode == "default":
    extract(default(ApplicationRecoveryResult)) # Defaults contain no application graph.
  elif mode == "missing":
    extract(recoverApplicationChain(default(StateStoreSnapshot), [], default(
        ApplicationCheckpointIdentity)))
  elif mode == "wrong-file":
    inspectFile(default(ApplicationRecoveryResult)) # Defaults contain no file read receipt.
  elif mode == "wrong-envelope":
    inspectEnvelope(default(ApplicationRecoveryResult)) # Default status grants no decoder reason.
  elif mode == "wrong-reason":
    inspectState(default(ApplicationRecoveryResult)) # Default status cannot grant a nested map reason.
  else:
    let owner = checkpointFixture()
    let expected = captureApplicationCheckpointIdentity(owner).value
    let header = owner.chainView.bestBlock.value.header
    var wire = newSeq[byte](header.headerInfo.value.consumed)
    assert encodeOwnedHeader(header, wire).error == HeaderError.None
    extract(recoverApplicationChain(owner.stateSnapshot.value, wire, expected))
    inspectEnvelope(decodeRecoveryCheckpoint([], wire, expected, genesisStoreLimits(), ByteLimit(238)))
    inspectFile(loadRecoveryCheckpoint("", wire, expected, genesisStoreLimits(), ByteLimit(238)))
    inspectState(recoverApplicationChain(default(StateStoreSnapshot), wire, expected))
try:
  main() # Native fixture errors remain distinct from assertion failures.
except:
  quit(2)
