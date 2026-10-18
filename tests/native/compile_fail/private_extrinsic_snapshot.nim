# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection keeps retained composition bytes and child descriptors private.
import ../../../src/codec/block_codec

var owner: OwnedExtrinsic
discard owner.data
