# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"nominal","expected":"ChainView","early":["initApplicationChain(","[1] expected: ChainView but got: string"]}

## Text construction must not infer or default a writable state policy.

import ../../../src/app/chain as app_chain
discard initApplicationChain("{}")
