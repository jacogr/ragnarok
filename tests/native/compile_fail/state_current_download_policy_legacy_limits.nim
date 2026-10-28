# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Encoding a current schema cannot reinterpret a legacy completion policy object.
# @@Verification={"group": "nominal", "expected": "expected: CurrentDownloadLoopLimits but got: DownloadLoopLimits", "early": ["encodeCurrentDownloadPolicy", "[1] expected: CurrentDownloadLoopLimits but got: DownloadLoopLimits"]}
import ../../../src/app/current_download_policy as app_current_download_policy
import ../../../src/quic/block_download_loop as quic_block_download_loop
let legacy = default(DownloadLoopLimits)
discard encodeCurrentDownloadPolicy(legacy)
