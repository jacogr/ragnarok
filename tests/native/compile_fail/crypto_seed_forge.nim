# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose or fabricate crypto result/secret storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "storage"}

import ../../../src/crypto/primitives as crypto_primitives
discard EdSeed(storage: nil)
