# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service identities cannot silently select mapping ordinals.
import ../../../src/codec/[state_composition, state_accounts]
discard stateEntryAt(default(StateSnapshot), ServiceIndex(0))
