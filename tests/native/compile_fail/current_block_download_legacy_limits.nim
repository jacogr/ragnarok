# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Legacy candidate limits cannot select current-only download preparation.
# @@Verification={"group": "nominal", "expected": "expected: CurrentCandidateLimits but got: ApplicationCandidateLimits", "early": ["begin", "[5] expected: CurrentCandidateLimits but got: ApplicationCandidateLimits"]}
import ../../../src/app/[current_block_download, current_block_input, candidate, chain]
import ../../../src/codec/header
var receiver = default(CurrentBlockDownload)
let owner = default(ApplicationChain)
let ancestors: seq[OwnedHeader] = @[]
let resources = default(CurrentBlockInputLimits)
let legacy = default(ApplicationCandidateLimits)
discard receiver.begin(owner, ancestors, resources, legacy)
