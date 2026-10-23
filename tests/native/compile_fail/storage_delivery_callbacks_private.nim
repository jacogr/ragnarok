# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot construct or access private encoded-admission authority.
# @@Verification={"group":"privacy","expected":"RecordDeliveryCallbacks"}
import ../../../src/storage/record_codec
type Hidden = record_codec.RecordDeliveryCallbacks[int]
discard sizeof(Hidden)
