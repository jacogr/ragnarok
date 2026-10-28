# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque helpers require runtime result selection and also succeed on genuine encoded bytes and precise capture refusal.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/app/chain as app_chain
import ../../src/app/checkpoint_codec as app_checkpoint_codec
import ../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../src/codec/bounded as codec_bounded
import ../../src/state/store as state_store
import ../../src/chain/genesis as chain_genesis
import ../support/app_checkpoint_context
proc extract(outcome: ApplicationCheckpointResult[seq[byte]]) =
  ## Failed/default bytes cannot escape through compile-time constant propagation or unguarded variant fields.
  discard outcome.value
proc inspect(outcome: ApplicationCheckpointResult[seq[byte]]) =
  ## Only actual identity failure may expose its selected nested reason.
  discard outcome.identityError
proc extractStore(outcome: ApplicationCheckpointResult[StateStore]) =
  ## Only a complete independently bound restored map can escape.
  discard outcome.value
proc inspectCheckpoint(outcome: ApplicationCheckpointResult[StateStore]) =
  ## A complete-map reason is available only on its matching failed alternative.
  discard outcome.checkpointError
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
  elif mode == "default-store":
    let absent = default(ApplicationCheckpointResult[StateStore])
    extractStore(absent) # Default recovery cannot expose a complete map.
  elif mode == "default-context":
    let absent = default(ApplicationCheckpointIdentity)
    let refused = decodeApplicationCheckpoint([], absent, genesisStoreLimits(), ByteLimit(1000))
    extractStore(refused) # No default context can authorize restored state.
  elif mode == "checkpoint-reason":
    let absent = default(ApplicationCheckpointResult[StateStore])
    inspectCheckpoint(absent) # No default result carries a selected complete-map refusal.
  else:
    assert mode == "positive"
    let owner = checkpointFixture()
    let encoded = encodeApplicationCheckpoint(owner, ByteLimit(high(uint64)))
    extract(encoded)
    let expected = captureApplicationCheckpointIdentity(owner).value
    let loaded = decodeApplicationCheckpoint(encoded.value, expected, genesisStoreLimits(),
        ByteLimit(high(uint64)))
    extractStore(loaded)
    let malformed = decodeApplicationCheckpoint(encoded.value.toOpenArray(0, 237), expected,
        genesisStoreLimits(), ByteLimit(238))
    inspectCheckpoint(malformed) # A genuine short-map refusal succeeds through the exact checked nested-reason helper.
    inspect(missing)
    assert encoded.value.len > 238
try:
  main() # Fixture/native errors must remain distinct from assertion exits.
except:
  quit(2)
