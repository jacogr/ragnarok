# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "payload"}

## Receiver state and bytes cannot be replaced outside checked generation operations.
import ../../../src/app/ancestor/receiver as ancestor_receiver
let owner = default(AncestorReceiver)
discard owner.payload
