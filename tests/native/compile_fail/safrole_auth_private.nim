# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authentication result state/payload remain private across default, failed and successful outcomes.
import ../../../src/state/safrole_authentication
var hidden = default(SafroleAuthResult)
discard hidden.completed
