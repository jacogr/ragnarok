# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Assurance signature bytes cannot occupy a guarantee credential implicitly.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[guarantees, assurances]
let wrong = GuaranteeCredential(signature: AssuranceSignature())
discard wrong
