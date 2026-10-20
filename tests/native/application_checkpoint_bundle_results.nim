# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque helpers require runtime result selection and also succeed on genuine encoded bytes and precise capture refusal.
import std/[assertions, cmdline, syncio]
import ../../src/app/[chain, checkpoint_codec]
import ../../src/codec/bounded
import ../support/application_checkpoint_context
proc extract(outcome: ApplicationCheckpointResult[seq[byte]]) =
  ## Failed/default bytes cannot escape through compile-time constant propagation or unguarded variant fields.
  discard outcome.value
proc inspect(outcome: ApplicationCheckpointResult[seq[byte]]) =
  ## Only actual identity failure may expose its selected nested reason.
  discard outcome.identityError
proc main() {.raises.} =
  ## A genuine successful export and real missing-head refusal exercise both helpers used by misuse cases.
  let mode = paramStr(1)
  let inactive = default(ApplicationChain)
  let missing = encodeApplicationCheckpoint(inactive, ByteLimit(1000))
  if mode == "default":
    let absent = default(ApplicationCheckpointResult[seq[byte]])
    extract(absent) # Default results contain no complete bytes.
  elif mode == "missing":
    extract(missing) # Failed capture cannot supply an encoded prefix or complete file.
  elif mode == "reason":
    let absent = default(ApplicationCheckpointResult[seq[byte]])
    inspect(absent) # A default result has no selected nested identity reason.
  else:
    assert mode == "positive"
    let owner = checkpointFixture()
    let encoded = encodeApplicationCheckpoint(owner, ByteLimit(high(uint64)))
    extract(encoded)
    inspect(missing)
    assert encoded.value.len > 238
try:
  main() # Fixture/native errors must remain distinct from assertion exits.
except:
  quit(2)
