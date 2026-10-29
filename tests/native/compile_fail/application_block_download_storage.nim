# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot rewrite the private request hash, framing positions or captured canonical context.
# @@Verification={"group": "privacy", "expected": "pending"}

import "../../../src/app/block/download" as block_download
var download = default(BlockDownload)
discard download.pending
