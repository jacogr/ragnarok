# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting private bootstrap ownership and nominal scalar/resource domains.
## The top-level access or call must fail semantic compilation before any payload can be used.

# @@Verification={"group": "nominal", "expected": "ServiceProbeLimit", "early": ["findUnusedAccumulationService(", "[3] expected: ServiceProbeLimit but got: ByteLimit"]}

import ../../../src/state/accumulation_invocation as state_accumulation_invocation
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
discard findUnusedAccumulationService(default(StateStoreSnapshot), ServiceIndex(65536), ByteLimit(1))
