# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ordinary binaries compile without the crypto provider and cannot claim enabled integration
## success.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import "../../../src/jamnp-s/integration"
assert not IntegrationEnabled
let key = preimageKey([1'u8, 2, 3])
assert key.error == IntegrationError.Crypto
let empty = default(IntegrationResult[VerifiedDigest])
assert empty.error == IntegrationError.Uninitialized
echo "Nimony integration: disabled provider returns typed refusal without native crypto linkage"
