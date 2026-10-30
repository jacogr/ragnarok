# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private owned source fragment; the projector removes exactly these three comment lines.
proc revokeNativeWindows(writer: nil ScalarMemoryWriter) {.inline.} =
  ## Every public writer store and seal invalidates raw leases before COW or publication, including failures/unchanged seals.
  if writer != nil and writer.nativeEpoch != high(uint64): inc writer.nativeEpoch

