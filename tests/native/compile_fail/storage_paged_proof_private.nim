# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private evidence/result backing cannot be forged or mutated by consumers.
# @@Verification={"group":"privacy","expected":"record"}
import ../../../src/storage/paged/stream as paged_stream
let captured = default(PagedProofLookup)
discard captured.record
