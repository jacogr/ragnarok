# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import ../../../src/codec/[guarantees, assurances]
# Assurance and guarantor identities require deliberate domain conversion.
let wrong = GuaranteeCredential(validator: ValidatorIndex(1))
discard wrong
