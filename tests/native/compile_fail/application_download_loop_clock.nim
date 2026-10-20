# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A scheduler clock cannot implicitly choose the dispatcher's native/adoption deadline domain.
# @@Verification={"group": "nominal", "expected": "DownloadLoopTick", "early": ["tick", "[2] expected: DownloadLoopTick but got: DownloadScheduleTick"]}
import ../../../src/quic/block_download_loop
import ../../../src/app/download_schedule
var dispatcher = default(BlockDownloadLoop)
discard dispatcher.tick(DownloadScheduleTick(1))
