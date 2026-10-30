# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Encoding a current schema cannot reinterpret a legacy completion policy object.
# @@Verification={"group": "nominal", "expected": "expected: CurrentDownloadLoopLimits but got: DownloadLoopLimits", "early": ["encodeCurrentDownloadPolicy", "[1] expected: CurrentDownloadLoopLimits but got: DownloadLoopLimits"]}
import ../../../src/app/current/download/policy as current_download_policy
import "../../../src/jamnp-s/block/download/loop" as block_download_loop
let legacy = default(DownloadLoopLimits)
discard encodeCurrentDownloadPolicy(legacy)
