# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedBlockAuthorization", "early": ["publishBlockAuthorization(", "[1] expected: PreparedBlockAuthorization but got: PublishedBlockPreimages"]}

## Loose uses or a post-preimage successor cannot replace the exact authorization stage owner.

import ../../../src/state/[block_authorization, block_preimages]
var source: PublishedBlockPreimages
discard publishBlockAuthorization(source)
