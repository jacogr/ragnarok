# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A preimage hash is not an already derived 31-byte state key.
import ../../../src/codec/[state_service_values, bounded]
discard captureServiceValue(ServiceIndex(0), default(ServicePreimageHash), @[], ByteLimit(0))
