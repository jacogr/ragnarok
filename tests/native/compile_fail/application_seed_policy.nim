# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"nominal","expected":"StateStoreLimits","early":["initApplicationChain(","[2] expected: StateStoreLimits but got: ByteLimit"]}

## A byte ceiling cannot substitute for the complete caller-selected state policy.

import ../../../src/app/chain
import ../../../src/codec/bounded
discard initApplicationChain("{}", ByteLimit(1))
