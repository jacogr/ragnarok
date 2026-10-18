# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import ../../../src/codec/guarantees
# External callers cannot reach the private mutable record sequence.
var owner: OwnedGuarantees
discard owner.data
