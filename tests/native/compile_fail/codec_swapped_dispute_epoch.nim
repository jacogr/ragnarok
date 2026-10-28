# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects the public disputes type/ownership boundary.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: GuaranteeSlot but wanted: DisputeEpoch"}

import ../../../src/codec/disputes as codec_disputes
import ../../../src/codec/guarantees as codec_guarantees

var value: Verdict
value.epoch = GuaranteeSlot(1)
