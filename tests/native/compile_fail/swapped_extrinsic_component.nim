# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects static component/parent schema identities.
import ../../../src/codec/block_codec

var source: Extrinsic = default(Extrinsic)
var wrong: PreimageComponent = default(PreimageComponent)
source.tickets = wrong
