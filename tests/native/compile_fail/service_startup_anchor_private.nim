# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External producers cannot construct configured checkpoint provenance by assigning the private hash.
# @@Verification={"group": "privacy", "expected": "hash"}
import ../../../src/app/services
import ../../../src/chain/genesis
var anchor = default(StartupBlockAnchor)
anchor.hash = default(BlockHash)
