# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A caller cannot manufacture transition success by changing its discriminator.
import ../../../src/state/entropy
var hidden = default(EntropyTransitionResult[EntropyTimeUpdate])
hidden.status = EntropyTransitionError.None
