# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Code identities cannot silently substitute for preimage lookup identities.
import ../../../src/codec/[state_service_values, work_digest, bounded]
discard servicePreimageKey(ServiceIndex(0), default(CodeHash), ByteLimit(32))
