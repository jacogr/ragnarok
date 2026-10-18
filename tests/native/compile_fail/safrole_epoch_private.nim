# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private result/owner fields cannot be read or retagged by application callers.
import ../../../src/state/safrole_markers
var hidden = default(SafroleMarkers)
discard hidden.epochValue
