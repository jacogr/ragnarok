# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite writer retirement and closed result extraction retain real native contracts.
import std/assertions
import std/cmdline
import std/syncio
import std/posix/posix
import ../../src/app/chain as app_chain
import ../../src/app/checkpoint_writer as app_checkpoint_writer
import ../../src/app/checkpoint_file as app_checkpoint_file
import ../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/chain/genesis as chain_genesis
import ../support/app_checkpoint_context
proc extract(outcome: ApplicationCheckpointFileResult[ApplicationCheckpointIdentity]) =
  ## Only durable publication supplies a fixed identity receipt.
  discard outcome.value
proc forgotten() =
  ## Actual native opening makes forgotten retirement a genuine destructor violation.
  var writer = default(ApplicationCheckpointWriter)
  assert writer.openApplicationCheckpointWriter("build/application-checkpoint-writer-guard") ==
      ApplicationCheckpointFileError.None
proc main() {.raises.} =
  ## Default and closed writers cannot authorize success; the same helper passes for genuine publication.
  let mode = paramStr(1)
  if mode == "unclosed":
    forgotten() # No automatic cleanup may conceal a forgotten live native owner.
  else:
    var path = "build/application-checkpoint-writer-guard"
    var lockPath = path & ".lock"
    defer:
      discard posix.unlink(path.toCString())
      discard posix.unlink(lockPath.toCString()) # Only closed owners precede test-only lock cleanup.
    var writer = default(ApplicationCheckpointWriter)
    defer: discard writer.close()
    let inactive = default(ApplicationChain)
    if mode == "default":
      extract(writer.save(inactive, ByteLimit(1000))) # No default owner grants a publication receipt.
    elif mode == "closed":
      assert writer.openApplicationCheckpointWriter(path) == ApplicationCheckpointFileError.None
      assert writer.close() == ApplicationCheckpointFileError.None
      extract(writer.save(inactive, ByteLimit(1000))) # Closed owner refuses before reading canonical inputs.
    else:
      let owner = checkpointFixture()
      assert writer.openApplicationCheckpointWriter(path) == ApplicationCheckpointFileError.None
      extract(writer.save(owner, ByteLimit(100000)))
      assert writer.close() == ApplicationCheckpointFileError.None
      if mode == "closed":
        extract(writer.save(owner, ByteLimit(100000))) # Previously open ownership cannot authorize another publication.
      else:
        assert mode == "positive" and not writer.opened
try:
  main() # Setup exceptions must not count as checked assertion exits.
except:
  quit(2)
