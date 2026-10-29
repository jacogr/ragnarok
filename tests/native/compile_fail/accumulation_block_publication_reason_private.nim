# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Publication result payloads and discriminators remain private.

import "../../../src/state/accumulation/block/publication" as accumulation_block_publication
var outcome: AccumulationPublicationResult
discard outcome.status
