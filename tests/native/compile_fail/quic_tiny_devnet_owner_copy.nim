# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite native transport owners cannot duplicate their stable callback addresses.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <DevnetNetwork>", "build_name": "tiny-devnet-owner-copy"}
import ../../../src/quic/devnet as quic_devnet
var original = DevnetNetwork()
var duplicate = original
discard original.finished
discard duplicate.finished
original.close()
duplicate.close()
