# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects the public disputes type/ownership boundary.
import ../../../src/codec/[disputes, guarantees]

var value: Judgment
value.signature = GuaranteeSignature(default(array[64, byte]))
