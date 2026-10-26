# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A failure-only constructor cannot fabricate successful ownership of a validator signing key.
# @@Verification={"group": "contracts", "expected": "not reason == None"}
import ../../../src/crypto/primitives
discard cryptoFailure[EdSeed](CryptoError.None)
