# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PublishedRecentHistory", "early": ["prepareBlockPreimages(", "[1] expected: PublishedRecentHistory but got: AdmittedPreimages"]}

## Loose admission or completed recent history cannot replace this stage's exact owner.

import ../../../src/state/[block_preimages, preimages]
var source: AdmittedPreimages
var config: BlockPreimageConfig
discard prepareBlockPreimages(source, config)
