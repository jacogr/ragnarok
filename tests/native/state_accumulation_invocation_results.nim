# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict selected-success probes for invocation bootstrap owners and deterministic-ID results.
## Dynamic modes must fail at result contracts instead of exposing default IDs, arguments or provenance.

import std/cmdline
import ../../src/state/accumulation_invocation as state_accumulation_invocation
import ../../src/state/accumulation_service as state_accumulation_service
import ../../src/state/store as state_store
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/composite as codec_composite
import ../../src/codec/header as codec_header

# Runtime selection preserves a real refused-result path without constant-invalid extraction during compilation.
let outcome = if paramStr(1) == "refused":
  prepareAccumulationInvocation(default(PreparedAccumulationService), default(StateEntropyWord),
      ServiceProbeLimit(1))
else: default(AccumulationInvocationResult[PreparedAccumulationInvocation]) # No success payload.
let owner = default(PreparedAccumulationInvocation)
let bound = default(BlockAccumulationInvocation)
case paramStr(1)
of "info": discard owner.bootstrapInfo.value # No fabricated seed metadata.
of "service": discard owner.bootstrapService.value # No forged service context.
of "arguments": discard owner.bootstrapArguments.value # No fake empty arguments.
of "projection": discard bound.bootstrapProjection.value # No fabricated bound success.
of "source": discard bound.bootstrapBlockService.value # No forged block provenance.
of "index": discard findUnusedAccumulationService(default(StateStoreSnapshot), ServiceIndex(0),
    ServiceProbeLimit(1)).value # Reserved indices carry no chosen ID.
else: discard outcome.value # Default/refused results require selected success too.
