# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict selected-result runtime probes for retained accumulation provisions and canonical request queries.
## Dynamic origins distinguish initialized refusals from absent/default owners; no failed case may expose payload.

import std/cmdline
import ../../src/state/accumulation_effects as state_accumulation_effects
import ../../src/state/accumulation_context as state_accumulation_context
import ../../src/state/preimages as state_preimages
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite
import ../../src/codec/state_requests as codec_state_requests
import ../../src/codec/state_service_values as codec_state_service_values
import ../../src/codec/state_trie as codec_state_trie
import ../../src/crypto/primitives as crypto_primitives
import ../support/state_accumulation_effect_context

## Prepare one genuine outstanding request and return a captured effect owner through public APIs only.
proc prepared(): AccumulationEffects =
  let raw = @[9'u8, 8, 7]
  let hash = ServicePreimageHash(array[32, byte](blake2b256(raw).value))
  let key = serviceRequestKey(ServiceIndex(42), hash, RequestLength(3), ByteLimit(32)).value
  prepareAccumulationEffects(preparedEffectContexts(@[StateEntry(key: key, value: @[0'u8])])).value

# Only actual provision refusals need live accounts; default-result probes preserve dynamic construction.
let owner = if paramStr(1) in ["index", "record", "unknown", "duplicate", "limit"]: prepared()
else: default(AccumulationEffects) # Other modes intentionally retain no initialized effects.

let config = AccumulationProvisionLimits(items: ElementLimit(1), perBlob: ByteLimit(3),
    totalBlobBytes: ByteLimit(3))
let outcome = if paramStr(1) == "refused": recordAccumulationProvision(owner, ServiceIndex(42), [
    9'u8, 8, 7], config)
else: default(AccumulationEffectResult[AccumulationEffects]) # Dynamic alternatives prevent static-invalid extraction.
let provision = default(AccumulationProvision)
case paramStr(1)
of "info": discard provision.provisionInfo.value # No default target/length facts.
of "bytes": discard provision.copyProvisionBytes.value # Default handles are not valid empty blobs.
of "index": discard owner.effectContext(AccumulationDimension.Regular).value.effectProvisionAt(
    AccumulationProvisionIndex(0)).value # Empty sets contain no ordinal zero.
of "record": discard recordAccumulationProvision(owner, ServiceIndex(42), [0'u8],
    config).value # Missing requests carry no updated owner.
of "unknown": discard recordAccumulationProvision(owner, ServiceIndex(99), [9'u8, 8, 7],
    config).value # Missing targets carry no updated owner.
of "duplicate":
  # First capture is valid; repeating that exact pair must refuse without a success payload.
  let first = recordAccumulationProvision(owner, ServiceIndex(42), [9'u8, 8, 7], config).value
  discard recordAccumulationProvision(first, ServiceIndex(42), [9'u8, 8, 7], config).value
of "limit": discard recordAccumulationProvision(owner, ServiceIndex(42), [9'u8, 8, 7], default(
    AccumulationProvisionLimits)).value # Local refusal carries no partial progress.
of "query": discard preimageRequested(default(StateStoreSnapshot), ServiceIndex(42), default(
    ServicePreimageHash), RequestLength(0)).value # Invalid maps cannot supply a requested/unrequested verdict.
else: discard outcome.value # Defaults and actual refused pair results require selected success.
