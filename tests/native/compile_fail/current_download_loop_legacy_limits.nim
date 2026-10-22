# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Legacy resource and completion policies cannot configure current-only download dispatch.
# @@Verification={"group": "nominal", "expected": "expected: CurrentDownloadLoopLimits but got: DownloadLoopLimits", "early": ["configure", "[5] expected: CurrentDownloadLoopLimits but got: DownloadLoopLimits"]}
import ../../../src/quic/[current_block_download_loop, block_download_loop]
import ../../../src/app/[services, download_schedule]
import ../../../src/codec/header
var dispatcher = default(CurrentDownloadLoop)
var owner = default(Services)
let peers: seq[DownloadPeerId] = @[]
let ancestors: seq[OwnedHeader] = @[]
let legacy = default(DownloadLoopLimits)
discard dispatcher.configure(owner, peers, ancestors, legacy, CurrentDownloadLoopTick(0))
