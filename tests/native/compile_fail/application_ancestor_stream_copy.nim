# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <AncestorStream>", "build_name": "application-ancestor-stream-copy"}

## Native callback bindings cannot duplicate borrowed stream handles or partial write offsets.
import ../../../src/quic/ancestor_stream
var original = default(AncestorStream)
var duplicate = original
discard original.active
discard duplicate.active
