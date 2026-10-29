# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default current disk publication cannot expose an update for canonical installation.
import ../../src/app/disk/chain as disk_chain
let publication = default(PreparedCurrentDiskPublication)
discard publication.chainUpdate
