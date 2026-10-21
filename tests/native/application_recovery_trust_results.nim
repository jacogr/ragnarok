# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trust extraction guards have genuine captured-input and actual decoder-error controls.
import std/[assertions, cmdline, syncio]
import ../../src/app/[chain, checkpoint_identity, checkpoint_trust]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, header]
import ../support/application_checkpoint_context
proc extract(outcome: CheckpointTrustResult) =
  ## Opaque discriminator prevents replacing runtime evidence with static rejection.
  discard outcome.value
proc inspect(trust: TrustedApplicationCheckpoint) =
  ## Fixed identity requires initialized operator inputs.
  discard trust.identity
proc reason(outcome: CheckpointTrustResult) =
  ## Identity decoder reason requires that exact failure alternative.
  discard outcome.identityError
proc fileReason(outcome: CheckpointTrustResult) =
  ## A native path reason requires an actual selected-file failure.
  discard outcome.fileError
proc main() {.raises.} =
  ## Defaults/refusals and positive controls call the same helpers.
  case paramStr(1)
  of "default": extract(default(CheckpointTrustResult)) # Default results contain no trust.
  of "missing": extract(captureCheckpointTrust([], [], ByteLimit(0))) # Refusal cannot grant a header owner.
  of "identity": inspect(default(TrustedApplicationCheckpoint)) # Default trust has no scalar identity.
  of "file": fileReason(default(CheckpointTrustResult)) # Default status has no native file error.
  of "reason": reason(default(CheckpointTrustResult)) # Default status contains no decoder cause.
  else:
    let source = checkpointFixture()
    let expected = captureApplicationCheckpointIdentity(source).value
    let metadata = encodeApplicationCheckpointIdentity(expected, ByteLimit(238)).value
    let header = source.chainView.bestBlock.value.header
    var wire = newSeq[byte](header.headerInfo.value.consumed)
    assert encodeOwnedHeader(header, wire).error == HeaderError.None
    let captured = captureCheckpointTrust(metadata, wire, ByteLimit(high(uint64)))
    extract(captured)
    inspect(captured.value)
    reason(captureCheckpointTrust([], wire, ByteLimit(high(uint64))))
    fileReason(loadCheckpointTrust("", "", ByteLimit(238)))
try:
  main() # Fixture failures cannot masquerade as runtime assertions.
except:
  quit(2)
