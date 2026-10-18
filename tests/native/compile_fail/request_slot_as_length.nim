# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## History timeslots cannot substitute for the key's advertised E4 length.
import ../../../src/codec/[state_requests, bounded]
discard serviceRequestKey(ServiceIndex(0), default(ServicePreimageHash), RequestSlot(0), ByteLimit(32))
