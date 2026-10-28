# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A preimage hash is not an already derived 31-byte state key.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "StateKey"}

import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/bounded as codec_bounded
discard captureServiceValue(ServiceIndex(0), default(ServicePreimageHash), @[], ByteLimit(0))
