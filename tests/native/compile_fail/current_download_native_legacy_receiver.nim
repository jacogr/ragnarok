# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current native routing cannot bind a legacy receiver or grant it current execution authority.
# @@Verification={"group": "nominal", "expected": "expected: CurrentBlockDownload but got: BlockDownload", "early": ["bindStream", "[2] expected: CurrentBlockDownload but got: BlockDownload"]}
import "../../../src/app/block/download" as block_download
import "../../../src/app/current/block/download" as current_block_download
import "../../../src/quic/current/block/download/stream" as current_block_download_stream
import ../../../src/quic/transport
var route = default(CurrentDownloadStream)
var legacy = default(BlockDownload)
discard route.bindStream(legacy, CurrentBlockDownloadId(0), NativeStream(nil),
  default(CurrentDownloadStreamLimits), CurrentDownloadTick(0))
