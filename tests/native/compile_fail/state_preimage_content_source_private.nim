# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "source"}

## Caller cannot forge source-bound content authority or alter failed alternatives.
import ../../../src/state/preimage_content
var value = default(CheckedPreimageContent)
discard value.source
