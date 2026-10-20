# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PublishedBlockPreimages", "early": ["prepareBlockAuthorization(", "[1] expected: PublishedBlockPreimages but got: CoreAuthorizer"]}

## Loose uses or a post-preimage successor cannot replace the exact authorization stage owner.

import ../../../src/state/[block_authorization, authorization]
var source: CoreAuthorizer
var config: BlockAuthorizationConfig
discard prepareBlockAuthorization(source, config)
