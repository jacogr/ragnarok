# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# Snapshot storage is private; safe callers cannot mutate its validated bytes.
import ../../../src/codec/owned
var frame = default(OwnedFrame)
frame.data.wire[0] = 7
