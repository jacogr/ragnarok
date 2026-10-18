# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose or fabricate crypto result/secret storage.
import ../../../src/crypto/primitives
discard EdSeed(storage: nil)
