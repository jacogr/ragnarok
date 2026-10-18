# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import ../../../src/codec/[guarantees, assurances]
# Assurance signature bytes cannot occupy a guarantee credential implicitly.
let wrong = GuaranteeCredential(signature: AssuranceSignature())
discard wrong
