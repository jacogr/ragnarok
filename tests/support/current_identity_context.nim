# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit full-view/key policies for original selected-parent to genuine current continuation.
import ../../src/state/current/identities as current_identities
import ../../src/codec/bounded
const currentIdentityTestLimits* = CurrentIdentityLimits(blocks: ElementLimit(32),
    keys: ElementLimit(128), viewBytes: ByteLimit(33554432))
