# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A transfer duration cannot accidentally be supplied as an absolute dispatcher tick.
# @@Verification={"group": "nominal", "expected": "DownloadTick", "early": ["expire", "[5] expected: DownloadTick but got: DownloadTimeout"]}

import ../../../src/quic/block_download_stream as quic_block_download_stream
import ../../../src/quic/transport as quic_transport
import ../../../src/app/block_download as app_block_download
var route = default(BlockDownloadStream)
var download = default(BlockDownload)
discard route.expire(download, default(BlockDownloadId), NativeStream(nil), DownloadTimeout(100))
