# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Integration callers cannot forge success or mutate private snapshot/bank storage.
import ../../../src/quic/integration
import ../../../src/codec/owned
discard VerifiedDigest(data: nil)
