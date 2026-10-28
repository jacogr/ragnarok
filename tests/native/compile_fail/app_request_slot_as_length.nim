# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## History timeslots cannot substitute for the key's advertised E4 length.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "RequestLength"}

import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/codec/bounded as codec_bounded
discard serviceRequestKey(ServiceIndex(0), default(ServicePreimageHash), RequestSlot(0), ByteLimit(32))
