# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot construct or access private encoded-admission authority.
# @@Verification={"group":"privacy","expected":"RecordScan"}
import ../../../src/storage/record_codec as storage_record_codec
type Hidden = storage_record_codec.RecordScan
discard sizeof(Hidden)
