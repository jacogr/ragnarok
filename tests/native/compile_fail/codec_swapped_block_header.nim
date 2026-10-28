# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects static component/parent schema identities.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal","expected": "got: Component[Guarantees] but wanted: Component[Header]"}

import ../../../src/codec/block_codec as codec_block_codec

var source: Block = default(Block)
var wrong: GuaranteeComponent = default(GuaranteeComponent)
source.header = wrong
