# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External code cannot replace a bound native handle behind checked callback routing.
# @@Verification={"group": "privacy", "expected": "handle"}

import "../../../src/jamnp-s/block/download/stream" as block_download_stream
var route = default(BlockDownloadStream)
discard route.handle
