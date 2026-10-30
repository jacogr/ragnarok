# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Receiver identity cannot be retargeted after binding.
# @@Verification={"group": "privacy", "expected": "receiver"}

import "../../../src/jamnp-s/block/download/stream" as block_download_stream
var route = default(BlockDownloadStream)
discard route.receiver
