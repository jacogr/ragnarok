# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Legacy resource and completion policies cannot configure current-only download dispatch.
# @@Verification={"group": "nominal", "expected": "expected: CurrentDownloadLoopLimits but got: DownloadLoopLimits", "early": ["configure", "[5] expected: CurrentDownloadLoopLimits but got: DownloadLoopLimits"]}
import ../../../src/quic/current_block_download_loop as quic_current_block_download_loop
import ../../../src/quic/block_download_loop as quic_block_download_loop
import ../../../src/app/services as app_services
import ../../../src/app/download_schedule as app_download_schedule
import ../../../src/codec/header as codec_header
var dispatcher = default(CurrentDownloadLoop)
var owner = default(Services)
let peers: seq[DownloadPeerId] = @[]
let ancestors: seq[OwnedHeader] = @[]
let legacy = default(DownloadLoopLimits)
discard dispatcher.configure(owner, peers, ancestors, legacy, CurrentDownloadLoopTick(0))
